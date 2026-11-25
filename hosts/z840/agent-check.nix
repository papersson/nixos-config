{ config, lib, pkgs, ... }:

# Check-only SSH endpoint for cloud agent sessions. A session on the tailnet
# with tag:agent (which the tailnet policy limits to z840 tcp:2222 and nothing
# else) pipes a git bundle of papersson/apps into
#
#   git bundle create - HEAD | ssh -p 2222 -i KEY agent-check@100.77.126.122
#
# and z840 runs `nix flake check` on that commit, streaming the log back and
# exiting with the check's status. The session learns whether its commit
# passes before it pushes, using z840's store and cache instead of building
# everything from scratch in its own container.
#
# Authentication on 2222 is the tailnet ACL: sshd accepts any public key for
# exactly one user, agent-check, so each session can bring a throwaway key.
# Everything else is locked down by the Match block: no shell (ForceCommand),
# no TTY, no forwarding of any kind, and no other user can log in on 2222.
# agent-check is not a nix trusted user, so it cannot change substituters or
# import unsigned paths; it can only ask the daemon to build.
let
  home = "/var/lib/agent-check";
  # 200 MiB: the apps bundle is a few MB; this only stops a runaway upload.
  maxBundleBytes = 200 * 1024 * 1024;

  check = pkgs.writeShellApplication {
    name = "agent-check";
    runtimeInputs = [
      pkgs.git
      config.nix.package
      pkgs.coreutils
      pkgs.gawk
      pkgs.jq
      pkgs.util-linux # logger
      config.services.tailscale.package
    ];
    # SSH_ORIGINAL_COMMAND is deliberately ignored: the only thing a caller
    # controls is the bundle on stdin.
    text = ''
      umask 077
      work=$(mktemp -d "${home}/run.XXXXXXXX")
      trap 'rm -rf "$work"' EXIT

      # Read one byte past the cap so an oversized upload is reported as such
      # rather than as a corrupt bundle.
      head -c ${toString (maxBundleBytes + 1)} > "$work/in.bundle"
      size=$(stat -c %s "$work/in.bundle")
      if [ "$size" -gt ${toString maxBundleBytes} ]; then
        echo "z840: bundle exceeds ${toString maxBundleBytes} bytes, refusing" >&2
        exit 2
      fi
      if ! rev=$(git bundle list-heads "$work/in.bundle" 2>/dev/null \
                 | awk '$2 == "HEAD" { print $1; found = 1; exit } END { exit !found }'); then
        echo "z840: stdin is not a git bundle with HEAD (send: git bundle create - HEAD)" >&2
        exit 2
      fi
      git clone -q --no-checkout "$work/in.bundle" "$work/repo"

      peer=''${SSH_CONNECTION%% *}
      who=$(tailscale whois --json "$peer" 2>/dev/null \
            | jq -r '"\(.Node.Name // "?") tags=\((.Node.Tags // []) | join(","))"' 2>/dev/null) \
            || who="unknown"
      logger -t agent-check "peer=$peer node=$who rev=$rev size=$size"

      echo "z840: checking $rev"
      status=0
      timeout 40m nix flake check -L --keep-going "git+file://$work/repo?rev=$rev" || status=$?
      if [ "$status" -eq 0 ]; then
        echo "z840: $rev passed"
      else
        echo "z840: $rev failed"
      fi
      exit "$status"
    '';
  };

  # sshd refuses an AuthorizedKeysCommand under a group-writable directory
  # such as /nix/store, so this lives in /etc as a real root-owned file.
  # It is called as `%u %k %t` and accepts any key, but only for agent-check:
  # for every other user it prints nothing, so no key works on port 2222.
  keysScript = ''
    #!${pkgs.bash}/bin/bash
    [ "$1" = agent-check ] || exit 0
    case "$3" in ssh-* | ecdsa-* | sk-*) ;; *) exit 0 ;; esac
    [[ "$2" =~ ^[A-Za-z0-9+/]+=*$ ]] || exit 0
    printf 'restrict %s %s\n' "$3" "$2"
  '';
in
{
  users.groups.agent-check = { };
  users.users.agent-check = {
    isSystemUser = true;
    group = "agent-check";
    home = home;
    createHome = true;
    shell = pkgs.bash;
  };

  environment.etc."ssh/agent-check-keys" = {
    text = keysScript;
    mode = "0755";
  };

  services.openssh = {
    ports = [ 22 2222 ];
    # openFirewall would open every port in `ports` on every interface. Keep
    # 22 open as before and open 2222 on the tailnet interface only.
    openFirewall = false;
    extraConfig = ''
      Match LocalPort 2222
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        AuthorizedKeysFile none
        AuthorizedKeysCommand /etc/ssh/agent-check-keys %u %k %t
        AuthorizedKeysCommandUser nobody
        ForceCommand ${lib.getExe check}
        PermitTTY no
        AllowTcpForwarding no
        AllowAgentForwarding no
        AllowStreamLocalForwarding no
        X11Forwarding no
        PermitTunnel no
    '';
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 2222 ];
}

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
# The same endpoint reads nixbot's results for papersson/apps, so a session
# can see why CI failed without the web UI:
#
#   ssh -p 2222 agent-check@z840 'log 116'                       # summary
#   ssh -p 2222 agent-check@z840 'log 116 pull_request/preview'  # one log
#
# See `usage` below and docs/ci.md for the full syntax.
#
# And it drives the Android emulator (hosts/z840/android.nix): `android
# <verb>` runs android-ctl as the android user, and the one TCP forward port
# 2222 allows, to 10.231.0.2:9333, is Chrome for Android's DevTools protocol:
#
#   ssh -p 2222 agent-check@z840 'android screenshot' > phone.png
#   ssh -p 2222 -N -L 9222:10.231.0.2:9333 agent-check@z840   # then --cdp
#
# Authentication on 2222 is the tailnet ACL: sshd accepts any public key for
# exactly one user, agent-check, so each session can bring a throwaway key.
# Everything else is locked down by the Match block: no shell (ForceCommand),
# no TTY, no forwarding but the emulator's DevTools port, and no other user
# can log in on 2222.
# agent-check is not a nix trusted user, so it cannot change substituters or
# import unsigned paths; it can only ask the daemon to build.
let
  home = "/var/lib/agent-check";
  # 200 MiB: the apps bundle is a few MB; this only stops a runaway upload.
  maxBundleBytes = 200 * 1024 * 1024;

  usage = ''
    usage: (no command) | check      read a git bundle on stdin, run nix flake check
           log <build>               summary of nixbot build <build> of papersson/apps
           log <build> <name>        log of effect <kind>/<name> or check attr <name>
           log runs                  the 30 latest effect runs, with run ids
           log run <id>              log of effect run <id> (e.g. a scheduled one)
           add --all to a log command for the whole log, not the last 2000 lines
           android <verb> [args]     drive the Android emulator (android help)
           -N -L 9222:10.231.0.2:9333 forward Chrome for Android's DevTools protocol'';

  # Reads nixbot's database and stored logs, as user nixbot (the only user
  # that can read /var/lib/nixbot), through the sudo rule below. Read-only:
  # every transaction is read_only, and no path is built from caller input;
  # log files are found from ids and attr names the database returns. Only
  # papersson/apps is reachable. nixbot redacts effect secrets before it
  # stores a log; this never touches secrets files, credentials or env.
  logReader = pkgs.writeShellApplication {
    name = "nixbot-agent-log";
    runtimeInputs = [
      config.services.postgresql.package
      pkgs.zstd
      pkgs.coreutils
      config.nix.package
    ];
    text = ''
      cd /
      export HOME=/var/lib/nixbot
      logs=/var/lib/nixbot/logs
      cap=2000
      all=0
      args=()
      for a in "$@"; do
        if [ "$a" = --all ]; then all=1; else args+=("$a"); fi
      done
      set -- "''${args[@]}"

      die() { echo "z840: $*" >&2; exit 2; }
      q() {
        PGOPTIONS='-c default_transaction_read_only=on' \
          psql -X -q -v ON_ERROR_STOP=1 -d nixbot "$@"
      }
      project="(select id from projects where forge = 'github' and owner = 'papersson' and name = 'apps')"

      show() { # file: print the last $cap lines, or all of it
        local total
        total=$(wc -l < "$1")
        if [ "$all" -eq 1 ] || [ "$total" -le "$cap" ]; then
          cat "$1"
        else
          echo "z840: last $cap of $total lines (add --all for the whole log)"
          tail -n "$cap" "$1"
        fi
      }

      umask 077
      tmp=$(mktemp)
      trap 'rm -f "$tmp"' EXIT

      effect_log() { # run id, status
        local f="$logs/effects/$1.zst"
        [ -f "$f" ] || die "no stored log for effect run $1 (status $2; nixbot stores it when the run ends)"
        zstdcat -q "$f" > "$tmp"
        show "$tmp"
      }

      case "$#:''${1:-}" in
        1:runs)
          q <<'SQL'
      select r.id as run, b.number as build, r.kind, coalesce(r.schedule_name || '/', ''') || r.name as name,
             r.status, r.skip_reason, to_char(r.started_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z' as started
        from effect_runs r left join builds b on b.id = r.build_id
       where r.project_id = (select id from projects where forge = 'github' and owner = 'papersson' and name = 'apps')
         and r.kind <> 'check'
       order by r.id desc limit 30
      SQL
          ;;
        2:run)
          [[ $2 =~ ^[0-9]{1,12}$ ]] || die "run id must be digits"
          row=$(q -tA -F $'\t' -v id="$2" <<SQL
      select id, status from effect_runs where id = :'id' and project_id = $project
      SQL
          )
          [ -n "$row" ] || die "no effect run $2 for papersson/apps"
          IFS=$'\t' read -r id status <<< "$row"
          effect_log "$id" "$status"
          ;;
        1:* | 2:*)
          [[ $1 =~ ^[0-9]{1,12}$ ]] || die "build number must be digits"
          build=$(q -tA -v n="$1" <<SQL
      select id from builds where project_id = $project and number = :'n'
      SQL
          )
          [ -n "$build" ] || die "no build $1 of papersson/apps"
          if [ "$#" -eq 1 ]; then
            q -v b="$build" <<'SQL'
      \pset footer off
      \x on
      select number as build, status, branch, pr_number as pr, commit_sha as commit,
             to_char(created_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') || 'Z' as created,
             to_char(finished_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') || 'Z' as finished,
             error
        from builds where id = :'b';
      \x off
      \echo
      \echo effect runs (log <build> <kind>/<name>):
      select id as run, kind || '/' || name as name, status, skip_reason, translate(left(error, 160), E'\n', ' ') as error
        from effect_runs where build_id = :'b' order by id;
      \echo
      \echo effect eval errors:
      select source, translate(left(error, 500), E'\n', ' ') as error from effect_eval_errors where build_id = :'b';
      \echo
      \echo check attrs (log <build> <attr>; failures first):
      select regexp_replace(attr, '^checks\.x86_64-linux\.', ''') as attr, status, cached,
             translate(left(error, 160), E'\n', ' ') as error
        from build_attributes where build_id = :'b'
       order by (status = 'failed') desc, attr;
      SQL
            exit 0
          fi
          name=$2
          [[ $name =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?$ ]] || die "bad name: use <kind>/<name> or an attr"
          row=$(q -tA -F $'\t' -v b="$build" -v name="$name" <<'SQL'
      select id, status from effect_runs where build_id = :'b' and kind || '/' || name = :'name'
      SQL
          )
          if [ -n "$row" ]; then
            IFS=$'\t' read -r id status <<< "$row"
            effect_log "$id" "$status"
            exit 0
          fi
          row=$(q -tA -F $'\t' -v b="$build" -v name="$name" <<'SQL'
      select attr, status, coalesce(drv_path, ''') from build_attributes
       where build_id = :'b' and (attr = :'name' or attr = 'checks.x86_64-linux.' || :'name')
      SQL
          )
          [ -n "$row" ] || die "build $1 has no effect or attr '$name' (see: log $1)"
          IFS=$'\t' read -r attr status drv <<< "$row"
          [[ $attr =~ ^[A-Za-z0-9._+-]+$ ]] || die "unexpected attr name in database"
          if [ -f "$logs/$build/$attr.zst" ]; then
            zstdcat -q "$logs/$build/$attr.zst" > "$tmp"
          elif [[ $drv =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+\.drv$ ]]; then
            # Cached attrs were built by an earlier build or a substituter:
            # nix keeps the log of whatever built it here.
            echo "z840: nixbot stored no log for $attr (status $status); nix log $drv:"
            nix log "$drv" > "$tmp" 2>&1 || true
          else
            die "no log for $attr (status $status)"
          fi
          show "$tmp"
          ;;
        *)
          die "bad log arguments"
          ;;
      esac
    '';
  };

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
    # The caller controls the bundle on stdin and SSH_ORIGINAL_COMMAND, which
    # is split on whitespace (never evaluated) and checked word by word.
    text = ''
      usage() {
        cat >&2 <<'EOF'
      ${usage}
      EOF
        exit 2
      }

      peer=''${SSH_CONNECTION%% *}
      who=$(tailscale whois --json "$peer" 2>/dev/null \
            | jq -r '"\(.Node.Name // "?") tags=\((.Node.Tags // []) | join(","))"' 2>/dev/null) \
            || who="unknown"

      read -r -a args <<< "''${SSH_ORIGINAL_COMMAND:-}"
      [ "''${#args[@]}" -le 8 ] || usage
      for a in "''${args[@]}"; do
        [[ $a =~ ^[A-Za-z0-9._/+-]{1,200}$ ]] || usage
      done

      case "''${args[0]:-check}" in
        check)
          [ "''${#args[@]}" -le 1 ] || usage
          ;;
        log)
          logger -t agent-check "peer=$peer node=$who log ''${args[*]:1}"
          exec /run/wrappers/bin/sudo -n -u nixbot ${lib.getExe logReader} "''${args[@]:1}"
          ;;
        android)
          logger -t agent-check "peer=$peer node=$who android ''${args[*]:1}"
          exec /run/wrappers/bin/sudo -n -u android ${lib.getExe config.z840.androidCtl} "''${args[@]:1}"
          ;;
        *)
          usage
          ;;
      esac

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
      # A bundle of HEAD clones with a detached HEAD, and Nix warns when HEAD
      # is not a branch. Point HEAD at a branch on the commit under check.
      git -C "$work/repo" update-ref refs/heads/check "$rev"
      git -C "$work/repo" symbolic-ref HEAD refs/heads/check

      logger -t agent-check "peer=$peer node=$who rev=$rev size=$size"

      echo "z840: checking $rev"
      # shallow=1: cloud sessions clone with --depth 1, so the bundle has no
      # parents and Nix would fail computing revCount. The apps flake does not
      # read revCount, lastModified or self.rev, so outputs are unchanged.
      status=0
      timeout 40m nix flake check -L --keep-going "git+file://$work/repo?rev=$rev&shallow=1" || status=$?
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
  # It is called as `%u %k %t` and accepts any key, but only for agent-check,
  # and lets that key forward to the emulator's DevTools port alone:
  # for every other user it prints nothing, so no key works on port 2222.
  keysScript = ''
    #!${pkgs.bash}/bin/bash
    [ "$1" = agent-check ] || exit 0
    case "$3" in ssh-* | ecdsa-* | sk-*) ;; *) exit 0 ;; esac
    [[ "$2" =~ ^[A-Za-z0-9+/]+=*$ ]] || exit 0
    printf 'restrict,port-forwarding,permitopen="10.231.0.2:9333" %s %s\n' "$3" "$2"
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

  # The one thing agent-check may run as another user: the log reader, as
  # nixbot. The reader validates its own arguments too.
  security.sudo.extraRules = [
    {
      users = [ "agent-check" ];
      runAs = "nixbot";
      commands = [
        {
          command = lib.getExe logReader;
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

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
        AllowTcpForwarding local
        PermitOpen 10.231.0.2:9333
        PermitListen none
        AllowAgentForwarding no
        AllowStreamLocalForwarding no
        X11Forwarding no
        PermitTunnel no
    '';
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 2222 ];
}

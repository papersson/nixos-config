{ lib, pkgs, ... }:

# Binary cache: harmonia serves z840's own /nix/store, signed with a key that
# never leaves the box. Everything z840 builds (nixbot's checks of
# papersson/apps, system rebuilds) is therefore in the cache the moment it is
# built, with no upload step. Reached over the trusted tailnet only, as
# http://z840:5000 (the firewall keeps it off the LAN).
#
# Clients add it with the public key printed by `cat /var/lib/harmonia/public-key`:
#   extra-substituters = http://z840:5000
#   extra-trusted-public-keys = z840-1:<key>
let
  keyDir = "/var/lib/harmonia";
in
{
  # The signing key is generated on first boot and kept on the host, not in
  # sops: nothing but harmonia ever needs it, and a lost key just means a new
  # one (clients swap the public key). Idempotent: an existing key is kept.
  systemd.services.harmonia-keygen = {
    description = "Generate harmonia's binary-cache signing key";
    wantedBy = [ "multi-user.target" ];
    before = [ "harmonia.service" ];
    requiredBy = [ "harmonia.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    path = [ pkgs.nix ];
    script = ''
      # Readable directory, private key: UMask 0077 would make the directory 0700 too.
      mkdir -p ${keyDir}
      chmod 0755 ${keyDir}
      if [ ! -s ${keyDir}/secret-key ]; then
        nix key generate-secret --key-name z840-1 > ${keyDir}/secret-key.tmp
        mv ${keyDir}/secret-key.tmp ${keyDir}/secret-key
      fi
      nix key convert-secret-to-public < ${keyDir}/secret-key > ${keyDir}/public-key
      chmod 0644 ${keyDir}/public-key
    '';
  };

  services.harmonia = {
    enable = true;
    signKeyPaths = [ "${keyDir}/secret-key" ];
    settings = {
      bind = "[::]:5000";
      # Above cache.nixos.org's 40, so clients that list both still prefer
      # upstream for anything it has and only come here for our own builds.
      priority = 50;
    };
  };

  # Keep build inputs and outputs of rooted paths alive, so a GC doesn't throw
  # away the dependency graph nixbot reuses between runs.
  nix.settings = {
    keep-outputs = true;
    keep-derivations = true;
  };
}

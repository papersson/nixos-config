{ config, ... }:

# Declarative Wi-Fi via sops-nix + NetworkManager.ensureProfiles. The PSK
# lives encrypted in secrets/t14.yaml; sops-nix decrypts it at activation
# using the host's SSH ed25519 key as an age recipient. The decrypted env
# file is referenced via `environmentFiles` and expanded into the profile
# at activation, so the PSK never enters the Nix store.
#
# If the host SSH key is ever regenerated, re-encrypt secrets with
#   sops updatekeys secrets/t14.yaml
# or activation will fail to decrypt on next boot.

{
  sops.defaultSopsFile = ../../secrets/t14.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets."wifi/home_env" = { };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.secrets."wifi/home_env".path ];
    profiles.home = {
      connection = {
        id = "home";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "$HOME_SSID";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$HOME_PSK";
      };
      ipv4.method = "auto";
      ipv6 = {
        method = "auto";
        addr-gen-mode = "stable-privacy";
      };
    };
  };
}

{ config, inputs, pkgs, ... }:

# CI for papersson/apps: nixbot (the successor of buildbot-nix) evaluates the
# flake's `checks` with nix-eval-jobs on every push and pull request, builds
# each one in z840's store, and reports them to GitHub as check runs. What it
# builds lands in the harmonia cache (cache.nix) with no upload step, and an
# unchanged derivation is never rebuilt, so a PR only re-runs what it touches.
# The apps flake's `herculesCI.onSchedule` effects (the nightly Hegel run) run
# here too.
#
# Reachability, both through Tailscale and nothing else:
#   - The web UI is tailnet-only: https://z840.tail7bf5b7.ts.net (tailscale
#     serve, 443). Log in with GitHub; `admins` below can do everything.
#   - GitHub's webhooks need a public URL, so Tailscale Funnel publishes
#     exactly one path on port 8443: /webhooks/github. nixbot checks every
#     delivery's HMAC signature against the webhook secret.
#
# The GitHub App (papersson-nixbot) was created from a manifest; its id and
# client id are public, its private key, client secret and webhook secret are
# in secrets/z840-nixbot.yaml (sops, decrypted by the host key).
let
  domain = "z840.tail7bf5b7.ts.net";
  nixbotPkgs = inputs.nixbot.packages.${pkgs.stdenv.hostPlatform.system};
  # Written by the manifest conversion; see docs/ci.md.
  app = builtins.fromJSON (builtins.readFile ./nixbot-app.json);
  secret = name: config.sops.secrets."nixbot/${name}".path;
in
{
  imports = [ inputs.nixbot.nixosModules.nixbot ];

  sops.secrets = {
    "nixbot/github-app-key".sopsFile = ../../secrets/z840-nixbot.yaml;
    "nixbot/github-webhook-secret".sopsFile = ../../secrets/z840-nixbot.yaml;
    "nixbot/github-oauth-secret".sopsFile = ../../secrets/z840-nixbot.yaml;
    # Secrets JSON for the apps flake's effects. Binary format: the whole
    # file decrypts to one Hercules-style secrets JSON. Root-owned 0400 is
    # enough, systemd reads it for LoadCredential before dropping to nixbot.
    "nixbot/effects-apps" = {
      sopsFile = ../../secrets/z840-nixbot-effects-apps.json;
      format = "binary";
    };
  };

  services.nixbot = {
    enable = true;
    inherit domain;
    # Behind tailscale serve, which terminates TLS; nixbot listens on 8010.
    nginx.enable = false;
    useHTTPS = true;
    # GitHub delivers to the Funnel port; the UI stays on 443, tailnet only.
    webhookBaseUrl = "https://${domain}:8443/";
    admins = [ "github:papersson" ];

    # Secret "sops": the age key that decrypts the apps repo's own sops
    # files, for its effects (secretsMap.sops = "sops").
    effects.perRepoSecretFiles."github:papersson/apps" = secret "effects-apps";

    # nixbot's own nixpkgs (unstable) builds it, not our 25.11.
    packages = {
      inherit (nixbotPkgs) nixbot nix-eval-jobs;
    };

    # z840 is the only builder, so only its system is evaluated: the apps
    # flake's darwin and aarch64 checks are left to their own machines.
    buildSystems = [ "x86_64-linux" ];
    evalSystems = [ "x86_64-linux" ];
    evalWorkerCount = 8;
    evalMaxMemorySize = 4096;

    github = {
      enable = true;
      appId = app.appId;
      oauthId = app.clientId;
      appSecretKeyFile = secret "github-app-key";
      webhookSecretFile = secret "github-webhook-secret";
      oauthSecretFile = secret "github-oauth-secret";
      # Only my own repositories, whatever the app gets installed on.
      userAllowlist = [ "papersson" ];
      # Enabled on first start; later projects are toggled in the web UI.
      topic = "nixbot";
    };
  };

  # Let effects call the pkey syscalls. The nixbot module's syscall filter
  # (@system-service) leaves them out and kills the caller with SIGSYS, and
  # the effects run V8: Chrome for Bombadil and workerd for local stages.
  # pkey_alloc killed every Chrome child (Bombadil: "sending on a
  # disconnected channel") and workerd at startup (audit: sig=31
  # syscall=330). Memory protection keys only let a process protect its own
  # memory. systemd merges this entry into the module's allow list.
  systemd.services.nixbot.serviceConfig.SystemCallFilter = [ "@pkey" ];

  # Publish the UI on the tailnet and the webhook path on the internet. The
  # serve config lives in tailscaled's state; this re-applies it at every
  # boot and rebuild, so the Nix config stays the source of truth.
  systemd.services.nixbot-tailscale-serve = {
    description = "Expose nixbot over Tailscale (UI on the tailnet, webhooks via Funnel)";
    after = [ "tailscaled.service" "nixbot.socket" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ config.services.tailscale.package ];
    script = ''
      # tailscaled answers before it has logged in after a boot.
      for _ in $(seq 60); do
        tailscale status --json >/dev/null 2>&1 && break
        sleep 1
      done
      tailscale serve --bg --yes --https=443 http://127.0.0.1:${toString config.services.nixbot.port}
      tailscale funnel --bg --yes --https=8443 --set-path=/webhooks/github \
        http://127.0.0.1:${toString config.services.nixbot.port}/webhooks/github
    '';
  };
}

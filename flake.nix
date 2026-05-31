{
  description = "NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Vendor- and architecture-specific defaults (microcode, fan/thermal,
    # SSD, mesa baseline). No T14 Gen 4 Intel profile exists upstream as
    # of 2026-05; we compose from the generic `common-*` modules instead.
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning. Consumed standalone via
    # `diskoConfigurations.z840` (boot SSD only); deliberately NOT imported into
    # the running z840 config, so `disko --mode destroy,format` can never be
    # pointed at the tank pool. See hosts/z840/disko.nix and docs/runbooks/.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot with our own keys. Step 1 only adds the input so `sbctl`
    # can land via systemPackages; the module is imported in step 5, after
    # keys are created and enrolled in firmware.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Neovim. Replaces the previous LazyVim-from-Lua deployment
    # under home/patrikpersson/nvim/; plugins and LSPs come from nixpkgs so
    # there's no Mason and no /lib64/ld-linux runtime issue.
    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zen browser (Firefox fork) — not packaged in nixpkgs. The flake
    # ships the binary plus a home-manager module (`programs.zen-browser`).
    # Upstream advises following nixpkgs-unstable so the bundled build
    # tracks a recent-enough Firefox; we point it at our unstable input.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs-unstable";
        home-manager.follows = "home-manager";
      };
    };

    # worklog — query Claude Code transcripts as a work history. Consumed
    # natively (home.packages + the agent file), not via the plugin system;
    # follows our nixpkgs so duckdb comes from the same 25.11 set.
    worklog = {
      url = "github:papersson/worklog";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude Code CLI, tracking Anthropic's official native binary releases.
    # nixpkgs-unstable lags upstream by ~days because each version is a PR;
    # this flake's CI checks hourly and ships pre-built binaries direct
    # from Anthropic's distribution servers. Applied via overlay below so
    # `pkgs.claude-code` is the bleeding-edge build everywhere.
    nix-claude-code = {
      url = "github:ryoppippi/nix-claude-code";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, sops-nix, lanzaboote, nixvim, zen-browser, nix-claude-code, ... }@inputs: {
    nixosConfigurations.t14 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/t14
        nixos-hardware.nixosModules.common-pc-laptop
        nixos-hardware.nixosModules.common-pc-ssd
        nixos-hardware.nixosModules.common-cpu-intel
        nixos-hardware.nixosModules.common-gpu-intel
        sops-nix.nixosModules.sops
        lanzaboote.nixosModules.lanzaboote
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-bak";
          # Thread flake inputs into home modules (claude.nix consumes
          # inputs.worklog). NixOS specialArgs don't reach HM modules.
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.sharedModules = [
            sops-nix.homeManagerModules.sops
            nixvim.homeModules.nixvim
            # Defines `programs.zen-browser`. `beta` is the flake's
            # default channel — updates only on a flake.lock bump.
            zen-browser.homeModules.beta
          ];
          home-manager.users.patrikpersson = import ./home/patrikpersson;
        }
        {
          # Pull fast-moving packages from unstable without changing the
          # system channel. `nix flake update nixpkgs-unstable` bumps just
          # this input.
          nixpkgs.overlays = [
            # Bleeding-edge Claude Code from official Anthropic binaries —
            # overrides `pkgs.claude-code` to the latest release tracked
            # by ryoppippi/nix-claude-code (hourly auto-bump). Keeps the
            # tool current without per-version flake editing.
            nix-claude-code.overlays.default
            (final: _prev: {
              unstable = import nixpkgs-unstable {
                inherit (final.stdenv.hostPlatform) system;
                config.allowUnfree = true;
              };
            })
          ];
        }
      ];
    };

    nixosConfigurations.z840 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/z840
        nixos-hardware.nixosModules.common-pc
        nixos-hardware.nixosModules.common-pc-ssd
        nixos-hardware.nixosModules.common-cpu-intel
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-bak";
          # Thread flake inputs into home modules (claude.nix consumes
          # inputs.worklog). NixOS specialArgs don't reach HM modules.
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.sharedModules = [
            sops-nix.homeManagerModules.sops
            nixvim.homeModules.nixvim
          ];
          home-manager.users.patrikpersson = import ./home/patrikpersson/server.nix;
        }
        {
          nixpkgs.overlays = [
            # Bleeding-edge Claude Code from official Anthropic binaries —
            # overrides `pkgs.claude-code` to the latest release tracked
            # by ryoppippi/nix-claude-code (hourly auto-bump). Keeps the
            # tool current without per-version flake editing.
            nix-claude-code.overlays.default
            (final: _prev: {
              unstable = import nixpkgs-unstable {
                inherit (final.stdenv.hostPlatform) system;
                config.allowUnfree = true;
              };
            })
          ];
        }
      ];
    };

    # Standalone boot-SSD layout for fresh installs / nixos-anywhere. Not wired
    # into nixosConfigurations.z840 (the running box already boots off its
    # by-uuid config); run via `nix run github:nix-community/disko -- --flake
    # .#z840 --mode ...` against a target disk.
    diskoConfigurations.z840 = import ./hosts/z840/disko.nix;
  };
}

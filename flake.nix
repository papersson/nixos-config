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

    # Secure Boot with our own keys. Step 1 only adds the input so `sbctl`
    # can land via systemPackages; the module is imported in step 5, after
    # keys are created and enrolled in firmware.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, sops-nix, lanzaboote, ... }@inputs: {
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
          home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];
          home-manager.users.patrikpersson = import ./home/patrikpersson;
        }
        {
          # Pull fast-moving packages from unstable without changing the
          # system channel. `nix flake update nixpkgs-unstable` bumps just
          # this input.
          nixpkgs.overlays = [
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
  };
}

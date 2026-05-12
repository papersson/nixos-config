{
  description = "NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Vendor- and architecture-specific defaults (microcode, fan/thermal,
    # SSD, mesa baseline). No T14 Gen 4 Intel profile exists upstream as
    # of 2026-05; we compose from the generic `common-*` modules instead.
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }@inputs: {
    nixosConfigurations.t14 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/t14
        nixos-hardware.nixosModules.common-pc-laptop
        nixos-hardware.nixosModules.common-pc-ssd
        nixos-hardware.nixosModules.common-cpu-intel
        nixos-hardware.nixosModules.common-gpu-intel
      ];
    };
  };
}

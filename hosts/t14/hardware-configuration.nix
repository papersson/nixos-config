# Placeholder.
#
# Inside the NixOS installer, after partitioning and mounting at /mnt, run:
#
#     nixos-generate-config --root /mnt
#
# Copy the generated /mnt/etc/nixos/hardware-configuration.nix over this
# file (or move it into place from inside the cloned flake). Do NOT
# commit a hardware-configuration.nix from another machine — it embeds
# UUIDs, partition layout, and kernel modules specific to the host.
#
# The empty attrset below will deliberately fail to evaluate as a NixOS
# system (no `fileSystems."/"`, no boot.initrd, etc.), forcing the real
# file to be generated before a build can succeed.
{ }

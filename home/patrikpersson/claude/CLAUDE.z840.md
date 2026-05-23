# CLAUDE.md

## Environment

- HP Z840 workstation, NixOS 25.11, kernel `pkgs.linuxPackages_latest`. Headless — no desktop session, accessed via SSH.
- User: `patrikpersson`. Shell: `zsh`. Prompt: starship. Jumps: zoxide.
- System config: flake at `~/nixos-config` (clone of `papersson/nixos-config`). User-writable for edits; rebuilds need sudo.
- Networking: static IP `192.168.1.10/24` on `eno1`, hostname `z840`, hostId `8f3a1c2b`. Reachable from the t14 as `ssh server`.

## Homelab

Personal homelab built around this single strong server, replacing common SaaS dependencies with self-hosted equivalents and building infrastructure skills along the way. Goal arc: media (Jellyfin) → files/backup → an "enterprise" identity stack (Kerberos + LDAP + SSSD) built from upstream components, not appliances.

### Principles

- **Declarative everything.** All configuration lives in the flake. If something can't be expressed in Nix, wrap it in a NixOS module that does.
- **One strong node over a cluster.** Complexity comes from services, not orchestration. A single Z840 with proper ZFS replaces a 3-node Proxmox cluster for the foreseeable future.
- **Build from components, not appliances.** When learning a technology (Kerberos, LDAP, DNS, CA), use the upstream daemons (MIT KDC, OpenLDAP, BIND, step-ca). Avoid all-in-one bundles that hide the protocol layer.
- **FOSS-first, no Microsoft.** AD-free identity stack. Linux clients via SSSD.
- **Real consequences.** Services replace things actually used daily (media, files, VPN). Forces fixing issues rather than abandoning the lab.

### Hardware (host)

- **CPU/RAM**: 2× Xeon E5-2650 v3 (20c / 40t), 256 GB DDR4 ECC
- **GPU**: Quadro M5000 8 GB (for transcode / passthrough later)
- **PSU**: 1125 W
- **Boot disk**: 512 GB Kingston NVMe on motherboard M.2
- **Bulk storage**: 4× WD HC550 16 TB SATA (enterprise CMR) — raidz1 planned → ~48 TB usable as pool `tank`
- **Fast tier (planned)**: 2× Kingston Fury Renegade 2 TB NVMe on PCIe adapters → mirror, pool `fast`
- **HBA**: built-in LSI SAS2308-IR in pass-through (drives appear as raw `sdb`–`sde`)
- **NIC**: 2× 1 GbE on-board; Mellanox ConnectX-3 dual SFP+ planned for 10G

### Other hardware (not yet deployed)

- MikroTik CRS326-24G-2S+RM — managed switch, VLAN trunking
- Protectli VP2430 (Intel N150, 8 GB, 500 GB NVMe, coreboot) — future OPNsense firewall
- CyberPower 1600VA UPS — clean shutdown via NUT

### Architecture

- **Virtualization**: libvirt + KVM as the default for full VMs (lab Rocky/Debian guests for the identity stack). NixOS containers (`containers.*`) for lightweight Nix-managed services. Docker via `virtualisation.oci-containers` reserved as an escape hatch for upstream containers without good Nix equivalents.
- **Storage**: two ZFS pools planned. `tank` (raidz1 on 4× HC550, `recordsize=1M` for media). `fast` (mirror on 2× NVMe, default recordsize for VM disks / databases).
- **Network (future)**: Telia ISP gateway → Protectli (OPNsense) → MikroTik trunk → 5 VLANs (mgmt, servers, lab, IoT, guest). WireGuard for remote access.
- **Identity (future)**: standalone MIT Kerberos KDC + OpenLDAP/389-ds + BIND + step-ca, with SSSD on Linux clients. Lab VMs join the realm; bare-metal hosts stay independent.

### Current state

- Flake-managed via `hosts/z840` in `~/nixos-config`. Bootloader: systemd-boot (no Lanzaboote).
- OpenSSH: key auth only, password auth and root login disabled.
- ZFS support enabled in the kernel; no pools created yet.
- No services running beyond SSH.

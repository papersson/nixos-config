# CLAUDE.md

## Environment

- HP Z840 workstation, NixOS 25.11, kernel `pkgs.linuxPackages_latest`. Headless — no desktop session, accessed via SSH.
- User: `patrikpersson`. Shell: `zsh`. Prompt: starship. Jumps: zoxide.
- System config: flake at `~/nixos-config` (clone of `papersson/nixos-config`). User-writable for edits. Claude has full passwordless sudo on z840 and rebuilds it itself: `sudo -n nixos-rebuild switch --flake ~/nixos-config#z840`. Which irreversible operations still need the user's go-ahead: the repo's CLAUDE.md.
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
- **Bulk storage**: 4× WD HC550 16 TB SATA (enterprise CMR) — raidz2 planned → ~28 TB usable as pool `tank`
- **Fast tier (planned)**: 2× Kingston Fury Renegade 2 TB NVMe on PCIe adapters → mirror, pool `fast`
- **HBA**: built-in LSI SAS2308-IR in pass-through (drives appear as raw `sda`–`sdd`; boot NVMe is on the motherboard M.2, not on the HBA)
- **NIC**: 2× 1 GbE on-board; Mellanox ConnectX-3 dual SFP+ planned for 10G

### Other hardware (not yet deployed)

- MikroTik CRS326-24G-2S+RM — managed switch, VLAN trunking
- Protectli VP2430 (Intel N150, 8 GB, 500 GB NVMe, coreboot) — future OPNsense firewall
- CyberPower 1600VA UPS — clean shutdown via NUT

### Architecture

- **Virtualization**: libvirt + KVM as the default for full VMs (lab Rocky/Debian guests for the identity stack). NixOS containers (`containers.*`) for lightweight Nix-managed services. Docker via `virtualisation.oci-containers` reserved as an escape hatch for upstream containers without good Nix equivalents.
- **Storage**: two ZFS pools planned. `tank` (raidz2 on 4× HC550, general-purpose; `recordsize=1M` only on the `tank/media` dataset, other datasets keep the 128 KiB pool default). `fast` (mirror on 2× NVMe, default recordsize for VM disks / databases). `tank` is the bulk pool — media is the first tenant, not the only one; see `docs/storage.md` for dataset-creation conventions.
- **Network (future)**: Telia ISP gateway → Protectli (OPNsense) → MikroTik trunk → 5 VLANs (mgmt, servers, lab, IoT, guest). WireGuard for remote access.
- **Identity (future)**: standalone MIT Kerberos KDC + OpenLDAP/389-ds + BIND + step-ca, with SSSD on Linux clients. Lab VMs join the realm; bare-metal hosts stay independent.

### Current state

- Flake-managed via `hosts/z840` in `~/nixos-config`. Bootloader: systemd-boot (no Lanzaboote).
- OpenSSH: key auth only, password auth and root login disabled.
- ZFS support enabled in the kernel; no pools created yet.
- No services running beyond SSH.

## Other models: Codex and Gemini

Two other agent CLIs are installed (Nix-managed) and logged in. Use them for a second opinion from a different model family, an independent review, or delegating a long autonomous job.

- **Codex (OpenAI)**: `codex exec`. No default model is configured; pass `-m gpt-6-astra` (list with `codex debug models`; run `codex-bump` for newer ones).
  - One-shot: `echo "<prompt>" | codex exec --skip-git-repo-check --ephemeral -s read-only -c 'notify=[]' -m gpt-6-astra -o out.md -`
  - Agentic: `-s workspace-write -C <repo> [--add-dir <dir>]`. Don't use `--dangerously-bypass-approvals-and-sandbox`; Claude's classifier blocks it. `--json` emits events, and the first line has `thread_id` for `codex exec resume <id>`, which takes the sandbox as `-c sandbox_mode=...`, not `-s`.
  - Images: `-i a.png -i b.png`, with the prompt on stdin (`-i` swallows positionals).
- **Gemini (Google Antigravity)**: `agy -p "<prompt>" --model gemini-4-neon-high --print-timeout 0`. List models with `agy models`. `--output-format json` gives structured output, `--mode auto` lets it edit files, and `--disable-slash-commands` suits scripted calls. It can read image, audio and video files with its own tools.
- Long runs (more than a few minutes): launch in a Rex window (`rex -S z840 new …`) and poll, rather than blocking a Bash call.
- Both bill against subscriptions with usage windows; cache results when calling in a loop. Login is interactive only (`codex login --device-auth`; `agy` with no arguments). If auth fails, hand off to the user.

## Agent history: atuin

atuin holds shell history and every Claude Code and Codex thread on this machine, back to the first transcripts (agy threads aren't captured). The `atuin-daemon` user service captures new threads as they happen. They sync with the Mac's through the atuin server on this box (`services.atuin`, port 8888, tailnet only), so the Mac's threads are searchable here too (each has a `host`).

- To find earlier work by any agent, use the atuin MCP tools (`atuin_threads_search`, then `atuin_threads_read`) or `atuin threads search <words> [--harness codex] --style json` instead of grepping `~/.claude/projects`. Each result's `session.atuin_id` is the thread id; its last 8 characters are enough. `atuin threads show <id>` prints a whole thread.
- To hand a thread to another agent: `atuin resume <id> --in <agent> --print`, with `<agent>` `claude-code` or `codex`. It writes the thread out as a new session of that agent and prints the command that resumes it. `--fork` instead makes a new session of the thread's own agent with the same history.
- The `worklog` skill turns this history into reports, runbooks and CLAUDE.md rules.

## Nightly tool bumps

The `nightly-bump` user timer (04:30) updates Claude Code, the papershop skills, Codex and atuin, rebuilds once and commits to `~/nixos-config` (never pushes). Rex is bumped by hand, because its update ends every session. If a tool misbehaves overnight, `journalctl --user -u nightly-bump` and `git -C ~/nixos-config log` show what changed. Tailscale SSH sessions and Rex panes don't set `XDG_RUNTIME_DIR`, so prefix `systemctl --user` and `journalctl --user` with `XDG_RUNTIME_DIR=/run/user/1000`.

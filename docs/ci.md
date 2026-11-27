# CI and binary cache on z840

z840 is the build farm for papersson/apps: it replaces GitHub Actions' `nix flake check` and the nightly fuzzing job.

## Pieces

- **nixbot** (`hosts/z840/ci.nix`), the successor of buildbot-nix (archived 2026-10). One service: GitHub App webhooks in, nix-eval-jobs over the flake's `checks`, builds in z840's store, check runs back to GitHub. The apps flake's `herculesCI` output adds the nightly Hegel run as an `onSchedule` effect, which opens an issue with the replay string when a property fails.
- **harmonia** (`hosts/z840/cache.nix`) serves z840's store as a signed binary cache at `http://z840:5000`, tailnet only. The key is generated on the host (`/var/lib/harmonia/secret-key`); the public key is in `/var/lib/harmonia/public-key`.

## Reaching it

- UI: <https://z840.tail7bf5b7.ts.net> (tailnet only, GitHub login, `github:papersson` is admin).
- Webhooks: Tailscale Funnel publishes only `https://z840.tail7bf5b7.ts.net:8443/webhooks/github`; nixbot verifies each delivery's signature.
- Cache, on a client (the Mac, nix.conf or nix-darwin's `nix.settings`):

  ```
  extra-substituters = http://z840:5000
  extra-trusted-public-keys = <contents of /var/lib/harmonia/public-key>
  ```

## The GitHub App

`papersson-nixbot`, created from a manifest so that no secret is ever copied by hand. To recreate it: post the manifest in `scripts/nixbot-app-manifest.json` to `https://github.com/settings/apps/new` (a form field `manifest`), press Create, and run `scripts/nixbot-app-from-manifest.sh <code>` with the `code` from the redirect URL. It writes `hosts/z840/nixbot-app.json` (public ids) and `secrets/z840-nixbot.yaml` (sops). Then install the app on the repositories to build and give each the `nixbot` topic (or enable it in the UI).

## Adding a repository

Install the app on it, enable the project in the UI, and add `nixbot.toml` if it needs anything but `checks`.

## Effect secrets

`secrets/z840-nixbot-effects-apps.json` is papersson/apps' effects secrets file (`services.nixbot.effects.perRepoSecretFiles`), a binary sops file that decrypts to Hercules-style JSON: one secret `sops` whose `data.key` is an age private key, with `condition = true`. The apps repo's `.sops.yaml` lists that key's public half as a recipient, so an effect with `secretsMap.sops = "sops"` can decrypt the apps repo's secrets. To rotate it, generate a new key straight into the file (`age-keygen | grep AGE-SECRET-KEY | jq -cR '{sops:{data:{key:.},condition:true}}' | sops encrypt --filename-override secrets/z840-nixbot-effects-apps.json --input-type binary --output-type json /dev/stdin`), so the private key never touches disk in plaintext, then swap the public key in the apps repo and re-encrypt its secrets.

## Reading CI results without the UI

The agent-check endpoint (`hosts/z840/agent-check.nix`, port 2222, tailnet only) also serves nixbot's results for papersson/apps, so a cloud session can read why CI failed:

```
ssh -p 2222 agent-check@z840 'log 116'                       # build summary: status, effect runs, check attrs
ssh -p 2222 agent-check@z840 'log 116 pull_request/preview'  # an effect run's log (<kind>/<name>, as the summary lists it)
ssh -p 2222 agent-check@z840 'log 116 lint'                  # a check attr's build log (short or full attr name)
ssh -p 2222 agent-check@z840 'log runs'                      # the 30 latest effect runs, scheduled ones included
ssh -p 2222 agent-check@z840 'log run 218'                   # one run's log by id (how to read a nightly run)
```

Logs print their last 2000 lines; add `--all` for the whole log. No command, or `check`, is the bundle check as before; anything else prints the usage and exits 2. Each call is logged to the journal (`journalctl -t agent-check`) with the peer's tailnet node.

It is read-only: agent-check may run exactly one program as `nixbot` through sudo, `nixbot-agent-log`, which queries the `nixbot` database in read-only transactions and reads the stored logs under `/var/lib/nixbot/logs` (`<build id>/<attr>.zst`, `effects/<run id>.zst`). Paths come from ids the database returns, never from the caller. A check attr nixbot did not build itself (cached) falls back to `nix log` of its derivation. Effect logs are stored after nixbot redacts secrets, so a running effect has no log yet.

## The Android emulator

`hosts/z840/android.nix` runs a headless Android Emulator on KVM for agents: Android 16 (API 36, the Google APIs image, so Chrome for Android and Gboard), a Pixel 9's screen (1080 x 2424 at 420 dpi), as the `android` user, always on at `CPUWeight=20`, `IOWeight=20` and `MemoryMax=8G` so CI comes first. `android-adb` is the adb server on 127.0.0.1:5037; `android-emulator` boots the AVD in `/var/lib/android` from cold each start (a new system image wipes its data), and its `ExecStartPost` (`android-ctl setup`) keeps the screen awake, skips Chrome's first-run screens and forwards 127.0.0.1:9333 to Chrome's `chrome_devtools_remote` socket.

Agents reach it through agent-check (port 2222), so the tailnet policy stays as it is:

```
ssh -p 2222 agent-check@z840 'android up'                       # wait for boot, start Chrome, status
ssh -p 2222 agent-check@z840 'android screenshot' > phone.png   # the whole screen, keyboard included
ssh -p 2222 -N -L 9222:127.0.0.1:9333 agent-check@z840          # Chrome's DevTools, for agent-browser --cdp
```

`android` runs `android-ctl` as `android` through one sudo rule (verbs: `status`, `up`, `screenshot`, `ui`, `tap`, `swipe`, `key`, `text` and `open` with their input on stdin, `rotate`, `reset`, `restart`); each call is journaled under `agent-check` with the peer's node. The forward to 9333 is the only one port 2222 allows (`permitopen` on every key, and `PermitOpen` in its Match block). papersson/apps wraps all of it as `scripts/z840.sh android`.

The firewall (`android-out`, on OUTPUT for the `android` uid) refuses the phone z840's own loopback (Radarr and friends trust localhost) except adb and the emulator's ports, the LAN, link-local, multicast and the tailnet, except the addresses in the `android-agents` ipset: `android-agent-peers` adds every `tag:agent` peer every 20 s with a 2-minute timeout, so a phone can open a cloud session's local stage at its tailnet address. On the host: `android-ctl status` (as any user with sudo: `sudo -u android android-ctl status`), `journalctl -u android-emulator`.

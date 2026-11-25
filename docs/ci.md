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

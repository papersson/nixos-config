#!/usr/bin/env bash
# Turn a GitHub App manifest code into nixbot's configuration, without any
# secret ever being printed or written in plaintext outside /dev/shm.
#
#   nix shell nixpkgs#sops nixpkgs#jq nixpkgs#curl -c scripts/nixbot-app-from-manifest.sh CODE
#
# CODE is the `?code=` GitHub appends to the manifest's redirect URL after
# "Create GitHub App" (single use, valid for an hour). Writes:
#   hosts/z840/nixbot-app.json   public: app id, client id, slug
#   secrets/z840-nixbot.yaml     sops: private key, client secret, webhook secret
set -euo pipefail

code=${1:?usage: $0 MANIFEST_CODE}
cd "$(dirname "$0")/.."

tmp=$(mktemp -d /dev/shm/nixbot-app.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
chmod 0700 "$tmp"

curl -fsS -X POST \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app-manifests/${code}/conversions" \
  -o "$tmp/app.json"

jq '{appId: .id, clientId: .client_id, slug: .slug}' "$tmp/app.json" > hosts/z840/nixbot-app.json

# JSON is YAML, so sops can take it as is; the nesting gives sops-nix the
# keys nixbot/github-app-key and so on.
jq '{nixbot: {
      "github-app-key": .pem,
      "github-webhook-secret": .webhook_secret,
      "github-oauth-secret": .client_secret
    }}' "$tmp/app.json" > "$tmp/secrets.json"

sops encrypt \
  --filename-override secrets/z840-nixbot.yaml \
  --input-type json --output-type yaml \
  "$tmp/secrets.json" > secrets/z840-nixbot.yaml

echo "App $(jq -r .slug hosts/z840/nixbot-app.json) (id $(jq -r .appId hosts/z840/nixbot-app.json)) written."
echo "Install it on the repositories to build: https://github.com/apps/$(jq -r .slug hosts/z840/nixbot-app.json)/installations/new"

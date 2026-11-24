# Nightly bump of the fast-moving agent tools on z840: Claude Code and the
# papershop skills (flake inputs), Codex and Atuin (release binaries in
# pkgs/). One rebuild for all of them and one commit, made only if the switch
# succeeds; on failure the edits are reverted and the unit fails, so the
# journal (`journalctl --user -u nightly-bump`) says why.
#
# Rex is left out on purpose: updating it restarts the Rex server, which ends
# every z840 session. Bump it by hand with `nix flake update rex`.
#
# Skips the night when the repo has uncommitted changes, so it never commits
# someone's work in progress. Commits locally; pushing stays manual.

repo="$HOME/nixos-config"
cd "$repo"

if [ -n "$(git status --porcelain)" ]; then
  echo "nightly-bump: $repo has uncommitted changes; skipping tonight"
  exit 0
fi

summary=()

lock_rev() {
  jq -r --arg n "$1" '.nodes[$n].locked.rev // .nodes[$n].locked.narHash' flake.lock | cut -c1-12
}

for input in nix-claude-code papershop; do
  before=$(lock_rev "$input")
  nix flake update "$input"
  after=$(lock_rev "$input")
  if [ "$before" != "$after" ]; then
    summary+=("$input $before -> $after")
  fi
done

# Usage: bump_release NAME FILE GITHUB_REPO TAG_PREFIX ASSET_SUFFIX
bump_release() {
  local name=$1 file=$2 gh=$3 prefix=$4 asset=$5 tag ver hash
  tag=$(curl -fsSL "https://api.github.com/repos/$gh/releases/latest" | jq -r .tag_name)
  ver=${tag#"$prefix"}
  if grep -q "version = \"$ver\"" "$file"; then
    return 0
  fi
  hash=$(nix store prefetch-file --json \
    "https://github.com/$gh/releases/download/$tag/$asset" | jq -r .hash)
  sed -i -e "s|version = \".*\";|version = \"$ver\";|" \
         -e "s|hash = \"sha256-.*\";|hash = \"$hash\";|" "$file"
  summary+=("$name $ver")
}

bump_release codex pkgs/codex.nix openai/codex rust-v codex-package-x86_64-unknown-linux-musl.tar.zst
bump_release atuin pkgs/atuin.nix atuinsh/atuin v atuin-x86_64-unknown-linux-musl.tar.gz

# The sync server takes the client's version (pkgs/atuin-server.nix), so
# only its hash needs to follow.
if ! git diff --quiet -- pkgs/atuin.nix; then
  ver=$(sed -n 's/^  version = "\(.*\)";/\1/p' pkgs/atuin.nix)
  hash=$(nix store prefetch-file --json \
    "https://github.com/atuinsh/atuin/releases/download/v$ver/atuin-server-x86_64-unknown-linux-musl.tar.gz" \
    | jq -r .hash)
  sed -i "s|hash = \"sha256-.*\";|hash = \"$hash\";|" pkgs/atuin-server.nix
fi

files=(flake.lock pkgs/codex.nix pkgs/atuin.nix pkgs/atuin-server.nix)

if git diff --quiet -- "${files[@]}"; then
  echo "nightly-bump: everything is current"
  exit 0
fi

if ! sudo -n /run/current-system/sw/bin/nixos-rebuild switch --flake "$repo#z840"; then
  echo "nightly-bump: rebuild failed; reverting ${summary[*]}"
  git checkout -- "${files[@]}"
  exit 1
fi

{
  echo "z840: nightly bump"
  echo
  printf -- '- %s\n' "${summary[@]}"
} | git commit -q -F - -- "${files[@]}"
echo "nightly-bump: switched and committed: ${summary[*]}"

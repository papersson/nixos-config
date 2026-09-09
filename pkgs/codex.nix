# OpenAI Codex CLI from the official prebuilt release bundle.
#
# nixpkgs builds codex from source and lags upstream by weeks; Codex ships
# several releases a week and new models only work on recent builds. This
# fetches the `codex-package` bundle OpenAI attaches to each GitHub
# release — the same approach nix-claude-code takes for Claude Code.
#
# The bundle is installed as-is because codex resolves its helpers by
# layout, not PATH: `codex-package.json` next to `bin/` points it at
# sibling binaries (`bin/codex-code-mode-host`, needed for Code Mode),
# `codex-path/` (rg) and `codex-resources/` (bwrap, zsh). Installing only
# the bare `codex` binary made Code Mode "fail closed" for want of the
# host executable. Everything is static musl, so no patchelf.
#
# Bump with the `codex-bump` shell function (edits version + hash below,
# rebuilds, commits). Manually: change `version`, then run
#   nix store prefetch-file --json <url> | jq -r .hash
# and paste the result into `hash`.
{
  lib,
  stdenvNoCC,
  fetchurl,
  zstd,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.153.4";

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-package-x86_64-unknown-linux-musl.tar.zst";
    hash = "sha256-K1wA31dY0BTHmRD9/+1D8ppsrnPzfpLV7CFlQ8pT554=";
  };

  # The tarball's entries sit at the top level (bin/, codex-path/, ...).
  sourceRoot = ".";

  nativeBuildInputs = [ zstd ];

  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r bin codex-path codex-resources codex-package.json $out/
    runHook postInstall
  '';

  meta = {
    description = "Lightweight coding agent that runs in your terminal (official binary)";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})

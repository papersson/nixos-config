# OpenAI Codex CLI from the official prebuilt release binary.
#
# nixpkgs builds codex from source and lags upstream by weeks; Codex ships
# several releases a week and new models only work on recent builds. This
# fetches the static musl binary OpenAI attaches to each GitHub release —
# the same approach nix-claude-code takes for Claude Code. No patchelf:
# the binary is static-pie.
#
# Bump with the `codex-bump` shell function (edits version + hash below,
# rebuilds, commits). Manually: change `version`, then run
#   nix store prefetch-file --json <url> | jq -r .hash
# and paste the result into `hash`.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  ripgrep,
  bubblewrap,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.153.4";

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-9HlCTsoJJITcQNh64oxE9MxAI0pgBF1hMeSTgA2BSjA=";
  };

  # The tarball holds a single file, no top-level directory.
  sourceRoot = ".";

  nativeBuildInputs = [ makeWrapper ];

  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 codex-x86_64-unknown-linux-musl $out/bin/codex
    # Same runtime deps nixpkgs wraps in: rg for search, bwrap for the
    # Linux sandbox.
    wrapProgram $out/bin/codex \
      --prefix PATH : ${lib.makeBinPath [ ripgrep bubblewrap ]}
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

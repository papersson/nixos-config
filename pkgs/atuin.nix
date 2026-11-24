# Atuin from the official prebuilt release binary.
#
# Thread capture, `atuin resume` and the MCP server need 18.25+; nixpkgs
# 25.11 ships 18.10 and unstable trails by weeks, while atuin releases
# every few days. The musl build is a single static binary, so no patchelf.
#
# Bump with the `atuin-bump` shell function (edits version + hash below,
# rebuilds, commits). Manually: change `version`, then run
#   nix store prefetch-file --json <url> | jq -r .hash
# and paste the result into `hash`.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "atuin";
  version = "18.25.1";

  src = fetchurl {
    url = "https://github.com/atuinsh/atuin/releases/download/v${finalAttrs.version}/atuin-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-8ryXWI1aqR9JuZIphUThN3bfBEy0uvYGh1x8yEROngA=";
  };

  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 atuin $out/bin/atuin
    runHook postInstall
  '';

  meta = {
    description = "Magical shell history (official binary)";
    homepage = "https://github.com/atuinsh/atuin";
    license = lib.licenses.mit;
    mainProgram = "atuin";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})

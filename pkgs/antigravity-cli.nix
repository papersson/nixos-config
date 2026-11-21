# Google Antigravity CLI (`agy`) from Google's official release tarball.
#
# Not in nixpkgs. Upstream ships one dynamically linked x86_64 binary
# (`antigravity`) that needs only glibc, so autoPatchelfHook is enough.
# The wrapper mirrors Homebrew's cask: the binary is exposed as `agy` with
# AGY_CLI_DISABLE_AUTO_UPDATE set, since it would otherwise try to replace
# itself inside the read-only store.
#
# Bump: take the new version pair and x86_64_linux sha256 from the Homebrew
# cask (Casks/a/antigravity-cli.rb), or from
#   https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json
# then convert the hex sha256 to SRI:
#   nix hash convert --hash-algo sha256 --to sri <hex>
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "antigravity-cli";
  version = "1.5.14";
  build = "5302690847260672";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${finalAttrs.version}-${finalAttrs.build}/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha256-1YOGMi0gc+lrM/fMMrTpri22Io9YRANpcllnst5Ix7U=";
  };

  # The tarball holds the single `antigravity` binary at its top level.
  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 antigravity $out/libexec/antigravity
    makeWrapper $out/libexec/antigravity $out/bin/agy \
      --set AGY_CLI_DISABLE_AUTO_UPDATE true
    runHook postInstall
  '';

  meta = {
    description = "Terminal interface for Google Antigravity agents (official binary)";
    homepage = "https://antigravity.google/product/antigravity-cli";
    license = lib.licenses.unfree;
    mainProgram = "agy";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})

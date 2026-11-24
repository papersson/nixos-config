# Atuin's sync server from the official prebuilt release binary.
#
# The release `atuin` client is built without the server, so it ships as its
# own static musl binary. It follows pkgs/atuin.nix's version, so client and
# server always match; only `hash` is bumped here (by `atuin-bump` and the
# nightly-bump timer, together with the client).
{
  lib,
  stdenvNoCC,
  fetchurl,
  atuin,
}:

stdenvNoCC.mkDerivation {
  pname = "atuin-server";
  inherit (atuin) version;

  src = fetchurl {
    url = "https://github.com/atuinsh/atuin/releases/download/v${atuin.version}/atuin-server-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-Ggud+xlHhTtn0CYTXXjmVUsnVRgJ5wFRJQKWb/XpT44=";
  };

  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 atuin-server $out/bin/atuin-server
    runHook postInstall
  '';

  meta = {
    description = "Atuin sync server (official binary)";
    homepage = "https://github.com/atuinsh/atuin";
    license = lib.licenses.mit;
    mainProgram = "atuin-server";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

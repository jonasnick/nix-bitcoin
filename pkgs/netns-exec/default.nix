{ stdenv, pkgs }:

stdenv.mkDerivation {
  name = "netns-exec";
  buildInputs = [ pkgs.libcap ];
  src = ./src;
  installPhase = ''
    mkdir -p $out
    cp main $out/netns-exec
  '';
}

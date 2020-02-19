let
  # TODO:
  # nix-bitcoin-path = builtins.fetchTarball {
  #   url = "https://github.com/fort-nix/nix-bitcoin/archive/master.tar.gz";
  #   sha256 = "1mlvfakjgbl67k4k9mgafp5gvi2gb2p57xwxwffqr4chx8g848n7";
  # };
  nix-bitcoin-path = ../.;
  nixpkgs-path = (import "${toString nix-bitcoin-path}/pkgs/nixpkgs-pinned.nix").nixpkgs;
  nixpkgs = import nixpkgs-path {};
  nix-bitcoin = nixpkgs.callPackage nix-bitcoin-path {};
in
with nixpkgs;

stdenv.mkDerivation rec {
  name = "nix-bitcoin-environment";

  buildInputs = [ nix-bitcoin.nixops19_09 figlet ];

  shellHook = ''
    export NIX_PATH="nixpkgs=${nixpkgs-path}:nix-bitcoin=${toString nix-bitcoin-path}:."
    # ssh-agent and nixops don't play well together (see
    # https://github.com/NixOS/nixops/issues/256). I'm getting `Received disconnect
    # from 10.1.1.200 port 22:2: Too many authentication failures` if I have a few
    # keys already added to my ssh-agent.
    export SSH_AUTH_SOCK=""
    figlet "nix-bitcoin"
    (mkdir -p secrets; cd secrets; ${nix-bitcoin.generate-secrets})
  '';
}

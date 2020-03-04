let
  nixpkgsPinned = import ./nixpkgs-pinned.nix;
  unstable = import nixpkgsPinned.nixpkgs-unstable { config = {}; overlays = []; };
in
{
  bitcoin = unstable.bitcoin.override { miniupnpc = null; };
  bitcoind = unstable.bitcoind.override { miniupnpc = null; };
  inherit (unstable)
    clightning
    lnd;
}

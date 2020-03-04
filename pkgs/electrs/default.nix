{ lib, rustPlatform, clang, llvmPackages, fetchFromGitHub, pkgs }:
rustPlatform.buildRustPackage rec {
  pname = "electrs";
  version = "0.8.3";

  src = fetchFromGitHub {
    owner = "romanz";
    repo = "electrs";
    rev = "v${version}";
    sha256 = "01993iv3kkf56s5x33gvk433zjwvqlfxa5vqrjl4ghr4i303ysc2";
  };

  # Needed for librocksdb-sys
  buildInputs = [ clang ];
  LIBCLANG_PATH = "${llvmPackages.libclang}/lib";

  cargoSha256 = if pkgs ? cargo-vendor then
    # nixpkgs ≤ 19.09
    "19qs8if8fmygv6j74s6iwzm534fybwasjvmzdqcl996xhg75w6gi"
  else
    # for recent nixpkgs with cargo-native vendoring (introduced in nixpkgs PR #69274)
    "1x88zj7p4i7pfb25ch1a54sawgimq16bfcsz1nmzycc8nbwbf493";

  meta = with lib; {
    description = "An efficient Electrum Server in Rust";
    homepage = "https://github.com/romanz/electrs";
    license = licenses.mit;
    maintainers = with maintainers; [ earvstedt ];
  };
}

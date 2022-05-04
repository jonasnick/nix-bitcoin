{ poetry2nix
, fetchzip
, python3
, clightning
, cffi
, pycparser
, coincurve
, cryptography
}:

let
  s = fetchzip { url = "file://" + clightning.src; hash = "sha256-PV4QCFWuAkt6X4DShpyYtyTwgFX08NTbJ62MU9eXauI="; };
in
poetry2nix.mkPoetryApplication {
  poetrylock = ./poetry.lock;
  projectDir = s + "/contrib/pyln-proto";
  src = s + "/contrib/pyln-proto";
    overrides = poetry2nix.overrides.withDefaults (self: super: {
      # workaround for https://github.com/nix-community/poetry2nix/issues/568
      pyparsing = super.pyparsing.overridePythonAttrs (old: {
        buildInputs = old.buildInputs or [ ] ++ [ python3.pkgs.flit-core ];
      });
      # When poetry2nix builds this, I get error
      #   Found duplicated packages in closure for dependency  'cffi': ...
      #   Found duplicated packages in closure for dependency  'pycparser': ...
      inherit cffi;
      inherit pycparser;
      # building cryptography requires a lot of tooling (rust?) and fails when
      # built through poetry2nix
      inherit cryptography;
   });
}

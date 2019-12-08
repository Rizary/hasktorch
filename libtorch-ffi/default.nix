{ shared ? import ../nix/shared.nix { }
, pkgs ? import <nixpkgs> {}
}:

let
  libtorch_src =
    let src = pkgs.fetchFromGitHub {
          owner  = "stites";
          repo   = "pytorch-world";
          rev    = "ebfe09208964af96ae4d5cf1f70d154b16826c6e";
          sha256 = "1x3jn55ygggg92kbrqvl9q8wgcld8bwxm12j2i5j1cyyhhr1p852";
    };
    in (pkgs.callPackage "${src}/libtorch/release.nix" { });

  c10 = libtorch_src.libtorch_cpu;
  torch = libtorch_src.libtorch_cpu;

  haskellPackages =
    pkgs.haskell.packages.ghc865.extend (newPkgs: old: {
      libtorch-ffi = old.callPackage ./libtorch-ffi.nix {
        inherit c10 torch;
      };
    });

in
 { inherit (haskellPackages)
   libtorch-ffi;
 }

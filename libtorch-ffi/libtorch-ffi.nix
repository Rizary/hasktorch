{ mkDerivation, async, base, bytestring, c10, containers, hspec
, hspec-discover, inline-c, inline-c-cpp, optparse-applicative
, safe-exceptions, stdenv, sysinfo, template-haskell, torch
}:
mkDerivation {
  pname = "libtorch-ffi";
  version = "1.3.0.0";
  src = ./.;
  libraryHaskellDepends = [
    async base bytestring containers inline-c inline-c-cpp
    optparse-applicative safe-exceptions sysinfo template-haskell
  ];
  librarySystemDepends = [ c10 torch ];
  testHaskellDepends = [
    base containers hspec hspec-discover inline-c inline-c-cpp
    optparse-applicative safe-exceptions
  ];
  testToolDepends = [ hspec-discover ];
  homepage = "https://github.com/hasktorch/hasktorch#readme";
  description = "test out alternative options for ffi interface to libtorch 1.x";
  license = stdenv.lib.licenses.bsd3;
}

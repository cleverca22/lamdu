{ mkDerivation, base, fetchgit, stdenv, nodejs-6_x, which }:
mkDerivation {
  pname = "nodejs-exec";
  version = "0.1.0.0";
  src = fetchgit {
    url = "https://github.com/razvan-panda/nodejs-exec";
    sha256 = "1m5sn6njpfz22m96smgjf4iyr26yfizbci71xpkz9fvfnwh5yknc";
    rev = "2045b123bf0793fc9cde53e18f257102db19d8b3";
  };
  enableSeparateDataOutput = true;
  libraryHaskellDepends = [ base ];
  extraLibraries = [ nodejs-6_x which ];
  homepage = "https://github.com/lamdu/nodejs-exec";
  description = "Package providing a nodejs installation";
  license = stdenv.lib.licenses.bsd3;
}

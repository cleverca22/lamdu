let config = {
    packageOverrides = pkgs: {
        haskellPackages = pkgs.haskellPackages.override {
            overrides = self: super: {
                AlgoW = self.callPackage ./AlgoW.nix {};
                lamdu-calculus = self.callPackage  ./lamdu-calculus.nix {};
                nodejs-exec = self.callPackage ./nodejs-exec.nix {};
                OpenGL = self.callPackage ./OpenGL.nix {};
                imagemagick = pkgs.haskell.lib.doJailbreak super.imagemagick;
                graphics-drawingcombinators = self.callPackage ./graphics-drawingcombinators.nix {};
                freetype-gl = self.callPackage ./freetype-gl.nix {};
                anttweakbar = self.callPackage ./AntTweakBar.nix {};
            };
        };
    };
};
in with import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/f607771d0f5.tar.gz") { 
    inherit config;
};

{ lamdu = haskellPackages.callPackage ./lamdu.nix {}; }
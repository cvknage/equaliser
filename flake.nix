{
  description = "Equaliser gh-pages devshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {nixpkgs, ...}: let
    systems = ["aarch64-darwin"];
  in {
    devShells = nixpkgs.lib.genAttrs systems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShellNoCC {
        name = "gh-pages-devshell";

        packages = with pkgs; [
          pandoc
        ];

        shellHook = ''
        '';
      };
    });
  };
}

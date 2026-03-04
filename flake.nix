{
  description = "Equaliser macOS app devshell";

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
        name = "equaliser-devshell";

        packages = with pkgs; [
          librsvg # SVG to PNG conversion (rsvg-convert)
        ];

        shellHook = ''
          # Use system Xcode toolchain (append to preserve existing PATH)
          export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
          export PATH="$PATH:/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
          export PATH="$PATH:/usr/bin"

          echo "Equaliser devshell loaded"
          echo "swift: $(which swift)"
          echo "rsvg-convert: $(which rsvg-convert)"
        '';
      };
    });
  };
}

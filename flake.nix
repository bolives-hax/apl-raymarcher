{
  description = "flake building raymarcher written in dyalog apl + rust plotting helpers";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url  = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay}:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
        unfreePkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
        #insecurePkgs = import nixpkgs {
        #  inherit system;
        #  config = {
        #    allowInsecure = true;
        #    permittedInsecurePackages = [
        #      "freeimage-unstable-2021-11-01"
        #    ];
        #  };
        #};

        xres = 130;
        yres = 100;
      in with pkgs; let
          rustPlatform = makeRustPlatform {
            cargo = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
            rustc = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default);
          };
          drawlib = rustPlatform.buildRustPackage {
            pname = "apl-raymarcher-drawlib";
            version = "1.0.0";
            src = ./.;
            cargoHash = "sha256-23SRWxfYMQ9tvU5VcZtbDvThHTrWdNQNTczUYGR0fqQ=";
          };
        aplWayland = pkgs.writeTextFile {
          name = "apl-raymarcher-wayland";
          text = ''
            drawlib_path←'${drawlib}/lib/libapl_window_draw_helper.so'
            draw_backend←'wayland'
            ${builtins.readFile ./raymarcher.apl}
          '';
        };
        aplPng = pkgs.writeTextFile {
          name = "apl-raymarcher-png";
          text = ''
            drawlib_path←'${drawlib}/lib/libapl_window_draw_helper.so'
            png_xres←${toString xres} ⋄ png_yres←${toString yres}
            png_outpath←'lol.png'
            draw_backend←'png'
            ${builtins.readFile ./raymarcher.apl}
          '';
        };
        dyalog = (unfreePkgs.dyalog.override {
          acceptLicense = true;
        });
      in {

        packages.waylandRunner = pkgs.writeShellScriptBin "apl-raymarcher-wayland-runner" ''
              LD_LIBRARY_PATH = "${lib.makeLibraryPath [wayland]}"
              ${dyalog}/bin/dyalogscript ${aplWayland}
        '';
        packages.pngRunner = pkgs.writeShellScriptBin "apl-raymarcher-png-runner"
          "${dyalog}/bin/dyalogscript ${aplPng}";

        devShells.default = with pkgs; mkShell rec {
          buildInputs = [
            (unfreePkgs.dyalog.override {
              acceptLicense = true;
            })
            #insecurePkgs.arrayfire
            rust-bin.nightly.latest.default
            libxkbcommon
            libGL

            # WINIT_UNIX_BACKEND=wayland
            wayland

            # WINIT_UNIX_BACKEND=x11
            xorg.libXcursor
            xorg.libXrandr
            xorg.libXi
            xorg.libX11

          ];
          LD_LIBRARY_PATH = "${lib.makeLibraryPath buildInputs}";


          #shellHook = ''
          #'';
        };
    });
}


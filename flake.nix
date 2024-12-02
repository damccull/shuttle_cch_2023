{
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    rust-overlay.url = "github:oxalica/rust-overlay";
    # surrealdb-gh.url = "github:surrealdb/surrealdb/v2.0.4";
  };
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      perSystem =
        {
          config,
          self',
          pkgs,
          lib,
          system,
          ...
        }:
        let
          runtimeDeps = with pkgs; [
            # Dependencies needed for running (linked libraries like openssl)
          ];
          buildDeps = with pkgs; [
            # Libraries and programs required to compile the program
            # Included in devshell
            clang
            lld
            lldb
            pkg-config
            rustPlatform.bindgenHook
            stdenv.cc.cc.lib
          ];
          devDeps = with pkgs; [
            # Libraries and programs needed for dev work; included in dev shell
            # NOT included in the nix build operation
            bashInteractive
            bunyan-rs
            cargo-deny
            cargo-edit
            cargo-expand
            cargo-msrv
            cargo-nextest
            cargo-watch
            (cargo-whatfeatures.overrideAttrs (oldAttrs: rec {
              pname = "cargo-whatfeatures";
              version = "0.9.13";
              src = fetchFromGitHub {
                owner = "museun";
                repo = "cargo-whatfeatures";
                rev = "v0.9.13";
                sha256 = "sha256-YJ08oBTn9OwovnTOuuc1OuVsQp+/TPO3vcY4ybJ26Ms=";
              };
              cargoDeps = oldAttrs.cargoDeps.overrideAttrs (
                lib.const {
                  name = "${pname}-vendor.tar.gz";
                  inherit src;
                  outputHash = "sha256-8pccXL+Ud3ufYcl2snoSxIfGM1tUR53GUrIp397Rh3o=";
                }
              );
              cargoBuildFlags = [
                "--no-default-features"
                "--features=rustls"
              ];
            }))
            flyctl
            gdb
            just
            nushell
            panamax
            zellij
          ];
          # ++ [
          #   inputs.surrealdb-gh.packages.${system}.default
          # ];

          cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
          msrv = cargoToml.package.rust-version;

          rustPackage =
            features:
            (pkgs.makeRustPlatform {
              cargo = pkgs.rust-bin.stable.latest.minimal;
              rustc = pkgs.rust-bin.stable.latest.minimal;
            }).buildRustPackage
              {
                inherit (cargoToml.package) name version;
                src = ./.;
                cargoLock.lockFile = ./Cargo.lock;
                buildFeatures = features;
                buildInputs = runtimeDeps;
                nativeBuildInputs = buildDeps;
                # Uncomment if your cargo tests require networking or otherwise
                # don't play nicely with the nix build sandbox:
                # doCheck = false;
              };

          mkDevShell =
            rustc:
            pkgs.mkShell {
              shellHook = ''
                # TODO: figure out if it's possible to remove this or allow a user's preferred shell
                exec env SHELL=${pkgs.bashInteractive}/bin/bash zellij --layout ./zellij_layout.kdl
              '';
              # LD_LIBRARY_PATH =
              #   with pkgs;
              #   lib.makeLibraryPath [
              #     stdenv.cc.cc.lib
              #   ];
              RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
              buildInputs = runtimeDeps;
              nativeBuildInputs = buildDeps ++ devDeps ++ [ rustc ];
            };

        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ (import inputs.rust-overlay) ];
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (lib.getName pkg) [
                "surrealdb"
              ];
          };

          packages.default = self'.packages.base;
          devShells.default = self'.devShells.nightly;

          packages.base = (rustPackage "");
          packages.bunyan = (rustPackage "bunyan");
          packages.tokio-console = (rustPackage "tokio-console");

          devShells.nightly = (
            mkDevShell (
              pkgs.rust-bin.selectLatestNightlyWith (
                toolchain:
                toolchain.default.override {
                  extensions = [ "rust-analyzer" ];
                }
              )
            )
          );
          devShells.stable = (
            mkDevShell (
              pkgs.rust-bin.stable.latest.default.override {
                extensions = [ "rust-analyzer" ];
              }
            )
          );
          devShells.msrv = (
            mkDevShell (
              pkgs.rust-bin.stable.${msrv}.default.override {
                extensions = [ "rust-analyzer" ];
              }
            )
          );
        };
    };
}

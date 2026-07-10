{
  description = "mlqs — native QML/Quickshell mail client (Go daemon + vendored UI)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      daemon = pkgs.buildGoModule {
        pname = "mlqs";
        version = "0.1.0";
        src = ./.;
        vendorHash = "sha256-cR5w5qdIKJei51Z7t7EHC4N/jNg4g9vYrf/RGJUe0F8=";
        subPackages = [ "." ];
        postInstall = ''
          mkdir -p $out/share/mlqs
          cp -r ui $out/share/mlqs/ui
        '';
        meta.mainProgram = "mlqs";
      };

      client = pkgs.writeShellApplication {
        name = "mlqs-client";
        runtimeInputs = [ daemon pkgs.quickshell pkgs.procps pkgs.coreutils pkgs.xdg-utils pkgs.wl-clipboard ];
        text = ''
          # QsLib shared QML module (dotfiles-managed, out of store)
          export QML2_IMPORT_PATH="$HOME/.local/share/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
          sock="$XDG_RUNTIME_DIR/mlqs.sock"
          if ! pgrep -x mlqs >/dev/null 2>&1; then
            rm -f "$sock"
            setsid nohup ${daemon}/bin/mlqs >/tmp/mlqs-daemon.log 2>&1 </dev/null &
          fi
          for _ in $(seq 1 150); do [ -S "$sock" ] && break; sleep 0.1; done
          exec qs -p "${daemon}/share/mlqs/ui"
        '';
      };
    in {
      packages.${system} = {
        mlqs = daemon;
        mlqs-client = client;
        default = client;
      };
    };
}

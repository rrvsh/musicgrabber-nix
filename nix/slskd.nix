{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      version = "0.26.0";

      slskdDarwin = pkgs.stdenvNoCC.mkDerivation {
        pname = "slskd-unwrapped";
        inherit version;

        src = pkgs.fetchzip {
          url = "https://github.com/slskd/slskd/releases/download/${version}/slskd-${version}-osx-arm64.zip";
          hash = "sha256-vdoJy2ZpElYJA43mNZfExNK4Mpnw8ApVxVDzPq1s97I=";
          stripRoot = false;
        };

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/libexec/slskd"
          cp -R . "$out/libexec/slskd/"
          chmod +x "$out/libexec/slskd/slskd"

          runHook postInstall
        '';

        meta = {
          description = "Modern client-server application for the Soulseek file-sharing network";
          homepage = "https://github.com/slskd/slskd";
          license = lib.licenses.agpl3Only;
          platforms = [ "aarch64-darwin" ];
        };
      };

      slskdUnwrapped =
        if pkgs.stdenv.hostPlatform.isDarwin then
          slskdDarwin
        else
          assert lib.assertMsg (
            pkgs.slskd.version == version
          ) "Update the tested slskd version before updating the Linux package";
          pkgs.slskd;

      slskdProgram =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${slskdDarwin}/libexec/slskd/slskd"
        else
          lib.getExe slskdUnwrapped;

      slskdExampleConfig =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${slskdDarwin}/libexec/slskd/config/slskd.example.yml"
        else
          "${slskdUnwrapped}/lib/slskd/config/slskd.example.yml";

      slskd = pkgs.writeShellApplication {
        name = "slskd";

        derivationArgs = {
          inherit version;
        };

        passthru = {
          unwrapped = slskdUnwrapped;
        };

        runtimeInputs = [ pkgs.coreutils ];

        text = ''
          umask 077

          # Safe defaults for local MusicGrabber use. YAML and command-line
          # settings can deliberately override these values.
          export SLSKD_HTTP_IP_ADDRESS="''${SLSKD_HTTP_IP_ADDRESS:-127.0.0.1}"
          export SLSKD_NO_HTTPS="''${SLSKD_NO_HTTPS:-true}"
          export SLSKD_REMOTE_CONFIGURATION="''${SLSKD_REMOTE_CONFIGURATION:-false}"
          export SLSKD_REMOTE_FILE_MANAGEMENT="''${SLSKD_REMOTE_FILE_MANAGEMENT:-false}"
          export SLSKD_NO_VERSION_CHECK="''${SLSKD_NO_VERSION_CHECK:-true}"

          ${
            if pkgs.stdenv.hostPlatform.isDarwin then
              ''export SLSKD_APP_DIR="''${SLSKD_APP_DIR:-$HOME/Library/Application Support/slskd}"''
            else
              ''export SLSKD_APP_DIR="''${SLSKD_APP_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/slskd}"''
          }

          uses_cli_config_path=false
          for argument in "$@"; do
            case "$argument" in
              -a|-a=*|--app-dir|--app-dir=*|-c|-c=*|--config|--config=*)
                uses_cli_config_path=true
                ;;
            esac
          done

          if [[ -z "''${SLSKD_CONFIG:-}" && "$uses_cli_config_path" == false ]]; then
            mkdir -p "$SLSKD_APP_DIR"
            chmod 700 "$SLSKD_APP_DIR"
            if [[ ! -e "$SLSKD_APP_DIR/slskd.yml" ]]; then
              install -m 600 ${slskdExampleConfig} "$SLSKD_APP_DIR/slskd.yml"
            else
              chmod go-rwx "$SLSKD_APP_DIR/slskd.yml"
            fi
          fi

          exec ${slskdProgram} "$@"
        '';

        meta = {
          description = "Local-first slskd companion for MusicGrabber";
          homepage = "https://github.com/slskd/slskd";
          license = lib.licenses.agpl3Only;
          mainProgram = "slskd";
          platforms = [
            "aarch64-darwin"
            "aarch64-linux"
            "x86_64-linux"
          ];
        };
      };
    in
    {
      packages.slskd = slskd;

      apps.slskd = {
        type = "app";
        program = "${slskd}/bin/slskd";
        meta.description = "Run the optional slskd Soulseek companion";
      };
    };
}

{
  inputs,
  projectRoot,
  ...
}:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
      inherit (inputs) pyproject-build-systems pyproject-nix uv2nix;
      inherit (pkgs) lib;

      version = (builtins.fromTOML (builtins.readFile (projectRoot + "/pyproject.toml"))).project.version;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = projectRoot; };
      pythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          python = pkgs.python312;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.wheel
              (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
            ]
          );
      pythonEnv = pythonSet.mkVirtualEnv "musicgrabber-python-env" workspace.deps.default;

      playwrightComponents = pkgs.playwright-driver.components;
      playwrightSources = {
        chromium = {
          x86_64-linux = {
            url = "https://cdn.playwright.dev/builds/cft/145.0.7632.6/linux64/chrome-linux64.zip";
            hash = "sha256-dJSO05xOzlSl/EwOWNQCeuSb+lhUU6NlGBnRu59irnM=";
          };
          aarch64-linux = {
            url = "https://cdn.playwright.dev/dbazure/download/playwright/builds/chromium/1208/chromium-linux-arm64.zip";
            hash = "sha256-9DFLCPuc9WZjYLzlRW+Df2pb+mViPK3/IOkkUozELsw=";
          };
          aarch64-darwin = {
            url = "https://cdn.playwright.dev/builds/cft/145.0.7632.6/mac-arm64/chrome-mac-arm64.zip";
            hash = "sha256-qXdgHeBS5IFIa4hZVmjq0+31v/uDPXHyc4aH7Wn2E7E=";
          };
        };
        chromium-headless-shell = {
          x86_64-linux = {
            url = "https://cdn.playwright.dev/builds/cft/145.0.7632.6/linux64/chrome-headless-shell-linux64.zip";
            hash = "sha256-/xskLzTc9tTZmu1lwkMpjV3QV7XjP92D/7zRcFuVWT8=";
          };
          aarch64-linux = {
            url = "https://cdn.playwright.dev/dbazure/download/playwright/builds/chromium/1208/chromium-headless-shell-linux-arm64.zip";
            hash = "sha256-jckH5+eGJ4BhH1NAa5LIgf3/salKLAHW9XUOo5gob4c=";
          };
          aarch64-darwin = {
            url = "https://cdn.playwright.dev/builds/cft/145.0.7632.6/mac-arm64/chrome-headless-shell-mac-arm64.zip";
            hash = "sha256-45DjMIu0t7IEYdXOmIqpV/1/MKdEfx/8T7DWagh6Zhc=";
          };
        };
      };
      overrideBrowserSource =
        derivation: source:
        derivation.overrideAttrs (_: {
          urls = [ source.url ];
          inherit (source) hash;
          outputHash = source.hash;
        });
      chromium =
        if pkgs.stdenv.hostPlatform.isDarwin then
          overrideBrowserSource playwrightComponents.chromium playwrightSources.chromium.${system}
        else
          playwrightComponents.chromium.overrideAttrs (
            previous:
            {
              src = overrideBrowserSource previous.src playwrightSources.chromium.${system};
            }
            // lib.optionalAttrs (system == "aarch64-linux") {
              installPhase = ''
                runHook preInstall
                mkdir -p "$out/chrome-linux"
                cp -R . "$out/chrome-linux"
                wrapProgram "$out/chrome-linux/chrome" \
                  --set-default SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
                  --set-default FONTCONFIG_FILE ${pkgs.makeFontsConf { fontDirectories = [ ]; }}
                runHook postInstall
              '';
              postFixup = ''
                rm "$out/chrome-linux/libvulkan.so.1"
                ln -s -t "$out/chrome-linux" "${lib.getLib pkgs.vulkan-loader}/lib/libvulkan.so.1"
              '';
            }
          );
      browsers =
        assert pkgs.playwright-driver.browsersJSON.ffmpeg.revision == "1011";
        pkgs.linkFarm "playwright-browsers-1.58" [
          {
            name = "chromium-1208";
            path = chromium;
          }
          {
            name = "chromium_headless_shell-1208";
            path =
              if pkgs.stdenv.hostPlatform.isDarwin then
                overrideBrowserSource playwrightComponents.chromium-headless-shell
                  playwrightSources.chromium-headless-shell.${system}
              else
                playwrightComponents.chromium-headless-shell.overrideAttrs (previous: {
                  src = overrideBrowserSource previous.src playwrightSources.chromium-headless-shell.${system};
                });
          }
          {
            name = "ffmpeg-1011";
            path = playwrightComponents.ffmpeg;
          }
        ];

      application = pkgs.stdenvNoCC.mkDerivation {
        pname = "musicgrabber-application";
        inherit version;
        src = pkgs.fetchFromGitLab {
          owner = "g33kphr33k";
          repo = "musicgrabber";
          rev = "7953eb6abe74c070899826d6e2352075ae7710ab";
          hash = "sha256-a1E4dgg9j2rOsmN2y4wVCIbrXVSja3qwysYrKR0QGLc=";
        };
        patches = [ (projectRoot + "/patches/native-package.patch") ];
        installPhase = ''
          runHook preInstall
          rm -f constants.py.orig
          mkdir -p "$out/share/musicgrabber"
          cp -R . "$out/share/musicgrabber/"
          runHook postInstall
        '';
      };
      musicgrabber = pkgs.writeShellApplication {
        name = "musicgrabber";
        runtimeInputs = [
          (pkgs.chromaprint.overrideAttrs (previous: {
            postFixup = (previous.postFixup or "") + ''
              rm -rf "$out/include" "$out/lib/cmake" "$out/lib/pkgconfig"
            '';
          }))
          pkgs.coreutils
          pkgs.deno
          pkgs.ffmpeg-headless
        ];
        passthru = {
          inherit application browsers pythonEnv;
        };
        derivationArgs = { inherit version; };
        text = ''
          umask 077
          export PATH="${pythonEnv}/bin:$PATH"

          if [[ -n "''${XDG_DATA_HOME:-}" ]]; then
            default_state_dir="$XDG_DATA_HOME/musicgrabber"
          elif [[ "$(uname -s)" == "Darwin" ]]; then
            default_state_dir="$HOME/Library/Application Support/MusicGrabber"
          else
            default_state_dir="$HOME/.local/share/musicgrabber"
          fi

          state_dir="''${MUSICGRABBER_STATE_DIR:-$default_state_dir}"
          export DB_PATH="''${DB_PATH:-$state_dir/music_grabber.db}"
          export COOKIES_FILE="''${COOKIES_FILE:-$state_dir/cookies.txt}"
          export MUSIC_DIR="''${MUSIC_DIR:-$HOME/Music/MusicGrabber}"
          export LISTEN_ADDR="''${LISTEN_ADDR:-127.0.0.1}"
          export LISTEN_PORT="''${LISTEN_PORT:-8080}"
          export PLAYWRIGHT_BROWSERS_PATH="''${PLAYWRIGHT_BROWSERS_PATH:-${browsers}}"
          export SSL_CERT_FILE="''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}"
          export CURL_CA_BUNDLE="''${CURL_CA_BUNDLE:-$SSL_CERT_FILE}"
          export MONOCHROME_BROWSER_FALLBACK_ENABLED="''${MONOCHROME_BROWSER_FALLBACK_ENABLED:-false}"
          export SOURCE_MP3PHOENIX_ENABLED="''${SOURCE_MP3PHOENIX_ENABLED:-false}"
          export YTDLP_AUTO_UPDATE="''${YTDLP_AUTO_UPDATE:-false}"
          export MUSICGRABBER_NATIVE_PACKAGE=true

          mkdir -p -- "$(dirname -- "$DB_PATH")" "$(dirname -- "$COOKIES_FILE")" "$MUSIC_DIR"
          cd ${application}/share/musicgrabber
          exec ${pythonEnv}/bin/uvicorn app:app --host "$LISTEN_ADDR" --port "$LISTEN_PORT" "$@"
        '';
        meta = {
          description = "Self-hosted music acquisition and playlist synchronization tool";
          homepage = "https://gitlab.com/g33kphr33k/musicgrabber";
          license = lib.licenses.unlicense;
          mainProgram = "musicgrabber";
          platforms = [
            "aarch64-darwin"
            "aarch64-linux"
            "x86_64-linux"
          ];
        };
      };
    in
    {
      packages = {
        default = musicgrabber;
        inherit musicgrabber;
      };

      apps.default = {
        type = "app";
        program = "${musicgrabber}/bin/musicgrabber";
        meta.description = "Run MusicGrabber";
      };
    };
}

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
              (
                final: previous:
                builtins.listToAttrs (
                  map
                    (name: {
                      inherit name;
                      value = previous.${name}.overrideAttrs (old: {
                        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
                        passthru =
                          (old.passthru or { })
                          //
                            lib.optionalAttrs
                              (builtins.elem name [
                                "mouseinfo"
                                "pyautogui"
                              ])
                              {
                                dependencies = removeAttrs old.passthru.dependencies [ "python3-xlib" ];
                              };
                      });
                    })
                    [
                      "mouseinfo"
                      "pyautogui"
                      "pygetwindow"
                      "pyrect"
                      "pyscreeze"
                      "python3-xlib"
                      "pytweening"
                    ]
                )
              )
            ]
          );
      pythonEnvBase = pythonSet.mkVirtualEnv "musicgrabber-python-env-base" workspace.deps.default;
      pythonEnv =
        if pkgs.stdenv.hostPlatform.isLinux then
          pkgs.symlinkJoin {
            name = "musicgrabber-python-env";
            paths = [
              pythonEnvBase
              pkgs.python312Packages.tkinter
            ];
          }
        else
          pythonEnvBase;

      playwrightComponents = pkgs.playwright-driver.components;
      seleniumVersion = "153.0.8010.12";
      seleniumDriverSources = {
        aarch64-darwin = {
          url = "https://storage.googleapis.com/chrome-for-testing-public/${seleniumVersion}/mac-arm64/chromedriver-mac-arm64.zip";
          hash = "sha256-/ipGRAIKk+eWFNVHB0kyuesMAO00uf7A4dh+LubSSIY=";
          directory = "chromedriver-mac-arm64";
        };
        x86_64-linux = {
          url = "https://storage.googleapis.com/chrome-for-testing-public/${seleniumVersion}/linux64/chromedriver-linux64.zip";
          hash = "sha256-t9X3wSD3gn81OLQW4IuCQY63AvGLaAwYPwQRyNfy32k=";
          directory = "chromedriver-linux64";
        };
        aarch64-linux = {
          url = "https://storage.googleapis.com/chrome-for-testing-public/${seleniumVersion}/linux-arm64/chromedriver-linux-arm64.zip";
          hash = "sha256-cTOhuFfydK4o899SjO39GzX+s69m7hW1lsAHVXk51QI=";
          directory = "chromedriver-linux-arm64";
        };
      };
      seleniumDriverSource = seleniumDriverSources.${system};
      seleniumDriver = pkgs.stdenv.mkDerivation {
        pname = "musicgrabber-chromedriver";
        version = seleniumVersion;
        src = pkgs.fetchurl {
          inherit (seleniumDriverSource) url hash;
        };
        sourceRoot = seleniumDriverSource.directory;
        nativeBuildInputs = [
          pkgs.unzip
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
        buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.dbus
          pkgs.glib
          pkgs.nspr
          pkgs.nss
          pkgs.stdenv.cc.cc.lib
          pkgs.libxcb
        ];
        dontConfigure = true;
        dontBuild = true;
        dontStrip = pkgs.stdenv.hostPlatform.isDarwin;
        installPhase = ''
          runHook preInstall
          install -Dm755 chromedriver "$out/bin/chromedriver"
          runHook postInstall
        '';
      };
      seleniumBrowser =
        assert pkgs.playwright-driver.browsersJSON.chromium.browserVersion == seleniumVersion;
        playwrightComponents.chromium;
      seleniumBrowserBinary =
        {
          aarch64-darwin = "${seleniumBrowser}/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";
          x86_64-linux = "${seleniumBrowser}/chrome-linux64/chrome";
          aarch64-linux = "${seleniumBrowser}/chrome-linux-arm64/chrome";
        }
        .${system};
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
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.xauth
          pkgs.xvfb
        ];
        passthru = {
          inherit
            application
            browsers
            pythonEnv
            seleniumBrowser
            seleniumBrowserBinary
            seleniumDriver
            seleniumVersion
            ;
        };
        derivationArgs = { inherit version; };
        text = ''
          umask 077
          export PATH="${pythonEnv}/bin:$PATH"

          platform="$(uname -s)"

          if [[ -n "''${XDG_DATA_HOME:-}" ]]; then
            default_state_dir="$XDG_DATA_HOME/musicgrabber"
          elif [[ "$platform" == "Darwin" ]]; then
            default_state_dir="$HOME/Library/Application Support/MusicGrabber"
          else
            default_state_dir="$HOME/.local/share/musicgrabber"
          fi

          if [[ -n "''${XDG_CACHE_HOME:-}" ]]; then
            default_cache_dir="$XDG_CACHE_HOME/musicgrabber"
          elif [[ "$platform" == "Darwin" ]]; then
            default_cache_dir="$HOME/Library/Caches/MusicGrabber"
          else
            default_cache_dir="$HOME/.cache/musicgrabber"
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
          export MUSICGRABBER_SELENIUM_BROWSER="''${MUSICGRABBER_SELENIUM_BROWSER:-${seleniumBrowserBinary}}"
          export MUSICGRABBER_SELENIUM_DRIVER_SOURCE="''${MUSICGRABBER_SELENIUM_DRIVER_SOURCE:-${seleniumDriver}/bin/chromedriver}"
          export MUSICGRABBER_SELENIUM_DRIVER_DIR="''${MUSICGRABBER_SELENIUM_DRIVER_DIR:-''${MUSICGRABBER_SELENIUM_CACHE_DIR:-$default_cache_dir}/seleniumbase-${seleniumVersion}}"
          export MUSICGRABBER_SELENIUM_VERSION="''${MUSICGRABBER_SELENIUM_VERSION:-${seleniumVersion}}"
          export SE_OFFLINE="''${SE_OFFLINE:-true}"
          export MONOCHROME_BROWSER_FALLBACK_ENABLED="''${MONOCHROME_BROWSER_FALLBACK_ENABLED:-true}"
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

{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      musicgrabber = self'.packages.musicgrabber;
    in
    {
      checks = {
        package = musicgrabber;

        application =
          pkgs.runCommand "musicgrabber-application-check"
            {
              nativeBuildInputs = [ musicgrabber.pythonEnv ];
            }
            ''
              export HOME="$TMPDIR/home"
              export DB_PATH="$TMPDIR/state/music_grabber.db"
              export COOKIES_FILE="$TMPDIR/state/cookies.txt"
              export MUSIC_DIR="$TMPDIR/music"
              export MONOCHROME_BROWSER_FALLBACK_ENABLED=false
              export MUSICGRABBER_NATIVE_PACKAGE=true
              mkdir -p "$HOME" "$MUSIC_DIR" "$(dirname "$DB_PATH")"
              cd ${musicgrabber.application}/share/musicgrabber
              ${musicgrabber.pythonEnv}/bin/python - <<'PY'
              import os

              import apprise
              import bcrypt
              import curl_cffi
              import fastapi
              import httpx
              import mutagen
              import playwright
              import pydantic
              import selenium
              import seleniumbase
              import uvicorn
              import app
              import monochrome_browser
              import mp3phoenix_browser
              from constants import COOKIES_FILE
              from selenium_runtime import browser_options
              from types import SimpleNamespace

              assert str(COOKIES_FILE).endswith("state/cookies.txt")
              assert app._is_volume_mounted() is True
              if os.uname().sysname == "Darwin":
                  assert monochrome_browser._broker_environment()["HOME"] == os.environ["HOME"]

              blocked_page = SimpleNamespace(
                  cdp=SimpleNamespace(
                      evaluate=lambda script: (
                          "Attention Required! | Cloudflare"
                          if script == "document.title"
                          else ""
                      )
                  )
              )
              try:
                  mp3phoenix_browser._wait_for_access(blocked_page, 20)
              except RuntimeError as exc:
                  assert str(exc) == "MP3Phoenix blocked this network through Cloudflare"
              else:
                  raise AssertionError("MP3Phoenix Cloudflare block was not detected")
              PY
              touch "$out"
            '';

        selenium =
          if pkgs.stdenv.hostPlatform.isLinux then
            pkgs.runCommand "musicgrabber-selenium-check"
              {
                nativeBuildInputs = [
                  musicgrabber.pythonEnv
                  pkgs.xauth
                  pkgs.xvfb
                ];
              }
              ''
                export HOME="$TMPDIR/home"
                export MUSICGRABBER_SELENIUM_BROWSER="${musicgrabber.seleniumBrowserBinary}"
                export MUSICGRABBER_SELENIUM_DRIVER_SOURCE="${musicgrabber.seleniumDriver}/bin/chromedriver"
                export MUSICGRABBER_SELENIUM_DRIVER_DIR="$TMPDIR/driver"
                export MUSICGRABBER_SELENIUM_VERSION="${musicgrabber.seleniumVersion}"
                export SE_OFFLINE=true
                export SELENIUM_CHECK_MARKER="$TMPDIR/selenium-check-passed"

                mkdir -p "$HOME"
                cd ${musicgrabber.application}/share/musicgrabber

                ${musicgrabber.pythonEnv}/bin/python - <<'PY'
                import os
                from pathlib import Path

                from seleniumbase.console_scripts import sb_install

                def reject_download(*args, **kwargs):
                    raise RuntimeError(
                        f"Runtime Selenium download attempted: {args} {kwargs}"
                    )

                sb_install.main = reject_download

                from seleniumbase import SB
                from selenium_runtime import browser_options

                marker = Path(os.environ["SELENIUM_CHECK_MARKER"])
                with SB(**browser_options()) as browser:
                    browser.activate_cdp_mode(
                        "data:text/html,"
                        "<title>Selenium Nix probe</title>"
                        '<h1 id="ok">working</h1>'
                    )
                    assert browser.cdp.evaluate("document.title") == "Selenium Nix probe"
                    assert (
                        browser.cdp.evaluate(
                            "document.querySelector('#ok').textContent"
                        )
                        == "working"
                    )
                    marker.write_text("passed\n")
                PY

                test -f "$SELENIUM_CHECK_MARKER"
                touch "$out"
              ''
          else
            pkgs.runCommand "musicgrabber-selenium-check"
              {
                nativeBuildInputs = [ musicgrabber.pythonEnv ];
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"

                browser_version="$("${musicgrabber.seleniumBrowserBinary}" --version)"
                driver_version="$(${musicgrabber.seleniumDriver}/bin/chromedriver --version)"

                case "$browser_version" in
                  *"${musicgrabber.seleniumVersion}"*) ;;
                  *)
                    printf 'Unexpected browser version: %s\n' "$browser_version" >&2
                    exit 1
                    ;;
                esac

                case "$driver_version" in
                  *"${musicgrabber.seleniumVersion}"*) ;;
                  *)
                    printf 'Unexpected driver version: %s\n' "$driver_version" >&2
                    exit 1
                    ;;
                esac

                ${musicgrabber.pythonEnv}/bin/python - <<'PY'
                import selenium
                import seleniumbase
                PY

                touch "$out"
              '';
      };
    };
}

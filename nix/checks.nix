{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      musicgrabber = self'.packages.musicgrabber;
      slskd = self'.packages.slskd;
    in
    {
      checks = {
        package = musicgrabber;
        slskd-package = slskd;

        slskd-version =
          pkgs.runCommand "slskd-version-check"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                slskd
              ];
            }
            ''
              export HOME="$TMPDIR/home"
              export DOTNET_BUNDLE_EXTRACT_BASE_DIR="$TMPDIR/dotnet"
              mkdir -p "$HOME" "$DOTNET_BUNDLE_EXTRACT_BASE_DIR"
              slskd --version | grep -F "0.26.0" > "$out"
            '';

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
              export MUSICGRABBER_NATIVE_PACKAGE=true
              mkdir -p "$HOME" "$MUSIC_DIR" "$(dirname "$DB_PATH")"
              cd ${musicgrabber.application}/share/musicgrabber
              ${musicgrabber.pythonEnv}/bin/python - <<'PY'
              import apprise
              import bcrypt
              import curl_cffi
              import fastapi
              import httpx
              import mutagen
              import playwright
              import pydantic
              import uvicorn
              import app
              from constants import COOKIES_FILE

              assert str(COOKIES_FILE).endswith("state/cookies.txt")
              assert app._is_volume_mounted() is True
              PY
              touch "$out"
            '';
      };
    };
}

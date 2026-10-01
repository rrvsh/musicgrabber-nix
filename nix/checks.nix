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

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

        slskd-application =
          pkgs.runCommand "slskd-application-check"
            {
              nativeBuildInputs = [
                pkgs.curl
                pkgs.jq
                slskd
              ];
            }
            ''
              export HOME="$TMPDIR/home"
              export DOTNET_BUNDLE_EXTRACT_BASE_DIR="$TMPDIR/dotnet"
              export SLSKD_APP_DIR="$TMPDIR/slskd"
              export SLSKD_HTTP_PORT="$((20000 + ($$ % 20000)))"
              mkdir -p "$HOME" "$DOTNET_BUNDLE_EXTRACT_BASE_DIR"

              slskd --no-connect --no-share-scan --no-logo > "$TMPDIR/slskd.log" 2>&1 &
              slskd_pid=$!
              trap 'kill "$slskd_pid" 2>/dev/null || true; wait "$slskd_pid" 2>/dev/null || true' EXIT

              for _ in $(seq 1 80); do
                if curl --fail --silent "http://127.0.0.1:$SLSKD_HTTP_PORT/" > /dev/null; then
                  break
                fi
                if ! kill -0 "$slskd_pid" 2>/dev/null; then
                  cat "$TMPDIR/slskd.log" >&2
                  exit 1
                fi
                sleep 0.25
              done

              bad_status="$TMPDIR/bad-status"
              curl --silent \
                --output /dev/null \
                --write-out '%{http_code}' \
                --request POST \
                --header 'Content-Type: application/json' \
                --data '{"username":"slskd","password":"wrong"}' \
                "http://127.0.0.1:$SLSKD_HTTP_PORT/api/v0/session" > "$bad_status"
              test "$(cat "$bad_status")" = 401

              session="$TMPDIR/session.json"
              curl --fail --silent \
                --request POST \
                --header 'Content-Type: application/json' \
                --data '{"username":"slskd","password":"slskd"}' \
                "http://127.0.0.1:$SLSKD_HTTP_PORT/api/v0/session" > "$session"
              jq --exit-status '.token | type == "string" and length > 0' "$session" > /dev/null
              token="$(jq --raw-output '.token' "$session")"

              curl --fail --silent \
                --header "Authorization: Bearer $token" \
                "http://127.0.0.1:$SLSKD_HTTP_PORT/api/v0/application/version" \
                | jq --exit-status 'startswith("0.26.0")' > /dev/null
              curl --fail --silent \
                --header "Authorization: Bearer $token" \
                "http://127.0.0.1:$SLSKD_HTTP_PORT/api/v0/application" \
                | jq --exit-status '.server.isConnected == false and .server.isLoggedIn == false' > /dev/null

              test -f "$SLSKD_APP_DIR/slskd.yml"
              test "$(stat --format '%a' "$SLSKD_APP_DIR/slskd.yml")" = 600
              test -d "$SLSKD_APP_DIR/downloads"
              test -d "$SLSKD_APP_DIR/incomplete"
              touch "$out"
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

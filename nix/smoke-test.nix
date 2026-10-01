{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      musicgrabber = self'.packages.musicgrabber;
      smokeTest = pkgs.writeShellApplication {
        name = "musicgrabber-smoke-test";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.ffmpeg-headless
          pkgs.gnugrep
          pkgs.jq
        ];
        text = ''
          if [[ -n "''${MUSICGRABBER_SMOKE_PORT:-}" ]]; then
            port="$MUSICGRABBER_SMOKE_PORT"
            ${musicgrabber.pythonEnv}/bin/python - "$port" <<'PY'
          import socket
          import sys

          with socket.socket() as listener:
              try:
                  listener.bind(("127.0.0.1", int(sys.argv[1])))
              except OSError as error:
                  raise SystemExit(f"Smoke-test port {sys.argv[1]} is unavailable: {error}") from error
          PY
          else
            port="$(${musicgrabber.pythonEnv}/bin/python - <<'PY'
          import socket

          with socket.socket() as listener:
              listener.bind(("127.0.0.1", 0))
              print(listener.getsockname()[1])
          PY
          )"
          fi

          test_root="$(mktemp -d "''${TMPDIR:-/tmp}/musicgrabber-smoke.XXXXXX")"
          server_pid=""

          cleanup() {
            if [[ -n "$server_pid" ]]; then
              kill "$server_pid" 2>/dev/null || true
              wait "$server_pid" 2>/dev/null || true
            fi
            if [[ "''${MUSICGRABBER_SMOKE_KEEP:-0}" != "1" ]]; then
              rm -rf "$test_root"
            else
              printf 'Smoke-test state retained at %s\n' "$test_root"
            fi
          }
          trap cleanup EXIT

          MUSICGRABBER_STATE_DIR="$test_root/state" \
          MUSIC_DIR="$test_root/music" \
          LISTEN_ADDR=127.0.0.1 \
          LISTEN_PORT="$port" \
            ${musicgrabber}/bin/musicgrabber >"$test_root/server.log" 2>&1 &
          server_pid=$!

          ready=0
          for _ in $(seq 1 60); do
            if ! kill -0 "$server_pid" 2>/dev/null; then
              printf 'MusicGrabber exited during startup.\n' >&2
              cat "$test_root/server.log" >&2
              exit 1
            fi
            if curl --fail --silent "http://127.0.0.1:$port/api/config" >"$test_root/config.json" 2>/dev/null; then
              sleep 1
              if ! kill -0 "$server_pid" 2>/dev/null; then
                printf 'Another process answered on port %s while MusicGrabber exited.\n' "$port" >&2
                cat "$test_root/server.log" >&2
                exit 1
              fi
              ready=1
              break
            fi
            sleep 1
          done

          if [[ "$ready" != "1" ]]; then
            printf 'MusicGrabber did not become ready on port %s.\n' "$port" >&2
            cat "$test_root/server.log" >&2
            exit 1
          fi

          jq --exit-status '.volume_mounted == true' "$test_root/config.json" >/dev/null
          curl --fail --silent --show-error \
            "http://127.0.0.1:$port/" \
            >"$test_root/home.html"
          grep -q "Music Grabber" "$test_root/home.html"
          printf 'Startup smoke test passed.\n'

          if [[ "''${MUSICGRABBER_SMOKE_NETWORK:-0}" != "1" ]]; then
            printf 'Set MUSICGRABBER_SMOKE_NETWORK=1 to test Spotify extraction and a real QA download.\n'
            exit 0
          fi

          curl --fail --silent --show-error \
            -H 'Content-Type: application/json' \
            -d '{"url":"https://open.spotify.com/playlist/3DHp7YE5h3l3PTz0rjeYFQ"}' \
            "http://127.0.0.1:$port/api/fetch-playlist" \
            >"$test_root/spotify.json"
          jq --exit-status '.count >= 1' "$test_root/spotify.json" >/dev/null

          curl --fail --silent --show-error \
            -H 'Content-Type: application/json' \
            -d '{"video_id":"jNQXAC9IVRw","title":"Me at the zoo","artist":"jawed","source":"youtube","convert_to_flac":true}' \
            "http://127.0.0.1:$port/api/download" \
            >"$test_root/download.json"
          job_id="$(jq --raw-output '.job_id' "$test_root/download.json")"

          status="queued"
          for _ in $(seq 1 60); do
            curl --fail --silent --show-error \
              "http://127.0.0.1:$port/api/jobs/$job_id" \
              >"$test_root/job.json"
            status="$(jq --raw-output '.status' "$test_root/job.json")"
            case "$status" in
              completed|completed_with_errors|failed) break ;;
            esac
            sleep 3
          done

          if [[ "$status" != "completed" && "$status" != "completed_with_errors" ]]; then
            jq . "$test_root/job.json"
            exit 1
          fi

          final_path="$(jq --raw-output '.final_path' "$test_root/job.json")"
          test -f "$final_path"
          ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 "$final_path" >/dev/null
          printf 'Network smoke test passed: Spotify extraction and QA download completed.\n'
        '';
      };
    in
    {
      packages.smoke-test = smokeTest;
      apps.smoke-test = {
        type = "app";
        program = "${smokeTest}/bin/musicgrabber-smoke-test";
        meta.description = "Run isolated MusicGrabber smoke tests";
      };
    };
}

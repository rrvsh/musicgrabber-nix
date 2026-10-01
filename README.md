# musicgrabber-nix

Standalone Nix package for [MusicGrabber](https://gitlab.com/g33kphr33k/musicgrabber), pinned to v4.2.3.

## Run

```console
nix run
```

The web interface listens on `http://127.0.0.1:8080` by default. Do not change `LISTEN_ADDR` to a public interface unless you have configured MusicGrabber authentication and appropriate network controls.

Runtime state defaults to:

- Any platform with `XDG_DATA_HOME` set: `$XDG_DATA_HOME/musicgrabber`
- macOS otherwise: `~/Library/Application Support/MusicGrabber`
- Linux otherwise: `~/.local/share/musicgrabber`
- Music: `~/Music/MusicGrabber`

Override these with `MUSICGRABBER_STATE_DIR`, `DB_PATH`, `COOKIES_FILE`, `MUSIC_DIR`, `LISTEN_ADDR`, or `LISTEN_PORT`.

The wrapper uses a restrictive umask for newly created state, cookies, and downloads. MusicGrabber and Mixxx can still read them when both run as the same user.

## Package boundary

The portable package includes:

- Python 3.12 dependencies locked with uv
- Chromium and Chromium headless shell for Playwright
- SeleniumBase with an exact Chromium and ChromeDriver pair
- Xvfb and Xauth on Linux
- FFmpeg and ffprobe
- Chromaprint's `fpcalc`
- yt-dlp and Deno

SeleniumBase supports Monochrome browser-authenticated playback fallback, MP3Phoenix browser clearance, and Amazon album extraction. Monochrome browser fallback is enabled by default. MP3Phoenix remains disabled by default because upstream treats it as experimental; enable it through MusicGrabber's source settings or `SOURCE_MP3PHOENIX_ENABLED=true`.

The package does not download a browser or driver at runtime. SeleniumBase creates its required patched `uc_driver` under `~/Library/Caches/MusicGrabber` on macOS or `${XDG_CACHE_HOME:-$HOME/.cache}/musicgrabber` on Linux. Override this with `MUSICGRABBER_SELENIUM_CACHE_DIR`.

SeleniumBase UC mode is intentionally headed. Linux runs it inside Xvfb. On macOS, MusicGrabber must run from an interactive graphical login session so Chrome can access WindowServer.

## Checks

```console
nix flake check
nix build
```

The flake checks the complete package, Python imports, application startup, native-package patch behavior, browser/driver version coordination, and SeleniumBase UC/CDP launch behavior on both Linux architectures. Darwin checks imports and exact browser/driver versions; a full Darwin UC launch requires an interactive WindowServer session and is validated manually.

Outputs and checks support `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.

## Smoke tests

Run an isolated startup test:

```console
nix run .#smoke-test
```

Opt into networked Spotify extraction and a real, short QA download:

```console
MUSICGRABBER_SMOKE_NETWORK=1 nix run .#smoke-test
```

The networked test uses MusicGrabber's own three-track Spotify QA playlist and the short `Me at the zoo` YouTube fixture. Temporary state is removed by default. Set `MUSICGRABBER_SMOKE_KEEP=1` to retain it for debugging.

## Packaging design

The flake uses flake-parts, import-tree, and small modules under `nix/`. It has one Nixpkgs input. The current Playwright browser component derivations are overridden with the coordinated Chromium revision 1208 sources required by the locked Python Playwright 1.58 wheel. Current Nixpkgs still provides the browser runtime libraries and FFmpeg revision 1011.

Playwright remains pinned to its revision-1208 Chromium 145 assets. SeleniumBase uses current Nixpkgs' separate Chromium 153.0.8010.12 bundle with the exact matching ChromeDriver on every supported architecture. These cannot be combined because no matching Chromium 145 Linux ARM64 ChromeDriver is published.

The package version comes from `pyproject.toml`. The application source is pinned independently by commit and content hash. A small patch makes the cookies path configurable and disables a Docker-specific volume warning for the native wrapper.

See [`docs/UPDATING.md`](docs/UPDATING.md) for the update workflow.

## License

MusicGrabber and this packaging repository use the Unlicense. See [`LICENSE`](LICENSE).

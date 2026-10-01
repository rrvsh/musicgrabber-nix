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

## Soulseek through slskd

The flake includes [slskd](https://github.com/slskd/slskd) as an optional companion package:

```console
nix run .#slskd
```

slskd remains separate from the default MusicGrabber package. It is not started automatically, and the flake does not install a NixOS, Home Manager, or nix-darwin service.

The wrapper uses local-first defaults:

- HTTP listens on `127.0.0.1:5030`.
- HTTPS is disabled.
- Remote configuration and remote file management are disabled.
- Automatic version checks are disabled because Nix owns the version.
- New state and downloaded files use a restrictive umask.

The YAML configuration and command-line arguments take precedence over these defaults. Do not configure the web interface to listen on a public address.

### Initial setup

Initialize the private application directory without connecting to Soulseek:

```console
nix run .#slskd -- \
  --no-start \
  --no-connect \
  --no-share-scan
```

On macOS this creates `~/Library/Application Support/slskd/`. Restrict the generated configuration before editing it:

```console
chmod 600 "$HOME/Library/Application Support/slskd/slskd.yml"
```

Configure separate credentials for the local web API and the Soulseek network in `slskd.yml`:

```yaml
headless: false
remote_configuration: false
remote_file_management: false

shares:
  directories: []

web:
  port: 5030
  ip_address: 127.0.0.1
  https:
    disabled: true
  authentication:
    disabled: false
    username: REPLACE_WITH_LOCAL_API_USERNAME
    password: REPLACE_WITH_A_STRONG_LOCAL_API_PASSWORD

soulseek:
  username: REPLACE_WITH_SOULSEEK_USERNAME
  password: REPLACE_WITH_SOULSEEK_PASSWORD
  listen_ip_address: 0.0.0.0
  listen_port: 50300
```

Do not commit this file. It contains both sets of credentials. `web.authentication` controls the local slskd web/API; `soulseek` authenticates with the Soulseek network. MusicGrabber uses the web/API credentials.

The default completed-download directory on macOS is `~/Library/Application Support/slskd/downloads`. Keep it separate from the MusicGrabber and Mixxx library. MusicGrabber copies accepted files from it into its own staging and library paths.

### MusicGrabber settings

Start slskd:

```console
nix run .#slskd
```

Then configure **Settings → Soulseek (slskd)** in MusicGrabber:

| Setting | Value |
| --- | --- |
| URL | `http://127.0.0.1:5030` |
| Username | The `web.authentication.username` value |
| Password | The `web.authentication.password` value |
| Downloads Path | The absolute slskd completed-download path |
| Move completed downloads | Off |

On macOS, the downloads path normally expands to `/Users/YOUR_USERNAME/Library/Application Support/slskd/downloads`.

Run **Test Connection** and require `Connected to slskd and downloads path is accessible`, then enable Soulseek under **Search Sources**.

For the first live test:

1. Leave slskd shares empty and leave **Move completed downloads** off.
2. Confirm slskd reports that it is logged into Soulseek.
3. Search for one small recording you are authorized to obtain.
4. Inspect the peer, filename, size, format, and match confidence.
5. Queue exactly one result.
6. Confirm the file appears under slskd's completed directory and is copied into MusicGrabber's library.
7. Check the resulting audio, tags, artwork, and Mixxx visibility.

The slskd web ports, `5030` and `5031`, must not be exposed publicly. The separate Soulseek peer port, `50300`, may later need router forwarding to improve peer connectivity.

## Package boundary

The default MusicGrabber package includes:

- Python 3.12 dependencies locked with uv
- Chromium and Chromium headless shell for Playwright
- FFmpeg and ffprobe
- Chromaprint's `fpcalc`
- yt-dlp and Deno

The flake also exposes slskd 0.26.0 as the optional `slskd` package and app. It remains a separate process and is not included in MusicGrabber's runtime closure.

SeleniumBase is currently excluded. The following features are therefore unavailable or reduced:

- Monochrome browser-authenticated fallback
- MP3Phoenix browser clearance
- Amazon album extraction

> **TODO:** Restore SeleniumBase support as soon as possible. Its current exclusion is temporary technical debt, not the intended final package boundary. A complete implementation must package and validate the coordinated browser, driver, display, Xauth, and Tk/PyAutoGUI runtime on every supported platform without runtime downloads.

Spotify playlist extraction uses Playwright and is supported. Monochrome's direct qbdlx route remains available without its browser fallback.

## Checks

```console
nix flake check
nix build
```

The flake checks the complete package, Python imports, application startup, and native-package patch behavior. Behavioral smoke tests cover runtime tools and browser-backed workflows without duplicating them as standalone flake checks.

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

The package version comes from `pyproject.toml`. The application source is pinned independently by commit and content hash. A small patch makes the cookies path configurable and disables a Docker-specific volume warning for the native wrapper.

See [`docs/UPDATING.md`](docs/UPDATING.md) for the update workflow.

## License

MusicGrabber and this packaging repository use the Unlicense. See [`LICENSE`](LICENSE).

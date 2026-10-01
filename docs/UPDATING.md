# Updating MusicGrabber

The source, Python environment, runtime tools, and Playwright browsers have separate update boundaries.

## Update upstream MusicGrabber

1. Find the new upstream tag and commit.
2. Update the `fetchFromGitLab.rev` commit in `nix/package.nix`.
3. Update the project version and dependency constraints in `pyproject.toml` from upstream's Dockerfile. Nix reads the package version from this file.
4. Enter the development shell and refresh the lock:

   ```console
   nix develop -c uv lock
   ```

5. Replace the source hash with `nixpkgs.lib.fakeHash`, run `nix build`, and copy the reported correct hash into `nix/package.nix`.
6. Refresh `patches/native-package.patch` if it no longer applies.

## Update runtime packages

Update the normal Nixpkgs input without changing the Playwright browser pin:

```console
nix flake update nixpkgs
```

This updates Deno, FFmpeg, Chromaprint, Python, and other Nix runtime dependencies. yt-dlp is pinned separately in `pyproject.toml`; update that version deliberately, then run `nix develop -c uv lock`.

## Update Playwright

Only update Playwright as a coordinated set:

1. Update the Playwright constraint in `pyproject.toml` and run `nix develop -c uv lock`.
2. Find the Chromium revision, browser URLs, hashes, and expected bundle directory names for that Playwright release.
3. Update `playwrightSources`, the link-farm revision names, and any platform-specific install or post-fixup paths in `nix/package.nix`.
4. Confirm that the current Nixpkgs Playwright FFmpeg revision still matches the linked revision. If it does not, add the corresponding source override rather than adding another Nixpkgs input.
5. Run `nix flake lock` and launch the packaged browser through the locked Python Playwright wheel on every supported system.

Do not update only the Python wheel or only the browser assets. Keep one Nixpkgs input and override its browser component derivations with `overrideAttrs` when the locked Python wheel requires older browser assets.

## Validate

Run:

```console
nix fmt -- .
nix flake check
nix build
nix run .#smoke-test
MUSICGRABBER_SMOKE_NETWORK=1 nix run .#smoke-test
nix path-info -Sh ./result
```

Then use a browser to verify the home page, a public Spotify playlist fetch, Queue status, and generated output.

Build on each supported system before claiming native support there:

- `aarch64-darwin`
- `x86_64-linux`
- `aarch64-linux`

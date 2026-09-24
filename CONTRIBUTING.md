# Contributing

Thanks for helping improve Claude Code Token Star.

## Before you start

- Search the existing issues before opening a new one.
- Keep changes focused on one problem or feature.
- Never include API keys, Claude transcripts, or local settings in a report.

## Development setup

You need Node.js 18+ for shader and CLI checks. Python 3.10+ is required for
the Ghostty bridge. Windows integration tests use Windows PowerShell.

```sh
npm ci
npm test
python -m unittest discover -s tests -v
```

On Windows, also run:

```powershell
npm run test:windows
npm run test:hlsl
```

## Visual checks

Exercise all six stages without spending tokens:

```powershell
.\tools\token-test.ps1 sweep
```

For Ghostty:

```sh
./src/ghostty/token-test.sh sweep
```

If a visual changes, include a before/after screenshot or short recording in
the pull request. Keep generated media compressed and place it in `assets/`.

## Releases

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which tests the
package, publishes it to npm with provenance, and then creates the GitHub
release with the same tarball attached. Before tagging:

1. Run `npm version X.Y.Z --no-git-tag-version` and write the same version to
   `VERSION` (`npm test` fails when `VERSION` and `package.json` differ, and
   the workflow rejects a tag that does not match `package.json`).
2. Move the `Unreleased` changelog entries under the new version.
3. Make sure the repository has an `NPM_TOKEN` Actions secret with publish
   rights for `claude-token-star`.

Re-running a failed release skips an npm version that is already published.

## Pull requests

Explain what changed, why it changed, which platforms you tested, and any
known limitations. By submitting a contribution, you agree that it is
licensed under the project's MIT license.

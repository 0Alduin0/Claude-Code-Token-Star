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
.\token-test.ps1 sweep
```

For Ghostty:

```sh
./token-test.sh sweep
```

If a visual changes, include a before/after screenshot or short recording in
the pull request. Keep generated media compressed and place it in `assets/`.

## Pull requests

Explain what changed, why it changed, which platforms you tested, and any
known limitations. By submitting a contribution, you agree that it is
licensed under the project's MIT license.

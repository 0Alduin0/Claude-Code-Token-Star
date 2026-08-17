# Changelog

All notable changes to this project are documented here.

## Unreleased

- Isolated Windows settings, runtimes, overlay processes, and Terminal profiles
  per project so installing or uninstalling one project cannot affect another.
- Added `python` fallback discovery for `doctor`, `sweep`, and `off` when
  `python3` is unavailable on Linux or macOS.
- Made the Windows overlay format token counts at or above one million with an
  `M` suffix, consistently with the other status surfaces.

## 2.6.1 - 2026-08-12

- Replaced the stage-slideshow GIF with a 60-frame recording of the real
  animated quasar overlay.
- Moved all six stellar-stage screenshots to the top of the README so every
  visual state is immediately visible.

## 2.6.0 - 2026-08-12

- Added a project-scoped Windows overlay for JetBrains IDEs, VS Code, Cursor,
  Visual Studio, and Eclipse.
- Added six context-driven stellar stages, token details, star scaling,
  position locking, and project-aware visibility.
- Added an optional Windows Terminal shader profile and the existing Ghostty
  shader integration for Linux and macOS.
- Added a cross-platform `npx` installer entry point and npm package metadata.
- Added an animated product preview, social preview artwork, contribution
  guidelines, and automated tagged releases.
- Expanded automated checks for Python, GLSL, HLSL, Windows integration, and
  the command-line package contract.

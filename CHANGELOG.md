# Changelog

All notable changes to this project are documented here.

## Unreleased

- Restored the smoother visible-overlay animation cadence while retaining the
  active-stage render-tree, caching, allocation, and hidden-refresh savings.
- Reworked the Windows control layout so the compact bar and details card stay
  centered directly below the star with stage-aware spacing at every star
  scale and token-driven growth level.
- Replaced native whole-window dragging with star-centered dragging, allowing
  the star to reach IDE corners even though the transparent control canvas is
  larger than the visible stellar graphic.
- Replaced corrupted/special model separators and all-uppercase effort text
  with readable Segoe UI labels such as `Opus 5 / Extra high`.
- Added per-session state tracking so multiple Claude tabs display the active
  tab with the highest context-token usage instead of whichever tab wrote last.
- Added persistent `on` and `off` commands for enabling, starting, stopping,
  and disabling the Windows overlay.
- Reduced animation object counts, removed dynamic blur effects, consolidated
  timers, slowed hidden refreshes, and trimmed the warmed-up working set.
- Collapsed inactive stellar stages out of the WPF render tree, resized the
  transparent surface to its visible content, cached stage resources, reduced
  per-frame allocations, and skipped inactive-stage animation calculations.
- Organized platform sources under `src/`, developer utilities under `tools/`,
  and Windows command wrappers under `scripts/windows/`.
- Added persistent automatic/fixed stellar-stage selection, including the
  option to keep a single stage such as Quasar visible for the whole session.
- Added an optional token-driven growth toggle for scaling the selected star
  as context usage rises.
- Added active Claude model and effort metadata plus used/available context
  counts to the overlay and cross-platform status-line output.
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

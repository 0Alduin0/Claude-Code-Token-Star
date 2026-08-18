# Claude Code Token Star

[![Tests](https://github.com/0Alduin0/Claude-Code-Token-Star/actions/workflows/test.yml/badge.svg)](https://github.com/0Alduin0/Claude-Code-Token-Star/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/0Alduin0/Claude-Code-Token-Star)](https://github.com/0Alduin0/Claude-Code-Token-Star/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Live star overlay that visualizes Claude Code context usage — six stellar
stages from red dwarf to quasar.

Claude Code sends its status-line data to a small local bridge. The bridge
updates the star without making extra API calls or using extra tokens. The
installation is scoped to the project where you run it.

### Quasar in motion

<p align="center">
  <img src="assets/quasar-in-motion.gif" width="500" alt="Animated quasar with a rotating accretion disk and pulsing relativistic jets">
</p>

## Star stages

| | |
| --- | --- |
| **Red Dwarf · 0–15%**<br><img src="assets/overlay-red-dwarf.png" width="420" alt="Red Dwarf"> | **Main Sequence · 15–35%**<br><img src="assets/overlay-main-sequence.png" width="420" alt="Main Sequence"> |
| **Blue Giant · 35–55%**<br><img src="assets/overlay-blue-giant.png" width="420" alt="Blue Giant"> | **Hypergiant · 55–75%**<br><img src="assets/overlay-hypergiant.png" width="420" alt="Hypergiant"> |
| **Neutron Star · 75–90%**<br><img src="assets/overlay-neutron-star.png" width="420" alt="Neutron Star"> | **Quasar · 90–100%**<br><img src="assets/overlay-quasar.png" width="420" alt="Quasar"> |


## Platform support

| Platform | Display | Status |
| --- | --- | --- |
| Windows | Transparent overlay for JetBrains IDEs, VS Code, Cursor, Visual Studio, and Eclipse; optional Windows Terminal shader | Fully supported |
| macOS | Ghostty shader | **Ghostty only** |
| Linux | Ghostty shader | **Ghostty only** |

macOS and Linux do not currently have native overlays for Terminal, iTerm2,
VS Code, or other terminals and editors.

## Quick install

You need Claude Code, Git, and Node.js 18+. Run this from your project root:

```sh
npx --yes github:0Alduin0/Claude-Code-Token-Star
```

On Windows, the installer uses `ExecutionPolicy Bypass` only for the child
PowerShell process because the local scripts are not code-signed. It does not
change your user or system execution policy. The source is copied into
`.claude-token-star/` so it remains inspectable. Each project gets its own
`.claude/settings.local.json`, overlay process, and hashed runtime directory.

Windows does not require Python. Linux and macOS require Ghostty 1.3+ and
Python 3.10+.

Update by running the same command again. Remove it with:

```sh
npx --yes github:0Alduin0/Claude-Code-Token-Star uninstall
```

The npm package is also ready for publication. After its first registry
release, the shorter command will be `npx claude-token-star`.

<details>
<summary>Manual installation</summary>

### Windows

```powershell
git clone https://github.com/0Alduin0/Claude-Code-Token-Star.git .claude-token-star
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.claude-token-star\src\windows\install.ps1
```

### Linux and macOS

```sh
git clone https://github.com/0Alduin0/Claude-Code-Token-Star.git .claude-token-star
sh ./.claude-token-star/src/ghostty/install.sh
```

</details>

## Use it

- Drag the star to move it near an IDE corner or edge.
- The controls automatically flip to the open side of the star near window
  edges, so the menu never covers the stellar visual.
- `MASS 656K / 1.00M` shows used tokens beside the model's context capacity.
- `5H 61% | 2h 23m` shows five-hour usage and the time until reset.
- The compact bar shows the active Claude model and a readable effort label.
- Click the arrow for model, effort, input, cache-read, remaining-context,
  five-hour, reset, and seven-day details.
- Choose **Auto** to evolve through every stellar stage, or pin one stage such
  as **Quasar** so its appearance stays fixed.
- Enable **Grow with token usage** when the selected star should scale from
  65% to 100% as the context fills.
- Choose `1x`, `2x`, or `3x` to resize the star.
- Enable **Lock position** to prevent accidental dragging.
- If several Claude tabs are open in the project, the overlay shows the active
  session with the highest context-token usage. The details card also shows
  the number of active sessions.
- The Windows overlay hides when you switch away from its installed project.

<img src="assets/overlay-token-details.png" width="500" alt="Token details and star size menu">

Test every stage without spending tokens:

```powershell
.\.claude-token-star\token-test.ps1 sweep
```

On Linux or macOS:

```sh
./.claude-token-star/token-test.sh sweep
```

### Turn the Windows overlay off or on

The setting persists across Claude sessions. Run either command from the
project where Token Star is installed:

```powershell
npx --yes github:0Alduin0/Claude-Code-Token-Star off
npx --yes github:0Alduin0/Claude-Code-Token-Star on
```

`off` closes the current overlay process and prevents status refreshes from
starting it again. `on` re-enables it; the star appears on the next Claude
status refresh.

## Browser preview

On Windows:

```powershell
.\.claude-token-star\preview.ps1
```

This opens <http://127.0.0.1:4173/preview.html>. Press Enter in the terminal to
stop it.

## Troubleshooting

```powershell
.\.claude-token-star\token-test.ps1 doctor
```

The Windows overlay appears only while the installed project is open in a
supported IDE. Seeing `--` before Claude Code sends its first status update is
normal. An enabled overlay process is restarted automatically by the next
status refresh if it exits unexpectedly.

For installation problems, include your OS, terminal/editor, Claude Code
version, and doctor output in a GitHub issue. Do not include tokens, settings,
or conversation contents.

## Resource use

The bridge reads data Claude Code already sends to the status line. It makes no
extra API requests and consumes no additional model tokens. The overlay uses a
single low-frequency WPF animation timer; hidden overlays refresh once per
second.

On the 16-logical-core Windows test machine, a 10-second warmed-up Quasar run
averaged **65.5 MB resident RAM** and **0.09% total CPU**. WPF initialization
briefly reached **260.9 MB resident RAM**; private committed memory averaged
234.4 MB. Results vary by Windows, DPI, GPU driver, and selected stellar stage.

## Repository layout

- `src/windows/` contains the Windows installer, bridge, WPF overlay, and HLSL.
- `src/ghostty/` contains the macOS/Linux bridge, scripts, and GLSL.
- `tools/` contains preview and visual-test utilities.
- `scripts/windows/` contains optional `.cmd` wrappers.
- `tests/` and `assets/` contain automated checks and documentation media.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for setup, tests, and visual-change guidelines.

## License

MIT. Visual references: [NASA Star Lifecycle](https://science.nasa.gov/mission/webb/star-lifecycle/)
and [NASA Active Galactic Nuclei](https://science.nasa.gov/mission/webb/science-overview/science-explainers/what-are-active-galactic-nuclei/).

#!/usr/bin/env python3
"""Claude Code -> Ghostty Supernova bridge.

Reads Claude Code status-line/hook JSON from stdin, encodes context fill and
absolute context tokens into two OSC 12 cursor-color packets, then prints a
small status line. All operations are best-effort: a missing terminal or an
unexpected payload must never break Claude's status line.

The cursor-channel transport and ancestor-TTY fallback are adapted from
s0xDk/ghostty-blackhole (MIT). See THIRD_PARTY_NOTICES.md.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

LEVEL_BASE = (0xF0, 0xB0, 0x00)
MASS_BASE = (0xE0, 0xA0, 0x10)
CONFIG_BEGIN = "# >>> ghostty-supernova >>>"
CONFIG_END = "# <<< ghostty-supernova <<<"
INSTALL_STATE = "ghostty-supernova.install.json"
RESET_PACKET = b"\033]112\007"


def finite_number(value: object) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
    )


def session_tty() -> str | None:
    """Find the terminal owned by the nearest ancestor process."""
    if os.name == "nt":
        return None
    pid = os.getppid()
    for _ in range(10):
        try:
            result = subprocess.run(
                ["ps", "-o", "ppid=,tty=", "-p", str(pid)],
                capture_output=True,
                text=True,
                timeout=1,
                check=False,
            ).stdout.split()
        except (OSError, subprocess.SubprocessError):
            return None
        if len(result) < 2:
            return None
        if result[1] != "??":
            return "/dev/" + result[1]
        if not result[0].isdigit() or int(result[0]) <= 1:
            return None
        pid = int(result[0])
    return None


def emit(payload: bytes) -> None:
    if os.name == "nt":
        try:
            with open("CONOUT$", "wb", buffering=0) as console:
                console.write(payload)
        except OSError:
            pass
        return

    try:
        with open("/dev/tty", "wb") as tty:
            tty.write(payload)
        return
    except OSError:
        pass

    path = session_tty()
    if path:
        try:
            with open(path, "wb") as tty:
                tty.write(payload)
        except OSError:
            pass


def context_stats(data: dict) -> tuple[float, int]:
    window = data.get("context_window") if isinstance(data, dict) else {}
    if not isinstance(window, dict):
        window = {}
    used = window.get("total_input_tokens")
    size = window.get("context_window_size")
    percentage = window.get("used_percentage")

    has_used = finite_number(used)
    if not has_used:
        current = window.get("current_usage")
        if isinstance(current, dict):
            components = (
                current.get("input_tokens"),
                current.get("cache_creation_input_tokens"),
                current.get("cache_read_input_tokens"),
            )
            numeric = [value for value in components if finite_number(value)]
            if numeric:
                used = sum(numeric)
                has_used = True
    used = int(used) if has_used else 0
    size = max(0, int(size)) if finite_number(size) else 0
    if finite_number(percentage):
        level = float(percentage) / 100.0
    elif size:
        level = used / size
    else:
        level = 0.0

    if not has_used and size:
        used = round(size * level)

    return max(0.0, min(1.0, level)), max(0, used)


def level_packet(level: float) -> bytes:
    fill = max(0, min(250, round(level * 250.0)))
    high, low = fill >> 4, fill & 0xF
    rgb = (
        LEVEL_BASE[0] | (high ^ low ^ 0x5),
        LEVEL_BASE[1] | high,
        LEVEL_BASE[2] | low,
    )
    return b"\033]12;#%02x%02x%02x\007" % rgb


def mass_packet(used_tokens: int) -> bytes:
    mass_k = max(0, min(4095, round(used_tokens / 1000.0)))
    rgb = (
        MASS_BASE[0] | ((mass_k >> 8) & 0xF),
        MASS_BASE[1] | ((mass_k >> 4) & 0xF),
        MASS_BASE[2] | (mass_k & 0xF),
    )
    return b"\033]12;#%02x%02x%02x\007" % rgb


def apply(level: float, used_tokens: int) -> None:
    # Two immediate updates make the mass packet available as Ghostty's
    # previous cursor color and leave the signed amber level packet current.
    emit(mass_packet(used_tokens) + level_packet(level))


def stage_name(level: float) -> str:
    stages = (
        (0.15, "RED DWARF"),
        (0.35, "MAIN SEQUENCE"),
        (0.55, "BLUE GIANT"),
        (0.75, "HYPERGIANT"),
        (0.90, "NEUTRON STAR"),
        (1.01, "QUASAR"),
    )
    return next(name for ceiling, name in stages if level < ceiling)


def compact_number(value: int) -> str:
    if value >= 1_000_000:
        return f"{value / 1_000_000:.2f}M"
    if value >= 1_000:
        return f"{value / 1_000:.1f}K"
    return str(value)


def status_line(data: dict, level: float, used_tokens: int) -> str:
    context_data = data.get("context_window") if isinstance(data, dict) else {}
    window_size = (
        context_data.get("context_window_size")
        if isinstance(context_data, dict)
        else None
    )
    mass_usage = compact_number(used_tokens)
    if finite_number(window_size) and float(window_size) > 0:
        mass_usage += f" / {compact_number(round(float(window_size)))}"
    parts = [
        f"* MASS {mass_usage} TOKENS",
        f"{level * 100:.0f}%",
        stage_name(level),
    ]
    model_data = data.get("model") if isinstance(data, dict) else {}
    model = (
        model_data.get("display_name") or model_data.get("id")
        if isinstance(model_data, dict)
        else None
    )
    if model:
        parts.append(str(model))
    effort_data = data.get("effort") if isinstance(data, dict) else {}
    effort = effort_data.get("level") if isinstance(effort_data, dict) else None
    if effort:
        parts.append(f"{str(effort).upper()} effort")
    return "\033[2m" + " · ".join(parts) + "\033[0m"


def default_config_paths() -> tuple[Path, Path]:
    """Return Claude and Ghostty config paths using their standard locations."""
    claude_root = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
    xdg_root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    ghostty_root = xdg_root / "ghostty"
    modern = ghostty_root / "config.ghostty"
    legacy = ghostty_root / "config"
    ghostty_config = modern if modern.exists() or not legacy.exists() else legacy

    if sys.platform == "darwin":
        mac_root = (
            Path.home() / "Library" / "Application Support" / "com.mitchellh.ghostty"
        )
        mac_modern = mac_root / "config.ghostty"
        mac_legacy = mac_root / "config"
        if mac_modern.exists() or mac_legacy.exists():
            ghostty_config = mac_modern if mac_modern.exists() else mac_legacy

    return claude_root / "settings.json", ghostty_config


def bridge_command(script: Path) -> str:
    if os.name == "nt":
        return subprocess.list2cmdline([sys.executable, str(script)])
    return shlex.quote(str(script))


def atomic_write_text(path: Path, text: str) -> None:
    """Replace a config file without exposing a partially written document."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".ghostty-supernova.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def read_json_object(path: Path, label: str) -> dict:
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise TypeError(f"{label} root must be a JSON object")
    return value


def state_path_for(claude_settings: Path) -> Path:
    return claude_settings.parent / INSTALL_STATE


def command_in_hook_group(group: object, command: str) -> bool:
    if not isinstance(group, dict):
        return False
    handlers = group.get("hooks", [])
    return isinstance(handlers, list) and any(
        isinstance(handler, dict) and handler.get("command") == command
        for handler in handlers
    )


def remove_hook_commands(settings: dict, commands: set[str]) -> None:
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return
    for event in ("SessionStart", "SessionEnd"):
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue
        kept_groups = []
        for group in groups:
            if not isinstance(group, dict):
                kept_groups.append(group)
                continue
            handlers = group.get("hooks")
            if not isinstance(handlers, list):
                kept_groups.append(group)
                continue
            kept_handlers = [
                handler
                for handler in handlers
                if not (
                    isinstance(handler, dict)
                    and isinstance(handler.get("command"), str)
                    and handler["command"] in commands
                )
            ]
            if kept_handlers:
                updated = dict(group)
                updated["hooks"] = kept_handlers
                kept_groups.append(updated)
        if kept_groups:
            hooks[event] = kept_groups
        else:
            hooks.pop(event, None)
    if not hooks:
        settings.pop("hooks", None)


def strip_ghostty_block(config: str) -> str:
    marked = re.compile(
        rf"(?:\r?\n)?{re.escape(CONFIG_BEGIN)}.*?{re.escape(CONFIG_END)}(?:\r?\n)?",
        re.DOTALL,
    )
    return marked.sub("\n", config).rstrip()


def install(claude_settings: Path, ghostty_config: Path) -> None:
    """Install idempotent Claude hooks and a reversible Ghostty config block."""
    script = Path(__file__).resolve()
    shader = script.with_name("supernova.glsl")
    if not shader.is_file():
        raise FileNotFoundError(f"Shader not found beside bridge: {shader}")

    settings = read_json_object(claude_settings, "Claude settings")
    state_path = state_path_for(claude_settings)
    state = read_json_object(state_path, "Install state")
    command = bridge_command(script)
    previous_command = state.get("command")
    commands_to_replace = {command}
    if isinstance(previous_command, str):
        commands_to_replace.add(previous_command)

    if not state:
        state = {
            "schema": 1,
            "had_status_line": "statusLine" in settings,
            "previous_status_line": settings.get("statusLine"),
        }
    state.update(
        {
            "command": command,
            "claude_settings": str(claude_settings.resolve()),
            "ghostty_config": str(ghostty_config.resolve()),
        }
    )

    remove_hook_commands(settings, commands_to_replace)
    settings["statusLine"] = {"type": "command", "command": command}
    hooks = settings.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise TypeError("Claude settings 'hooks' must be a JSON object")
    hook = {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
    for event in ("SessionStart", "SessionEnd"):
        event_hooks = hooks.setdefault(event, [])
        if not isinstance(event_hooks, list):
            raise TypeError(f"Claude settings hooks.{event} must be a JSON array")
        if not any(command_in_hook_group(group, command) for group in event_hooks):
            event_hooks.append(hook)

    atomic_write_text(
        claude_settings,
        json.dumps(settings, ensure_ascii=False, indent=2) + "\n",
    )
    atomic_write_text(
        state_path, json.dumps(state, ensure_ascii=False, indent=2) + "\n"
    )

    old_config = (
        ghostty_config.read_text(encoding="utf-8") if ghostty_config.exists() else ""
    )
    old_config = strip_ghostty_block(old_config)
    block = (
        f"{CONFIG_BEGIN}\n"
        f"custom-shader = {shader.as_posix()}\n"
        "custom-shader-animation = true\n"
        f"{CONFIG_END}\n"
    )
    atomic_write_text(
        ghostty_config, (old_config + "\n\n" if old_config else "") + block
    )

    if os.name != "nt":
        script.chmod(script.stat().st_mode | 0o111)


def uninstall(claude_settings: Path, ghostty_config: Path | None = None) -> None:
    """Remove only this project's settings and restore a replaced status line."""
    state_path = state_path_for(claude_settings)
    state = read_json_object(state_path, "Install state")
    settings = read_json_object(claude_settings, "Claude settings")

    current_command = bridge_command(Path(__file__).resolve())
    installed_command = state.get("command")
    commands = {current_command}
    if isinstance(installed_command, str):
        commands.add(installed_command)

    status_line = settings.get("statusLine")
    status_command = (
        status_line.get("command") if isinstance(status_line, dict) else None
    )
    if status_command in commands:
        if state.get("had_status_line"):
            settings["statusLine"] = state.get("previous_status_line")
        else:
            settings.pop("statusLine", None)

    remove_hook_commands(settings, commands)
    if claude_settings.exists():
        atomic_write_text(
            claude_settings,
            json.dumps(settings, ensure_ascii=False, indent=2) + "\n",
        )

    if ghostty_config is None:
        configured_path = state.get("ghostty_config")
        ghostty_config = (
            Path(configured_path) if isinstance(configured_path, str) else None
        )
    if ghostty_config and ghostty_config.exists():
        remaining = strip_ghostty_block(ghostty_config.read_text(encoding="utf-8"))
        atomic_write_text(ghostty_config, remaining + ("\n" if remaining else ""))

    if state_path.exists():
        state_path.unlink()
    emit(RESET_PACKET)


def install_main(argv: list[str]) -> None:
    default_claude, default_ghostty = default_config_paths()
    parser = argparse.ArgumentParser(
        description="Install Ghostty Supernova for Claude Code"
    )
    parser.add_argument("--claude-settings", type=Path, default=default_claude)
    parser.add_argument("--ghostty-config", type=Path, default=default_ghostty)
    args = parser.parse_args(argv)
    install(args.claude_settings.expanduser(), args.ghostty_config.expanduser())
    print(f"Claude Code: {args.claude_settings.expanduser()}")
    print(f"Ghostty:     {args.ghostty_config.expanduser()}")
    checks = doctor(args.claude_settings.expanduser(), args.ghostty_config.expanduser())
    failures = [message for status, message in checks if status == "FAIL"]
    if failures:
        raise RuntimeError("Installation verification failed: " + "; ".join(failures))
    for status, message in checks:
        if status == "WARN":
            print(f"Warning: {message}")
    print(
        "Installed. Reload Ghostty's configuration, then start a new Claude Code session."
    )


def uninstall_main(argv: list[str]) -> None:
    default_claude, default_ghostty = default_config_paths()
    parser = argparse.ArgumentParser(description="Uninstall Ghostty Supernova")
    parser.add_argument("--claude-settings", type=Path, default=default_claude)
    parser.add_argument("--ghostty-config", type=Path, default=None)
    args = parser.parse_args(argv)
    claude_settings = args.claude_settings.expanduser()
    ghostty_config = args.ghostty_config.expanduser() if args.ghostty_config else None
    uninstall(claude_settings, ghostty_config)
    print(f"Removed Ghostty Supernova from {claude_settings}")
    if ghostty_config or default_ghostty.exists():
        print(
            f"Removed its marked Ghostty block from {ghostty_config or default_ghostty}"
        )


def parse_level(value: str) -> float:
    text = value.strip()
    is_percent = text.endswith("%")
    if is_percent:
        text = text[:-1]
    number = float(text)
    if is_percent or number > 1.0:
        number /= 100.0
    if not 0.0 <= number <= 1.0:
        raise argparse.ArgumentTypeError("level must be 0..1 or 0%..100%")
    return number


def test_main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description="Send a manual token level to Ghostty")
    parser.add_argument(
        "level", type=parse_level, help="0..1, or a percentage such as 82%%"
    )
    parser.add_argument("--tokens", type=int, help="absolute input-token count")
    parser.add_argument("--window-size", type=int, default=200_000)
    args = parser.parse_args(argv)
    used_tokens = args.tokens
    if used_tokens is None:
        used_tokens = round(max(0, args.window_size) * args.level)
    apply(args.level, max(0, used_tokens))
    print(
        f"MASS {compact_number(max(0, used_tokens))} · {args.level * 100:.0f}% · {stage_name(args.level)}"
    )


def sweep_main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(
        description="Sweep Ghostty Supernova from 0% to 100%"
    )
    parser.add_argument("--seconds", type=float, default=25.0)
    parser.add_argument("--steps", type=int, default=101)
    parser.add_argument("--window-size", type=int, default=200_000)
    args = parser.parse_args(argv)
    if args.seconds <= 0 or args.steps < 2 or args.window_size < 0:
        parser.error("seconds must be positive, steps >= 2, and window-size >= 0")
    delay = args.seconds / (args.steps - 1)
    for index in range(args.steps):
        level = index / (args.steps - 1)
        apply(level, round(args.window_size * level))
        if index + 1 < args.steps:
            time.sleep(delay)
    print("Sweep complete at 100%. Run --off to restore the cursor color.")


def doctor(claude_settings: Path, ghostty_config: Path) -> list[tuple[str, str]]:
    """Return machine-readable health checks without modifying configuration."""
    script = Path(__file__).resolve()
    shader = script.with_name("supernova.glsl")
    command = bridge_command(script)
    checks: list[tuple[str, str]] = []

    checks.append(
        (
            "OK" if sys.version_info >= (3, 10) else "FAIL",
            f"Python {sys.version.split()[0]}",
        )
    )
    checks.append(("OK" if shader.is_file() else "FAIL", f"shader: {shader}"))
    claude_executable = shutil.which("claude")
    checks.append(
        (
            "OK" if claude_executable else "WARN",
            f"Claude Code: {claude_executable or 'not on PATH'}",
        )
    )
    ghostty_executable = shutil.which("ghostty")
    checks.append(
        (
            "OK" if ghostty_executable else "WARN",
            f"Ghostty CLI: {ghostty_executable or 'not on PATH'}",
        )
    )

    try:
        settings = read_json_object(claude_settings, "Claude settings")
    except (OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        checks.append(("FAIL", f"Claude settings: {error}"))
        settings = {}
    try:
        state = read_json_object(state_path_for(claude_settings), "Install state")
    except (OSError, TypeError, ValueError, json.JSONDecodeError):
        state = {}
    expected_commands = {command}
    state_command = state.get("command")
    if isinstance(state_command, str):
        expected_commands.add(state_command)
    status_line = settings.get("statusLine")
    status_ok = (
        isinstance(status_line, dict)
        and status_line.get("command") in expected_commands
    )
    checks.append(("OK" if status_ok else "FAIL", f"statusLine: {claude_settings}"))
    hooks = settings.get("hooks") if isinstance(settings.get("hooks"), dict) else {}
    for event in ("SessionStart", "SessionEnd"):
        groups = hooks.get(event, []) if isinstance(hooks, dict) else []
        installed = isinstance(groups, list) and any(
            any(
                command_in_hook_group(group, expected) for expected in expected_commands
            )
            for group in groups
        )
        checks.append(("OK" if installed else "FAIL", f"{event} hook"))

    try:
        config = ghostty_config.read_text(encoding="utf-8")
        config_ok = (
            CONFIG_BEGIN in config
            and CONFIG_END in config
            and shader.as_posix() in config
            and "custom-shader-animation = true" in config
        )
        checks.append(
            ("OK" if config_ok else "FAIL", f"Ghostty config: {ghostty_config}")
        )
    except OSError as error:
        checks.append(("FAIL", f"Ghostty config: {error}"))

    packet_ok = len(level_packet(0.82)) == 13 and len(mass_packet(164_000)) == 13
    checks.append(("OK" if packet_ok else "FAIL", "OSC 12 packet contract"))
    return checks


def doctor_main(argv: list[str]) -> None:
    default_claude, default_ghostty = default_config_paths()
    parser = argparse.ArgumentParser(
        description="Check a Ghostty Supernova installation"
    )
    parser.add_argument("--claude-settings", type=Path, default=default_claude)
    parser.add_argument("--ghostty-config", type=Path, default=default_ghostty)
    args = parser.parse_args(argv)
    checks = doctor(args.claude_settings.expanduser(), args.ghostty_config.expanduser())
    for status, message in checks:
        print(f"[{status}] {message}")
    if any(status == "FAIL" for status, _ in checks):
        raise SystemExit(1)


def cli(argv: list[str]) -> None:
    command = argv[0] if argv else ""
    handlers = {
        "--install": install_main,
        "--uninstall": uninstall_main,
        "--doctor": doctor_main,
        "--test": test_main,
        "--sweep": sweep_main,
    }
    if command in {"-h", "--help"}:
        print(
            "Ghostty Supernova - Claude Code context-token bridge\n\n"
            "Commands:\n"
            "  --install    Configure Claude Code and Ghostty\n"
            "  --uninstall  Restore the previous configuration\n"
            "  --doctor     Check the installation\n"
            "  --test       Send one manual context level\n"
            "  --sweep      Animate through all context levels\n"
            "  --off        Restore the terminal cursor color\n\n"
            "Run a command with --help for its options."
        )
        return
    if command == "--off":
        emit(RESET_PACKET)
        print("Cursor color restored; Ghostty Supernova is off for this surface.")
        return
    handler = handlers.get(command)
    if handler:
        handler(argv[1:])
        return
    options = ", ".join([*handlers, "--off"])
    raise SystemExit(f"Unknown command {command!r}. Available commands: {options}")


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}

    event = data.get("hook_event_name")
    if event == "SessionEnd":
        emit(RESET_PACKET)
        return

    if event == "SessionStart":
        apply(0.0, 0)
        return

    level, used_tokens = context_stats(data)
    apply(level, used_tokens)
    print(status_line(data, level, used_tokens))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        cli(sys.argv[1:])
    else:
        main()

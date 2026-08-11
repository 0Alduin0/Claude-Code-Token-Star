from __future__ import annotations

import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("token_mass", ROOT / "token-mass.py")
assert SPEC and SPEC.loader
token_mass = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(token_mass)


class ContextStatsTests(unittest.TestCase):
    def test_prefers_reported_percentage_and_keeps_absolute_tokens(self) -> None:
        data = {
            "context_window": {
                "used_percentage": 82,
                "total_input_tokens": 164_000,
                "context_window_size": 200_000,
            }
        }
        self.assertEqual(token_mass.context_stats(data), (0.82, 164_000))

    def test_derives_percentage_from_window_size(self) -> None:
        data = {
            "context_window": {
                "total_input_tokens": 50_000,
                "context_window_size": 200_000,
            }
        }
        self.assertEqual(token_mass.context_stats(data), (0.25, 50_000))

    def test_derives_tokens_when_only_percentage_and_size_are_present(self) -> None:
        data = {
            "context_window": {
                "used_percentage": 12.5,
                "context_window_size": 200_000,
            }
        }
        self.assertEqual(token_mass.context_stats(data), (0.125, 25_000))

    def test_clamps_invalid_ranges(self) -> None:
        high = {"context_window": {"used_percentage": 140, "total_input_tokens": -2}}
        low = {"context_window": {"used_percentage": -10}}
        self.assertEqual(token_mass.context_stats(high), (1.0, 0))
        self.assertEqual(token_mass.context_stats(low), (0.0, 0))

    def test_uses_input_and_cache_components_as_legacy_fallback(self) -> None:
        data = {
            "context_window": {
                "context_window_size": 200_000,
                "current_usage": {
                    "input_tokens": 8_000,
                    "output_tokens": 9_999,
                    "cache_creation_input_tokens": 5_000,
                    "cache_read_input_tokens": 2_000,
                },
            }
        }
        self.assertEqual(token_mass.context_stats(data), (0.075, 15_000))

    def test_non_object_and_non_finite_values_are_safe(self) -> None:
        self.assertEqual(token_mass.context_stats([]), (0.0, 0))
        data = {
            "context_window": {
                "used_percentage": float("nan"),
                "total_input_tokens": float("inf"),
                "context_window_size": 200_000,
            }
        }
        self.assertEqual(token_mass.context_stats(data), (0.0, 0))


class PacketTests(unittest.TestCase):
    def test_level_packet_is_exactly_thirteen_bytes(self) -> None:
        packet = token_mass.level_packet(0.82)
        self.assertEqual(packet, b"\x1b]12;#f4bc0d\x07")
        self.assertEqual(len(packet), 13)

    def test_mass_packet_is_exactly_thirteen_bytes(self) -> None:
        packet = token_mass.mass_packet(164_000)
        self.assertEqual(packet, b"\x1b]12;#e0aa14\x07")
        self.assertEqual(len(packet), 13)

    def test_packet_inputs_are_clamped(self) -> None:
        self.assertEqual(token_mass.level_packet(-1), token_mass.level_packet(0))
        self.assertEqual(token_mass.level_packet(2), token_mass.level_packet(1))
        self.assertEqual(token_mass.mass_packet(-1), token_mass.mass_packet(0))
        self.assertEqual(
            token_mass.mass_packet(9_000_000), token_mass.mass_packet(4_095_000)
        )

    def test_apply_emits_mass_then_level_in_one_write(self) -> None:
        with mock.patch.object(token_mass, "emit") as emit:
            token_mass.apply(0.82, 164_000)
        emit.assert_called_once_with(b"\x1b]12;#e0aa14\x07" + b"\x1b]12;#f4bc0d\x07")


class PresentationTests(unittest.TestCase):
    def test_stage_boundaries(self) -> None:
        expected = [
            (0.00, "RED DWARF"),
            (0.15, "MAIN SEQUENCE"),
            (0.35, "BLUE GIANT"),
            (0.55, "HYPERGIANT"),
            (0.75, "NEUTRON STAR"),
            (0.90, "QUASAR"),
            (1.00, "QUASAR"),
        ]
        for level, stage in expected:
            with self.subTest(level=level):
                self.assertEqual(token_mass.stage_name(level), stage)

    def test_status_line_contains_only_token_context_and_model_fields(self) -> None:
        data = {"model": {"display_name": "Demo Model"}, "tests": "passed", "diff": 42}
        line = token_mass.status_line(data, 0.99, 198_000)
        self.assertEqual(
            line,
            "\x1b[2m* MASS 198.0K TOKENS · 99% · QUASAR · Demo Model\x1b[0m",
        )
        self.assertNotIn("passed", line)
        self.assertNotIn("42", line)

    def test_compact_number(self) -> None:
        self.assertEqual(token_mass.compact_number(999), "999")
        self.assertEqual(token_mass.compact_number(1_000), "1.0K")
        self.assertEqual(token_mass.compact_number(1_250_000), "1.25M")


class TerminalTransportTests(unittest.TestCase):
    def test_windows_writes_to_conout(self) -> None:
        handle = mock.mock_open()
        with (
            mock.patch.object(token_mass.os, "name", "nt"),
            mock.patch("builtins.open", handle),
        ):
            token_mass.emit(b"packet")
        handle.assert_called_once_with("CONOUT$", "wb", buffering=0)
        handle().write.assert_called_once_with(b"packet")

    def test_unix_prefers_dev_tty(self) -> None:
        handle = mock.mock_open()
        with (
            mock.patch.object(token_mass.os, "name", "posix"),
            mock.patch("builtins.open", handle),
            mock.patch.object(token_mass, "session_tty") as session_tty,
        ):
            token_mass.emit(b"packet")
        handle.assert_called_once_with("/dev/tty", "wb")
        handle().write.assert_called_once_with(b"packet")
        session_tty.assert_not_called()

    def test_unix_falls_back_to_ancestor_tty(self) -> None:
        fallback = mock.MagicMock()
        fallback.__enter__.return_value = fallback
        fallback.__exit__.return_value = False
        with (
            mock.patch.object(token_mass.os, "name", "posix"),
            mock.patch("builtins.open", side_effect=[OSError, fallback]) as open_file,
            mock.patch.object(token_mass, "session_tty", return_value="/dev/pts/7"),
        ):
            token_mass.emit(b"packet")
        self.assertEqual(
            open_file.call_args_list,
            [mock.call("/dev/tty", "wb"), mock.call("/dev/pts/7", "wb")],
        )
        fallback.write.assert_called_once_with(b"packet")

    def test_session_tty_walks_ancestors(self) -> None:
        no_tty = mock.MagicMock(stdout="22 ??\n")
        found = mock.MagicMock(stdout="1 pts/4\n")
        with (
            mock.patch.object(token_mass.os, "name", "posix"),
            mock.patch.object(token_mass.os, "getppid", return_value=11),
            mock.patch.object(
                token_mass.subprocess, "run", side_effect=[no_tty, found]
            ) as run,
        ):
            self.assertEqual(token_mass.session_tty(), "/dev/pts/4")
        self.assertEqual(run.call_count, 2)


class InstallerTests(unittest.TestCase):
    def test_install_merges_settings_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings_path = root / ".claude" / "settings.json"
            ghostty_path = root / ".config" / "ghostty" / "config.ghostty"
            settings_path.parent.mkdir(parents=True)
            settings_path.write_text(
                json.dumps({"permissions": {"allow": ["Read"]}}), encoding="utf-8"
            )
            ghostty_path.parent.mkdir(parents=True)
            ghostty_path.write_text("font-size = 13\n", encoding="utf-8")

            token_mass.install(settings_path, ghostty_path)
            token_mass.install(settings_path, ghostty_path)

            settings = json.loads(settings_path.read_text(encoding="utf-8"))
            self.assertEqual(settings["permissions"], {"allow": ["Read"]})
            self.assertEqual(settings["statusLine"]["type"], "command")
            for event in ("SessionStart", "SessionEnd"):
                self.assertEqual(len(settings["hooks"][event]), 1)
                self.assertEqual(settings["hooks"][event][0]["hooks"][0]["timeout"], 5)

            self.assertTrue((settings_path.parent / token_mass.INSTALL_STATE).is_file())

            config = ghostty_path.read_text(encoding="utf-8")
            self.assertIn("font-size = 13", config)
            self.assertEqual(config.count(token_mass.CONFIG_BEGIN), 1)
            self.assertEqual(config.count("custom-shader-animation = true"), 1)

    def test_uninstall_restores_previous_status_line_and_keeps_other_hooks(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings_path = root / ".claude" / "settings.json"
            ghostty_path = root / ".config" / "ghostty" / "config.ghostty"
            settings_path.parent.mkdir(parents=True)
            previous_status = {"type": "command", "command": "old-status"}
            custom_group = {"hooks": [{"type": "command", "command": "keep-me"}]}
            settings_path.write_text(
                json.dumps(
                    {
                        "statusLine": previous_status,
                        "hooks": {"SessionStart": [custom_group]},
                    }
                ),
                encoding="utf-8",
            )

            token_mass.install(settings_path, ghostty_path)
            with mock.patch.object(token_mass, "emit") as emit:
                token_mass.uninstall(settings_path, ghostty_path)

            settings = json.loads(settings_path.read_text(encoding="utf-8"))
            self.assertEqual(settings["statusLine"], previous_status)
            self.assertEqual(settings["hooks"]["SessionStart"], [custom_group])
            self.assertNotIn("SessionEnd", settings["hooks"])
            self.assertNotIn(
                token_mass.CONFIG_BEGIN, ghostty_path.read_text(encoding="utf-8")
            )
            self.assertFalse((settings_path.parent / token_mass.INSTALL_STATE).exists())
            emit.assert_called_once_with(token_mass.RESET_PACKET)

    def test_install_rejects_non_object_settings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings_path = root / "settings.json"
            settings_path.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(TypeError, "JSON object"):
                token_mass.install(settings_path, root / "config.ghostty")

    def test_doctor_passes_critical_checks_after_install(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings_path = root / "settings.json"
            ghostty_path = root / "config.ghostty"
            token_mass.install(settings_path, ghostty_path)
            checks = token_mass.doctor(settings_path, ghostty_path)
            self.assertFalse(
                [message for status, message in checks if status == "FAIL"]
            )


class CommandTests(unittest.TestCase):
    def test_general_help_lists_commands(self) -> None:
        output = io.StringIO()
        with mock.patch.object(token_mass.sys, "stdout", output):
            token_mass.cli(["--help"])
        self.assertIn("--install", output.getvalue())
        self.assertIn("--sweep", output.getvalue())

    def test_parse_level_accepts_fraction_and_percentage(self) -> None:
        self.assertEqual(token_mass.parse_level("0.82"), 0.82)
        self.assertEqual(token_mass.parse_level("82"), 0.82)
        self.assertEqual(token_mass.parse_level("82%"), 0.82)

    def test_manual_test_derives_tokens_from_window(self) -> None:
        with (
            mock.patch.object(token_mass, "apply") as apply,
            mock.patch.object(token_mass.sys, "stdout", io.StringIO()) as stdout,
        ):
            token_mass.test_main(["75", "--window-size", "1000000"])
        apply.assert_called_once_with(0.75, 750_000)
        self.assertIn("NEUTRON STAR", stdout.getvalue())

    def test_sweep_emits_requested_number_of_steps(self) -> None:
        with (
            mock.patch.object(token_mass, "apply") as apply,
            mock.patch.object(token_mass.time, "sleep") as sleep,
            mock.patch.object(token_mass.sys, "stdout", io.StringIO()),
        ):
            token_mass.sweep_main(["--seconds", "2", "--steps", "3"])
        self.assertEqual(
            apply.call_args_list,
            [mock.call(0.0, 0), mock.call(0.5, 100_000), mock.call(1.0, 200_000)],
        )
        self.assertEqual(sleep.call_count, 2)


class MainTests(unittest.TestCase):
    def run_main(self, payload: dict | str) -> tuple[str, list[bytes]]:
        source = payload if isinstance(payload, str) else json.dumps(payload)
        stdout = io.StringIO()
        emitted: list[bytes] = []
        with (
            mock.patch.object(token_mass.sys, "stdin", io.StringIO(source)),
            mock.patch.object(token_mass.sys, "stdout", stdout),
            mock.patch.object(token_mass, "emit", side_effect=emitted.append),
        ):
            token_mass.main()
        return stdout.getvalue(), emitted

    def test_status_line_event(self) -> None:
        output, emitted = self.run_main(
            {
                "context_window": {
                    "used_percentage": 99,
                    "total_input_tokens": 198_000,
                    "context_window_size": 200_000,
                },
                "model": {"display_name": "Demo Model"},
            }
        )
        self.assertEqual(len(emitted), 1)
        self.assertEqual(len(emitted[0]), 26)
        self.assertIn("MASS 198.0K TOKENS · 99% · QUASAR · Demo Model", output)

    def test_session_lifecycle_events(self) -> None:
        start_output, start_packets = self.run_main({"hook_event_name": "SessionStart"})
        end_output, end_packets = self.run_main({"hook_event_name": "SessionEnd"})
        self.assertEqual(start_output, "")
        self.assertEqual(
            start_packets, [token_mass.mass_packet(0) + token_mass.level_packet(0)]
        )
        self.assertEqual(end_output, "")
        self.assertEqual(end_packets, [b"\x1b]112\x07"])

    def test_bad_json_is_best_effort(self) -> None:
        output, emitted = self.run_main("{not-json")
        self.assertIn("MASS 0 TOKENS · 0% · RED DWARF", output)
        self.assertEqual(len(emitted), 1)

    def test_non_object_json_is_best_effort(self) -> None:
        output, emitted = self.run_main("[]")
        self.assertIn("MASS 0 TOKENS · 0% · RED DWARF", output)
        self.assertEqual(len(emitted), 1)


if __name__ == "__main__":
    unittest.main()

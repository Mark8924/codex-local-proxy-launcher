"""Regression tests use temporary apps and loopback listeners, never the user's app."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "macos/Codex Launcher.app"
COMMON = APP / "Contents/Resources/launcher-common.zsh"
LAUNCHER_KEYS = (
    "CODEX_PROXY_CONFIG", "CODEX_PROXY_PORT", "CODEX_PROXY_HOST",
    "CODEX_PROXY_SCHEME", "CODEX_PROXY_URL", "CODEX_APP_PATH",
    "CODEX_ICON_PATH", "CODEX_NO_PROXY",
)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="launcher test ")
        self.addCleanup(self.directory.cleanup)
        self.temp = Path(self.directory.name)
        self.env = dict(os.environ)
        for key in LAUNCHER_KEYS:
            self.env.pop(key, None)

    def shell(self, code, *args, env=None):
        return subprocess.run(
            ["/bin/zsh", "-eu", "-c", 'source "$1"; ' + code,
             "test", str(COMMON), *map(str, args)],
            env={**self.env, **(env or {})},
            capture_output=True, text=True, timeout=10,
        )

    def test_proxy_defaults_and_argument(self):
        result = self.shell('configure_proxy; print -r -- "$proxy_url|$check_host|$check_port"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "http://127.0.0.1:10808|127.0.0.1|10808")
        result = self.shell('configure_proxy 7890; print "$check_port"', env={"CODEX_PROXY_PORT": "10809"})
        self.assertEqual(result.stdout.strip(), "7890")

    def test_proxy_urls(self):
        for url, host, port in (
            ("http://127.0.0.1:7890/", "127.0.0.1", 7890),
            ("http://user:p%23ss@[::1]:7890", "::1", 7890),
            ("http://[::1]", "::1", 80),
            ("https://localhost/", "localhost", 443),
        ):
            with self.subTest(url=url):
                result = self.shell(
                    'configure_proxy 1234; print -r -- "$check_host|$check_port|$proxy_url"',
                    env={"CODEX_PROXY_URL": url},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), f"{host}|{port}|{url}")

    def test_ipv6_host_setting(self):
        for host in ("::1", "[::1]"):
            result = self.shell(
                'configure_proxy 7890; print -r -- "$proxy_url|$check_host"',
                env={"CODEX_PROXY_HOST": host},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "http://[::1]:7890|::1")

    def test_invalid_proxy_settings(self):
        for port in ("0", "65536", "-1", "abc", "1.5", "999999999999999999999", " 80"):
            with self.subTest(port=port):
                result = self.shell('configure_proxy "$2"', port)
                self.assertNotEqual(result.returncode, 0)
        for url in (
            "localhost:7890", "socks5://localhost:7890", "http://:7890",
            "http://localhost:", "http://localhost:0", "http://localhost:65536",
            "http://localhost:abc", "http://::1:7890", "http://[::1",
            "http://localhost:7890/path", "http://localhost:7890?query",
            "http://localhost:7890#fragment", "http://-z:7890",
        ):
            with self.subTest(url=url):
                result = self.shell('configure_proxy', env={"CODEX_PROXY_URL": url})
                self.assertNotEqual(result.returncode, 0)

    def test_config_quotes_comments_bom_and_precedence(self):
        config = self.temp / "config.env"
        config.write_bytes(
            b'\xef\xbb\xbfCODEX_PROXY_PORT=7890 # port\r\n'
            b'CODEX_APP_PATH="/Applications/Example #1.app" # comment\r\n'
            b"CODEX_ICON_PATH='/tmp/icon#1.icns'\r\n"
            b'CODEX_NO_PROXY=localhost,example.test\r\n'
            b'UNRECOGNIZED_SETTING=ignored\r\n'
            b'CODEX_PROXY_PORT=9999'
        )
        result = self.shell(
            'load_config_file "$2"; print -r -- "$CODEX_PROXY_PORT|$CODEX_APP_PATH|$CODEX_ICON_PATH|$CODEX_NO_PROXY"',
            config,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "7890|/Applications/Example #1.app|/tmp/icon#1.icns|localhost,example.test",
        )
        # A duplicate key on the final line must not trigger zsh's errexit.
        result = self.shell(
            'load_config_file "$2"; print "$CODEX_PROXY_PORT"',
            config, env={"CODEX_PROXY_PORT": "1234"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1234")

    def test_explicit_missing_config_is_reported(self):
        result = self.shell(
            'load_launcher_config "$2"', self.temp,
            env={"CODEX_PROXY_CONFIG": str(self.temp / "missing.env")},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Config file not found", result.stderr)

    def make_app(self, exit_code=0):
        app = self.temp / "Example #1.app"
        binary = app / "Contents/MacOS/Example App"
        binary.parent.mkdir(parents=True)
        with (app / "Contents/Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleExecutable": binary.name}, file)
        output = self.temp / "child-env.json"
        binary.write_text(
            "#!/bin/sh\n"
            f'exec "{os.sys.executable}" -c \''
            "import json,os,sys; "
            'json.dump({k:os.environ.get(k) for k in '
            '["HTTP_PROXY","HTTPS_PROXY","ALL_PROXY","NO_PROXY","http_proxy","https_proxy","all_proxy","no_proxy"]}, '
            'open(sys.argv[1],"w")); '
            f"sys.exit({exit_code})' " + f'"{output}"\n'
        )
        binary.chmod(0o755)
        return app, binary, output

    def test_app_bundle_executable_and_invalid_override(self):
        app, binary, _ = self.make_app()
        for path in (app, binary):
            result = self.shell("resolve_app_executable", env={"CODEX_APP_PATH": str(path)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, str(binary.resolve()))
        for path in (self.temp / "missing.app", self.temp):
            result = self.shell("resolve_app_executable", env={"CODEX_APP_PATH": str(path)})
            self.assertNotEqual(result.returncode, 0)

    def test_process_matching_uses_executable_path(self):
        process = subprocess.Popen(["/bin/sleep", "10"])
        def cleanup():
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
        self.addCleanup(cleanup)
        result = self.shell('find_running_app /bin/sleep')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(process.pid), result.stdout)
        result = self.shell('find_running_app "/nonexistent/sleep"')
        self.assertNotEqual(result.returncode, 0)
        process.terminate()

    def test_native_entry_launches_with_proxy_environment(self):
        _, binary, output = self.make_app()
        app_copy = self.temp / "Launcher copy.app"
        shutil.copytree(APP, app_copy)
        listener = socket.socket()
        self.addCleanup(listener.close)
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        url = f"http://127.0.0.1:{port}"
        env = {
            **self.env, "CODEX_APP_PATH": str(binary),
            "CODEX_PROXY_URL": url, "CODEX_NO_PROXY": "localhost,127.0.0.1,::1",
            "TMPDIR": str(self.temp),
        }
        result = subprocess.run(
            [str(app_copy / "Contents/MacOS/Codex Launcher")],
            env=env, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for _ in range(50):
            if output.exists():
                break
            time.sleep(0.05)
        self.assertTrue(output.exists(), "Native entry did not start the fake application")
        values = json.loads(output.read_text())
        for key in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
            self.assertEqual(values[key], url)
        self.assertEqual(values["NO_PROXY"], "localhost,127.0.0.1,::1")
        self.assertEqual(values["no_proxy"], values["NO_PROXY"])
        self.assertFalse((app_copy / "Contents/Resources/icon.icns").exists())

    def test_startup_failure_is_reported(self):
        _, binary, _ = self.make_app(exit_code=17)
        app_copy = self.temp / "Failure test.app"
        shutil.copytree(APP, app_copy)
        script = app_copy / "Contents/Resources/launcher.zsh"
        # Stub only the GUI presentation in this disposable copy.
        script.write_text(script.read_text().replace("/usr/bin/osascript", "/usr/bin/true"))
        listener = socket.socket()
        self.addCleanup(listener.close)
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        result = subprocess.run(
            ["/bin/zsh", str(script)],
            env={
                **self.env, "CODEX_APP_PATH": str(binary),
                "CODEX_PROXY_URL": f"http://127.0.0.1:{listener.getsockname()[1]}",
                "TMPDIR": str(self.temp),
            },
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertIn("failed to start", result.stderr)


if __name__ == "__main__":
    unittest.main()

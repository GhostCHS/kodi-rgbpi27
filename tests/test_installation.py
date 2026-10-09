from pathlib import Path
import os
import subprocess
import tempfile
import importlib.util
import signal

repo = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    ports = root / "roms" / "ports"
    dats = root / "dats"
    ports.mkdir(parents=True)
    dats.mkdir()

    old = ports / "RGB-PI Updater27"
    (old / "data").mkdir(parents=True)
    (old / "update.sh").write_text("old\n", encoding="utf-8")
    (old / "data" / "private-test.sh").write_text("preserved\n", encoding="utf-8")

    original_games = (
        b'"","","ports","ports","/roms/ports/Other/update.sh","Other","?","?","2026","1"\n'
        b'"","","ports","ports","/roms/ports/RGB-PI Updater27/update.sh","RGB-PI Updater27","?","?","2026","1"\n'
        b'"","","ports","ports","/roms/ports/RGB-PI Updater27/data/update_kodi.sh","Old helper","?","?","2026","1"\n'
    )
    (dats / "games.dat").write_bytes(original_games)

    cmd = ["bash", str(repo / "install.sh"), str(ports)]
    subprocess.run(cmd, check=True)

    runtime = root / ".rgbpi-updater27"
    assert (runtime / "data" / "manifest.json").read_bytes() == (repo / "manifest.json").read_bytes()
    assert len(list(ports.rglob("*.sh"))) == 1
    assert len(list(runtime.glob("legacy.*/port/data/private-test.sh"))) == 1

    for retired in ("update_kodi.sh", "make_pi_root.sh", "ensure_pi_sudo.sh"):
        assert not (runtime / "data" / retired).exists(), retired

    cleaned_games = (dats / "games.dat").read_bytes()
    assert b"/roms/ports/Other/update.sh" in cleaned_games
    assert b"/roms/ports/RGB-PI Updater27/update.sh" in cleaned_games
    assert b"/roms/ports/RGB-PI Updater27/data/" not in cleaned_games
    assert (runtime / "games.dat.before-updater27-cleanup").read_bytes() == original_games

    (runtime / "logs").mkdir()
    (runtime / "logs" / "keep").write_text("keep\n", encoding="utf-8")
    subprocess.run(cmd, check=True)
    assert (runtime / "logs" / "keep").read_text(encoding="utf-8") == "keep\n"
    assert len(list(ports.rglob("*.sh"))) == 1

    # Replace hardware/update actions with recording stubs; exercise launcher dispatch.
    for script in (runtime / "data").glob("*.sh"):
        script.write_text('#!/bin/bash\nprintf "called:%s\\n" "$0"\n', encoding="utf-8")

    launcher = (runtime / "update.sh").read_text(encoding="utf-8").replace("$EUID", "$TEST_EUID")
    (runtime / "update.sh").write_text(launcher, encoding="utf-8")

    mock_bin = root / "bin"
    mock_bin.mkdir()
    mock_sudo = mock_bin / "sudo"
    mock_sudo.write_text("#!/bin/bash\necho unexpected-sudo >&2\nexit 1\n", encoding="utf-8")
    mock_sudo.chmod(0o755)

    env = dict(os.environ, PATH=str(mock_bin) + ":" + os.environ["PATH"], TEST_EUID="0")
    for action in ("retroarch", "cores", "timings", "bootstrap", "mount"):
        proc = subprocess.run(
            ["bash", str(runtime / "update.sh"), action],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == 0, (action, proc.stdout, proc.stderr)
        assert "called:" in proc.stdout
        assert "unexpected-sudo" not in proc.stderr

    proc = subprocess.run(
        ["bash", str(ports / "RGB-PI Updater27" / "update.sh"), "cores"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0 and "called:" in proc.stdout

    env["TEST_EUID"] = "1000"
    proc = subprocess.run(
        ["bash", str(runtime / "update.sh"), "retroarch"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 77
    assert "Ports" in proc.stdout
    assert "called:" not in proc.stdout

    proc = subprocess.run(
        ["bash", str(runtime / "update.sh"), "root"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 77

    print(
        "PASS: installer backup/cleanup is idempotent; retired helpers stay out of the runtime; "
        "root dispatch bypasses sudo; restricted SSH fails safely."
    )

for script in [repo / "update.sh", repo / "install.sh", *(repo / "data").glob("*.sh")]:
    subprocess.run(["bash", "-n", str(script)], check=True)

print("PASS: all shell scripts parse.")


# Regression test: a completed child keeps its stdout pipe readable at EOF.
# The progress loop must detect b"" and return instead of spinning forever.
spec = importlib.util.spec_from_file_location(
    "rgbpi_update_menu",
    repo / "data" / "rgbpi_update_menu.py",
)
menu = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(menu)

app = object.__new__(menu.MenuApp)
class _Event:
    @staticmethod
    def pump():
        pass
class _Pygame:
    event = _Event()
app.pygame = _Pygame()
class _Clock:
    @staticmethod
    def tick(_fps):
        pass
app.clock = _Clock()
app.draw_progress = lambda *args, **kwargs: None

def _alarm(_signum, _frame):
    raise TimeoutError("progress loop failed to terminate at stdout EOF")

old_handler = signal.signal(signal.SIGALRM, _alarm)
signal.alarm(3)
try:
    rc = app.run_command_with_progress(
        ["bash", "-lc", "printf '[100%%] [#] done\\n'"],
        title="TEST",
        status="EOF regression",
        step_index=0,
        step_total=1,
    )
finally:
    signal.alarm(0)
    signal.signal(signal.SIGALRM, old_handler)
assert rc == 0
print("PASS: progress loop terminates on child stdout EOF.")

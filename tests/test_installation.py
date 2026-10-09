from pathlib import Path
import os
import subprocess
import tempfile

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

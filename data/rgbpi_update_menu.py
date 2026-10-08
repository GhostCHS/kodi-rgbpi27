#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import select
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

DATA_DIR = Path(os.environ.get("DATA_ROOT", Path(__file__).resolve().parent))
APP_ROOT = Path(os.environ.get("APP_ROOT", DATA_DIR.parent))
KODI_SCRIPT = DATA_DIR / "update_kodi.sh"
RETROARCH_SCRIPT = DATA_DIR / "update_retroarch.sh"
CORES_SCRIPT = DATA_DIR / "update_cores.sh"
TIMINGS_SCRIPT = DATA_DIR / "update_timings.sh"
PREFLIGHT_SCRIPT = DATA_DIR / "preflight.sh"
BOOTSTRAP_SCRIPT = DATA_DIR / "bootstrap_local_metadata.sh"
CRT_GUARD_SCRIPT = DATA_DIR / "crt_guard.sh"

KODI_LOG = Path("/var/log/kodi-updater/latest.log")
RETROARCH_LOG = Path("/var/log/retroarch-updater/latest.log")
UPDATE_ALL_LOG = APP_ROOT / "logs" / "update-all.log"
BOOTSTRAP_LOG = Path("/var/log/rgbpi-updater-bootstrap/latest.log")
WINDOW_SIZE = (320, 240)
BUNDLED_ASSETS = [
    DATA_DIR / "manifest.json",
    DATA_DIR / "kodi.deb",
    DATA_DIR / "kodi-omega-peripheral-joystick.tar.gz",
]
FPS = 30
BTN_BACK = 6
BTN_START = 7
COMBO_WINDOW_SECONDS = 0.35
PROGRESS_RE = re.compile(r"\[(\d{1,3})%\]\s*\[[^\]]*\]\s*(.*)")
UPDATE_STEP_TIMEOUT_SECONDS = int(os.environ.get("RGBPI_UPDATE_STEP_TIMEOUT", "300"))


@dataclass
class Status:
    installed: str = "unknown"
    available: str = "unknown"
    update_available: bool = False
    reachable: bool = True


@dataclass
class MenuEntry:
    label: str
    action: Optional[Callable[[], int]] = None
    kind: str = "info"


@dataclass
class MenuState:
    name: str
    title: str
    subtitle: str
    entries: list[MenuEntry]


def _extract(text: str, pattern: str) -> Optional[str]:
    match = re.search(pattern, text, re.MULTILINE)
    return match.group(1).strip() if match else None


def use_bundled_manifest() -> bool:
    return os.environ.get("FORCE_BUNDLED_MANIFEST") == "YES" or all(path.exists() for path in BUNDLED_ASSETS)


def _runtime_env_args() -> list[str]:
    args = [f"APP_ROOT={APP_ROOT}", f"DATA_ROOT={DATA_DIR}"]
    for key in ("REPO_OWNER", "REPO_NAME", "UPDATE_BRANCH"):
        value = os.environ.get(key)
        if value:
            args.append(f"{key}={value}")
    if use_bundled_manifest():
        args.append("FORCE_BUNDLED_MANIFEST=YES")
    return args


def status_script_command(script: Path, mode: str) -> list[str]:
    return ["env", *_runtime_env_args(), "bash", str(script), mode]


def sudo_script_command(script: Path, mode: str) -> list[str]:
    if os.geteuid() == 0:
        return ["env", *_runtime_env_args(), "bash", str(script), mode]
    return ["sudo", "-n", "env", *_runtime_env_args(), "bash", str(script), mode]


def run_status(script: Path) -> Status:
    try:
        proc = subprocess.run(
            status_script_command(script, "--status"),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=90,
            check=False,
        )
    except Exception:
        return Status(reachable=False)

    text = proc.stdout
    installed = _extract(text, r"^INSTALLED_VERSION=(.*)$") or _extract(text, r"Installed version\s*:\s*(.*)")
    available = _extract(text, r"^AVAILABLE_VERSION=(.*)$") or _extract(text, r"Available version\s*:\s*(.*)")
    update = (_extract(text, r"^UPDATE_AVAILABLE=(YES|NO)$") or "NO") == "YES"
    return Status(
        installed=installed or "unknown",
        available=available or "unknown",
        update_available=update,
        reachable=proc.returncode == 0,
    )


def run_action(script: Path) -> int:
    return subprocess.call(sudo_script_command(script, "--update"))


def run_script(script: Path, *args: str) -> int:
    mode = args[0] if args else "--update"
    command = sudo_script_command(script, mode)
    if len(args) > 1:
        command.extend(args[1:])
    return subprocess.call(command)


def process_tree_cpu_ticks(root_pid: int) -> int:
    """Return accumulated user+system CPU ticks for a process and its descendants."""
    processes: dict[int, tuple[int, int]] = {}
    try:
        proc_entries = list(Path("/proc").iterdir())
    except OSError:
        return 0

    for entry in proc_entries:
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "stat").read_text(encoding="utf-8", errors="replace")
            close = raw.rfind(")")
            if close < 0:
                continue
            fields = raw[close + 2 :].split()
            pid = int(entry.name)
            ppid = int(fields[1])
            ticks = int(fields[11]) + int(fields[12])
            processes[pid] = (ppid, ticks)
        except (OSError, ValueError, IndexError):
            continue

    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _ticks) in processes.items():
            if pid not in descendants and ppid in descendants:
                descendants.add(pid)
                changed = True

    return sum(processes.get(pid, (0, 0))[1] for pid in descendants)


def format_elapsed(seconds: float) -> str:
    total = max(0, int(seconds))
    minutes, secs = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def read_log_tail(path: Path, max_lines: int = 11) -> list[str]:
    if not path.exists():
        return ["Log not found."]
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception as exc:
        return [f"Could not read log: {exc}"]
    tail = lines[-max_lines:]
    return tail or ["Log is empty."]


def root_access_ready() -> bool:
    if os.geteuid() == 0:
        return True
    try:
        return subprocess.run(
            ["sudo", "-n", "true"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False,
        ).returncode == 0
    except Exception:
        return False


def ensure_runtime_env() -> None:
    os.environ.setdefault("SDL_VIDEODRIVER", "fbcon")
    os.environ.setdefault("SDL_FBDEV", "/dev/fb0")
    os.environ.setdefault("SDL_NOMOUSE", "1")
    os.environ.setdefault("SDL_AUDIODRIVER", "alsa")
    os.environ.setdefault("XDG_RUNTIME_DIR", "/tmp")


def candidate_devices():
    try:
        from evdev import InputDevice, ecodes, list_devices
    except Exception:
        return []

    devices = []
    for path in list_devices():
        try:
            dev = InputDevice(path)
            caps = dev.capabilities(verbose=False)
            keys = caps.get(ecodes.EV_KEY, [])
            abs_caps = caps.get(ecodes.EV_ABS, [])
            if ecodes.BTN_SOUTH in keys or ecodes.BTN_A in keys or ecodes.ABS_HAT0X in abs_caps:
                try:
                    dev.grab()
                except OSError:
                    pass
                try:
                    os.set_blocking(dev.fd, False)
                except OSError:
                    pass
                devices.append(dev)
        except OSError:
            continue
    return devices


class MenuApp:
    def __init__(self) -> None:
        ensure_runtime_env()

        import pygame

        pygame.init()
        pygame.font.init()
        self.pygame = pygame
        self.screen = pygame.display.set_mode(WINDOW_SIZE, pygame.FULLSCREEN)
        pygame.display.set_caption("RGB-Pi 27 Updater")
        pygame.mouse.set_visible(False)

        self.clock = pygame.time.Clock()
        self.title_font = pygame.font.Font(None, 26)
        self.body_font = pygame.font.Font(None, 18)
        self.small_font = pygame.font.Font(None, 14)
        self.tiny_font = pygame.font.Font(None, 12)

        self.kodi = Status()
        self.retroarch = Status()
        self.cores = Status()
        self.timings = Status()
        self.state = "main"
        self.index = 0
        self.notice = ""
        self.notice_until = 0.0
        self.log_title = ""
        self.log_lines: list[str] = []
        self.controller_devices = []
        self.last_controller_scan = 0.0
        self.last_back_press = 0.0
        self.last_start_press = 0.0
        self.refresh()

    def refresh(self) -> None:
        self.kodi = run_status(KODI_SCRIPT)
        self.retroarch = run_status(RETROARCH_SCRIPT)
        self.cores = run_status(CORES_SCRIPT)
        self.timings = run_status(TIMINGS_SCRIPT)

    def set_notice(self, message: str, seconds: float = 2.0) -> None:
        self.notice = message
        self.notice_until = time.monotonic() + seconds

    def build_state(self) -> MenuState:
        if self.state == "main":
            pending = self.all_pending_updates()
            return MenuState(
                name="main",
                title="RGB-PI 27 UPDATER",
                subtitle="ONE-BUTTON UPDATE",
                entries=[
                    MenuEntry(
                        f"UPDATE EVERYTHING ({len(pending)})" if pending else "UPDATE EVERYTHING",
                        self.run_update_all,
                        "action",
                    ),
                    MenuEntry("Status", lambda: self.open_state("status"), "action"),
                    MenuEntry("System", lambda: self.open_state("system"), "action"),
                    MenuEntry("View Update Log", lambda: self.open_log("Update All Log", UPDATE_ALL_LOG), "action"),
                    MenuEntry("Return", self.exit_app, "action"),
                ],
            )
        if self.state == "status":
            pending = self.all_pending_updates()
            entries = [
                MenuEntry(f"Kodi: {self.kodi.installed} -> {self.kodi.available}"),
                MenuEntry(f"RetroArch: {self.retroarch.installed} -> {self.retroarch.available}"),
                MenuEntry(f"Cores: {self.cores.installed} -> {self.cores.available}"),
                MenuEntry(f"Timings: {self.timings.installed} -> {self.timings.available}"),
                MenuEntry(f"Pending: {', '.join(pending) if pending else 'none'}"),
                MenuEntry("Back", lambda: self.open_state("main"), "action"),
            ]
            return MenuState("status", "STATUS", "KODI / RETROARCH / CORES / TIMINGS", entries)
        if self.state == "system":
            entries = [
                MenuEntry(f"GUI root: {'READY' if root_access_ready() else 'OFF'}"),
                MenuEntry("Run Preflight", self.open_preflight, "action"),
                MenuEntry("Run CRT Check", self.open_crt_check, "action"),
                MenuEntry("Bootstrap Metadata", lambda: self.run_system_action(BOOTSTRAP_SCRIPT, "Metadata refreshed"), "action"),
                MenuEntry("View Bootstrap log", lambda: self.open_log("Bootstrap Log", BOOTSTRAP_LOG), "action"),
                MenuEntry("Back", lambda: self.open_state("main"), "action"),
            ]
            return MenuState("system", "SYSTEM", "CRT / CHECKS / METADATA", entries)
        return MenuState("log", self.log_title, "B TO GO BACK", [MenuEntry(line) for line in self.log_lines] + [MenuEntry("Back", lambda: self.open_state("main"), "action")])

    def open_state(self, name: str) -> int:
        self.state = name
        self.index = 0
        if name != "log":
            self.refresh()
        return 0

    def open_log(self, title: str, path: Path) -> int:
        self.log_title = title
        self.log_lines = read_log_tail(path)
        self.state = "log"
        self.index = max(0, len(self.log_lines))
        return 0

    def open_preflight(self) -> int:
        env = os.environ.copy()
        env["APP_ROOT"] = str(APP_ROOT)
        env["DATA_ROOT"] = str(DATA_DIR)
        try:
            proc = subprocess.run(
                ["bash", str(PREFLIGHT_SCRIPT)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=15,
                check=False,
                env=env,
            )
            lines = proc.stdout.splitlines()
            if proc.returncode not in (0, 2):
                lines.append(f"Preflight exited with {proc.returncode}")
        except Exception as exc:
            lines = [f"Preflight failed: {exc}"]
        self.log_title = "Preflight"
        self.log_lines = lines or ["No preflight output."]
        self.state = "log"
        self.index = max(0, len(self.log_lines))
        return 0

    def open_crt_check(self) -> int:
        env = os.environ.copy()
        env["APP_ROOT"] = str(APP_ROOT)
        env["DATA_ROOT"] = str(DATA_DIR)
        try:
            proc = subprocess.run(
                ["bash", str(CRT_GUARD_SCRIPT), "--status"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=20,
                check=False,
                env=env,
            )
            lines = proc.stdout.splitlines()
        except Exception as exc:
            lines = [f"CRT check failed: {exc}"]
        self.log_title = "CRT Check"
        self.log_lines = lines or ["No CRT check output."]
        self.state = "log"
        self.index = max(0, len(self.log_lines))
        return 0

    def run_and_refresh(self, script: Path) -> int:
        rc = self.run_with_progress(script, "Running update...")
        self.refresh()
        self.set_notice("Update complete" if rc == 0 else f"Update failed ({rc})", 2.5)
        return rc

    def all_pending_updates(self) -> list[str]:
        pending = []
        if self.kodi.update_available:
            pending.append("Kodi")
        if self.retroarch.update_available:
            pending.append("RetroArch")
        if self.cores.update_available:
            pending.append("Cores")
        if self.timings.update_available:
            pending.append("Timings")
        return pending

    def run_update_all(self) -> int:
        if not root_access_ready():
            self.set_notice("Root required for UPDATE EVERYTHING", 4.0)
            return 77

        steps: list[tuple[str, list[str]]] = [
            ("Kodi", sudo_script_command(KODI_SCRIPT, "--update")),
            ("RetroArch", sudo_script_command(RETROARCH_SCRIPT, "--update")),
            ("Cores", sudo_script_command(CORES_SCRIPT, "--update")),
            ("CRT Timings", sudo_script_command(TIMINGS_SCRIPT, "--update")),
            ("CRT verification", ["env", *_runtime_env_args(), "bash", str(CRT_GUARD_SCRIPT), "--strict"]),
        ]

        failed_count = self.run_commands_with_progress(steps, UPDATE_ALL_LOG)
        self.refresh()
        if failed_count == 0:
            self.set_notice("Everything updated", 3.0)
        else:
            self.set_notice(f"Done - skipped {failed_count} failed step(s)", 4.0)
        return 0

    def run_system_action(self, script: Path, success_notice: str) -> int:
        self.draw_loading("Applying system change...")
        rc = run_script(script)
        self.refresh()
        self.set_notice(success_notice if rc == 0 else f"Action failed ({rc})", 2.5)
        return rc

    def overall_progress(self, step_index: int, step_total: int, child_percent: int) -> int:
        child_percent = max(0, min(100, child_percent))
        if step_total <= 1:
            return child_percent
        overall = ((step_index + (child_percent / 100.0)) / step_total) * 100.0
        return max(0, min(100, int(round(overall))))

    def parse_progress_segment(self, segment: str, current_percent: int, current_detail: str) -> tuple[int, str]:
        text = segment.strip()
        if not text:
            return current_percent, current_detail
        match = PROGRESS_RE.search(text)
        if match:
            percent = max(0, min(100, int(match.group(1))))
            detail = match.group(2).strip() or current_detail
            return percent, detail
        return current_percent, text

    def run_with_progress(self, script: Path, message: str) -> int:
        return self.run_command_with_progress(
            sudo_script_command(script, "--update"),
            title="PLEASE WAIT",
            status=message,
            step_index=0,
            step_total=1,
        )

    def run_commands_with_progress(self, steps: list[tuple[str, list[str]]], log_path: Path) -> int:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        failed_steps: list[tuple[str, int]] = []

        with log_path.open("w", encoding="utf-8") as log_handle:
            for index, (name, command) in enumerate(steps):
                log_handle.write(f"== {name} ==\n")
                log_handle.flush()

                try:
                    rc = self.run_command_with_progress(
                        command,
                        title="UPDATE EVERYTHING",
                        status=f"Step {index + 1}/{len(steps)}: {name}",
                        step_index=index,
                        step_total=len(steps),
                        log_handle=log_handle,
                    )
                except Exception as exc:
                    rc = 127
                    log_handle.write(f"ERROR: {name}: {exc}\n")

                if rc != 0:
                    failed_steps.append((name, rc))
                    log_handle.write(f"SKIPPED AFTER ERROR: {name} (exit {rc})\n")
                else:
                    log_handle.write(f"OK: {name}\n")

                log_handle.write("\n")
                log_handle.flush()

            if failed_steps:
                log_handle.write("== SUMMARY ==\n")
                for name, rc in failed_steps:
                    log_handle.write(f"SKIPPED: {name} (exit {rc})\n")
                log_handle.flush()

        return len(failed_steps)

    def run_command_with_progress(
        self,
        command: list[str],
        title: str,
        status: str,
        step_index: int,
        step_total: int,
        log_handle=None,
    ) -> int:
        proc = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        assert proc.stdout is not None
        fd = proc.stdout.fileno()
        os.set_blocking(fd, False)

        buffer = ""
        percent = 0
        detail = "Starting..."
        started_at = time.monotonic()
        last_output_at = started_at
        last_cpu_sample_at = started_at
        last_cpu_ticks = process_tree_cpu_ticks(proc.pid)
        cpu_state = "starting"
        spinner = "|/-\\"

        while True:
            self.pygame.event.pump()
            ready, _, _ = select.select([proc.stdout], [], [], 0.05)
            now = time.monotonic()
            if ready:
                try:
                    chunk = os.read(fd, 4096)
                except BlockingIOError:
                    chunk = b""
                if chunk:
                    last_output_at = now
                    text = chunk.decode("utf-8", errors="replace")
                    if log_handle is not None:
                        log_handle.write(text.replace("\r", "\n"))
                        log_handle.flush()
                    buffer += text.replace("\r", "\n")
                    while "\n" in buffer:
                        segment, buffer = buffer.split("\n", 1)
                        percent, detail = self.parse_progress_segment(segment, percent, detail)

            if now - last_cpu_sample_at >= 1.0:
                cpu_ticks = process_tree_cpu_ticks(proc.pid)
                cpu_state = "CPU active" if cpu_ticks > last_cpu_ticks else "waiting / I-O"
                last_cpu_ticks = cpu_ticks
                last_cpu_sample_at = now

            elapsed = now - started_at
            output_age = max(0, int(now - last_output_at))

            if elapsed >= UPDATE_STEP_TIMEOUT_SECONDS and proc.poll() is None:
                if log_handle is not None:
                    log_handle.write(
                        f"ERROR: step timed out after {UPDATE_STEP_TIMEOUT_SECONDS}s; skipping\n"
                    )
                    log_handle.flush()
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                    proc.wait(timeout=3)
                except Exception:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except Exception:
                        pass
                return 124

            spin = spinner[int(elapsed * 4) % len(spinner)]
            activity = f"{spin} {cpu_state}  elapsed {format_elapsed(elapsed)}  output {output_age}s ago"

            self.draw_progress(
                title,
                status,
                self.overall_progress(step_index, step_total, percent),
                detail,
                activity,
            )
            self.clock.tick(FPS)

            if proc.poll() is not None and not ready:
                break

        if buffer.strip():
            percent, detail = self.parse_progress_segment(buffer, percent, detail)

        rc = proc.wait()
        final_percent = 100 if rc == 0 else percent
        final_detail = detail if rc == 0 else f"{detail} (failed)"
        final_activity = f"finished after {format_elapsed(time.monotonic() - started_at)}"
        self.draw_progress(
            title,
            status,
            self.overall_progress(step_index, step_total, final_percent),
            final_detail,
            final_activity,
        )
        return rc

    def exit_app(self) -> int:
        raise SystemExit(0)

    def ensure_controller_devices(self) -> None:
        if self.controller_devices:
            return
        now = time.monotonic()
        if now - self.last_controller_scan < 1.0:
            return
        self.last_controller_scan = now
        self.controller_devices = candidate_devices()

    def handle_controller_events(self) -> None:
        try:
            from evdev import ecodes
        except Exception:
            return

        active = []
        for dev in list(self.controller_devices):
            try:
                for event in dev.read():
                    if event.type == ecodes.EV_KEY and event.value == 1:
                        self.on_evdev_button(event.code, ecodes)
                    elif event.type == ecodes.EV_ABS:
                        self.on_evdev_axis(event.code, event.value, ecodes)
            except BlockingIOError:
                pass
            except OSError:
                continue
            active.append(dev)
        self.controller_devices = active

    def on_evdev_button(self, code: int, ecodes) -> None:
        now = time.monotonic()
        if code == ecodes.BTN_START:
            self.last_start_press = now
            if now - self.last_back_press <= COMBO_WINDOW_SECONDS:
                raise SystemExit(0)
            self.on_select()
            return
        if code in (ecodes.BTN_SELECT, ecodes.BTN_MODE):
            self.last_back_press = now
            if now - self.last_start_press <= COMBO_WINDOW_SECONDS:
                raise SystemExit(0)
            self.on_back()
            return
        if code in (ecodes.BTN_SOUTH, ecodes.BTN_A):
            self.on_select()
        elif code in (ecodes.BTN_EAST, ecodes.BTN_B):
            self.on_back()

    def on_evdev_axis(self, code: int, value: int, ecodes) -> None:
        if code == ecodes.ABS_HAT0Y:
            if value == -1:
                self.move(-1)
            elif value == 1:
                self.move(1)
        elif code == ecodes.ABS_HAT0X:
            if value == -1:
                self.on_back()
            elif value == 1:
                self.on_select()

    def handle_events(self) -> None:
        self.ensure_controller_devices()
        self.handle_controller_events()
        for event in self.pygame.event.get():
            if event.type == self.pygame.QUIT:
                raise SystemExit(0)
            if event.type == self.pygame.KEYDOWN:
                if event.key in (self.pygame.K_DOWN, self.pygame.K_s):
                    self.move(1)
                elif event.key in (self.pygame.K_UP, self.pygame.K_w):
                    self.move(-1)
                elif event.key in (self.pygame.K_RETURN, self.pygame.K_SPACE):
                    self.on_select()
                elif event.key in (self.pygame.K_ESCAPE, self.pygame.K_BACKSPACE):
                    self.on_back()

    def selectable_indexes(self, entries: list[MenuEntry]) -> list[int]:
        return [i for i, entry in enumerate(entries) if entry.action is not None]

    def move(self, delta: int) -> None:
        state = self.build_state()
        choices = self.selectable_indexes(state.entries)
        if not choices:
            return
        if self.index not in choices:
            self.index = choices[0]
            return
        pos = choices.index(self.index)
        self.index = choices[(pos + delta) % len(choices)]

    def on_select(self) -> None:
        state = self.build_state()
        if 0 <= self.index < len(state.entries):
            action = state.entries[self.index].action
            if action is not None:
                action()

    def on_back(self) -> None:
        if self.state == "main":
            raise SystemExit(0)
        self.open_state("main")

    def ellipsize(self, font, text: str, width: int) -> str:
        if font.size(text)[0] <= width:
            return text
        trimmed = text
        while trimmed and font.size(trimmed + "...")[0] > width:
            trimmed = trimmed[:-1]
        return (trimmed + "...") if trimmed else "..."

    def draw_loading(self, message: str) -> None:
        self.screen.fill((6, 10, 22))
        self.blit(self.title_font, "PLEASE WAIT", (88, 84), (236, 246, 255))
        self.blit(self.body_font, message, (68, 116), (176, 220, 255))
        self.pygame.display.flip()

    def draw_progress(self, title: str, status: str, percent: int, detail: str, activity: str = "") -> None:
        self.screen.fill((6, 10, 22))
        self.blit(self.title_font, title, (88, 42), (236, 246, 255))
        self.blit(self.body_font, self.ellipsize(self.body_font, status, 286), (18, 76), (176, 220, 255))

        bar_outer = self.pygame.Rect(24, 112, 272, 20)
        bar_inner = self.pygame.Rect(26, 114, max(0, int(268 * (percent / 100.0))), 16)
        self.pygame.draw.rect(self.screen, (16, 34, 74), bar_outer)
        self.pygame.draw.rect(self.screen, (92, 144, 206), bar_outer, 1)
        if bar_inner.width > 0:
            self.pygame.draw.rect(self.screen, (224, 242, 255), bar_inner)
        self.blit(self.body_font, f"{percent}%", (136, 140), (236, 246, 255))
        self.blit(self.small_font, self.ellipsize(self.small_font, detail, 294), (13, 171), (196, 224, 248))
        if activity:
            self.blit(self.tiny_font, self.ellipsize(self.tiny_font, activity, 294), (13, 199), (142, 190, 230))
        self.pygame.display.flip()

    def draw(self) -> None:
        now = time.monotonic()
        if self.notice and now > self.notice_until:
            self.notice = ""

        state = self.build_state()
        entries = state.entries
        choices = self.selectable_indexes(entries)
        if choices and self.index not in choices:
            self.index = choices[0]

        self.screen.fill((5, 10, 22))
        header = self.pygame.Rect(8, 8, 304, 28)
        self.pygame.draw.rect(self.screen, (12, 26, 60), header)
        self.pygame.draw.rect(self.screen, (154, 210, 255), header, 1)
        self.blit(self.title_font, state.title, (16, 13), (240, 246, 255))
        self.blit(self.tiny_font, state.subtitle, (16, 38), (160, 208, 246))

        top = 58
        visible = 8 if state.name != "log" else 10
        offset = 0
        if self.index >= visible:
            offset = self.index - visible + 1

        for row in range(visible):
            idx = offset + row
            if idx >= len(entries):
                break
            entry = entries[idx]
            y = top + row * 20
            rect = self.pygame.Rect(8, y, 304, 18)
            selected = idx == self.index and entry.action is not None
            if selected:
                self.pygame.draw.rect(self.screen, (224, 242, 255), rect)
                self.pygame.draw.rect(self.screen, (18, 86, 160), rect, 1)
                color = (12, 54, 106)
            else:
                self.pygame.draw.rect(self.screen, (16, 34, 74), rect)
                self.pygame.draw.rect(self.screen, (58, 108, 170), rect, 1)
                color = (206, 232, 255) if entry.action else (142, 178, 214)
            label = entry.label
            if state.name != "log":
                label = self.ellipsize(self.small_font, label, 286)
            self.blit(self.small_font, label, (14, y + 3), color)

        footer = self.pygame.Rect(8, 224, 304, 10)
        self.pygame.draw.rect(self.screen, (12, 26, 60), footer)
        self.pygame.draw.rect(self.screen, (92, 144, 206), footer, 1)
        footer_text = self.notice or "D-PAD MOVE   A SELECT   B BACK   START+SELECT EXIT"
        self.blit(self.tiny_font, self.ellipsize(self.tiny_font, footer_text, 292), (14, 224), (176, 220, 255))
        self.pygame.display.flip()

    def blit(self, font, text: str, pos: tuple[int, int], color: tuple[int, int, int]) -> None:
        self.screen.blit(font.render(text, True, color), pos)

    def run(self) -> int:
        while True:
            self.handle_events()
            self.draw()
            self.clock.tick(FPS)


def main() -> int:
    if "--dump-status" in sys.argv:
        kodi = run_status(KODI_SCRIPT)
        retroarch = run_status(RETROARCH_SCRIPT)
        cores = run_status(CORES_SCRIPT)
        timings = run_status(TIMINGS_SCRIPT)
        print(f"KODI_INSTALLED={kodi.installed}")
        print(f"KODI_AVAILABLE={kodi.available}")
        print(f"KODI_UPDATE={'YES' if kodi.update_available else 'NO'}")
        print(f"RETROARCH_INSTALLED={retroarch.installed}")
        print(f"RETROARCH_AVAILABLE={retroarch.available}")
        print(f"RETROARCH_UPDATE={'YES' if retroarch.update_available else 'NO'}")
        print(f"CORES_INSTALLED={cores.installed}")
        print(f"CORES_AVAILABLE={cores.available}")
        print(f"CORES_UPDATE={'YES' if cores.update_available else 'NO'}")
        print(f"TIMINGS_INSTALLED={timings.installed}")
        print(f"TIMINGS_AVAILABLE={timings.available}")
        print(f"TIMINGS_UPDATE={'YES' if timings.update_available else 'NO'}")
        return 0

    if "--terminal" in sys.argv:
        print("Terminal mode is no longer the preferred RGB-Pi path.")
        return 1

    try:
        return MenuApp().run()
    except SystemExit:
        raise
    except Exception as exc:
        print(f"rgbpi_update_menu.py failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

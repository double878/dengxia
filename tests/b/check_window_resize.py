"""Exercise real Windows maximize/restore/close on the source project or export.

Run with Python 3.13 on Windows. Only processes launched here may be terminated.
Results and engine output are saved under builds/window-resize/.
"""

import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path)
    parser.add_argument("--scene")
    parser.add_argument("--fullscreen", action="store_true")
    parser.add_argument("--intro", action="store_true")
    args = parser.parse_args()
    if sys.platform != "win32":
        parser.error("This regression requires a real Windows desktop.")
    if args.exe and args.scene:
        parser.error("Scene overrides require the source project.")

    project = Path(__file__).resolve().parents[2]
    output = project / "builds/window-resize"
    output.mkdir(parents=True, exist_ok=True)
    label = "packed" if args.exe else "source"
    label += "-fullscreen" if args.fullscreen else "-windowed"
    label += "-intro" if args.intro else ""
    if args.scene:
        label += "-" + Path(args.scene).parent.name + "-" + Path(args.scene).stem

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    user32.SetProcessDPIAware()
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsZoomed.argtypes = [wintypes.HWND]
    user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user32.SendMessageTimeoutW.argtypes = [
        wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM,
        wintypes.UINT, wintypes.UINT, ctypes.POINTER(ctypes.c_size_t),
    ]
    user32.SendMessageTimeoutW.restype = wintypes.LPARAM

    if args.exe:
        command = [str(args.exe.resolve())]
    else:
        command = [r"D:\Godot\4.7.2\godot.exe", "--path", str(project)]
    if args.scene:
        command.append(args.scene)
    if args.fullscreen:
        command.append("--fullscreen")

    records = []
    passed = True
    with (output / (label + ".log")).open("w", encoding="utf-8") as log:
        process = subprocess.Popen(
            command, cwd=project, stdout=log, stderr=log,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        try:
            hwnd = None
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and process.poll() is None:
                handles = []

                @callback_type
                def visit(handle, unused):
                    pid = wintypes.DWORD()
                    user32.GetWindowThreadProcessId(handle, ctypes.byref(pid))
                    if pid.value == process.pid and user32.IsWindowVisible(handle):
                        handles.append(handle)
                    return True

                user32.EnumWindows(visit, 0)
                if handles:
                    hwnd = handles[0]
                    break
                time.sleep(.1)
            if hwnd is None:
                raise RuntimeError("No game window within 10 seconds.")
            time.sleep(1.5)
            if args.intro:
                user32.PostMessageW(hwnd, 0x100, 0x0D, 0x001C0001)
                user32.PostMessageW(hwnd, 0x101, 0x0D, 0xC01C0001)
                time.sleep(1)

            steps = [("initial", None)]
            if not args.fullscreen:
                steps += [("maximized", 0xF030), ("restored", 0xF120)] * 2
            for index, (mode, code) in enumerate(steps):
                if code is not None:
                    user32.PostMessageW(hwnd, 0x112, code, 0)
                time.sleep(.7)
                result = ctypes.c_size_t()
                responsive = bool(user32.SendMessageTimeoutW(
                    hwnd, 0, 0, 0, 2, 1500, ctypes.byref(result),
                ))
                rect = wintypes.RECT()
                user32.GetWindowRect(hwnd, ctypes.byref(rect))
                maximized = bool(user32.IsZoomed(hwnd))
                mode_applied = code is None or maximized == (mode == "maximized")
                record = {
                    "step": index, "mode": mode, "responsive": responsive,
                    "mode_applied": mode_applied,
                    "rect": [rect.left, rect.top, rect.right, rect.bottom],
                }
                records.append(record)
                print(json.dumps(record), flush=True)
                if not responsive or not mode_applied:
                    passed = False
                    break
            user32.PostMessageW(hwnd, 0x10, 0, 0)
            try:
                process.wait(timeout=4)
                closed = True
            except subprocess.TimeoutExpired:
                closed = False
            record = {"normal_close": closed, "exit": process.poll()}
            records.append(record)
            print(json.dumps(record), flush=True)
            passed = passed and closed and process.returncode == 0
        except (OSError, RuntimeError) as error:
            passed = False
            records.append({"error": str(error)})
            print(str(error), file=sys.stderr)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            (output / (label + ".json")).write_text(
                json.dumps(records, indent=2), encoding="utf-8",
            )
    print("WINDOW_RESIZE_PASS=" + str(passed), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

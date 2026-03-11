import asyncio
import fcntl
import os
import pty
import re
import signal
import struct
import subprocess
import termios

# Auto-reap zombie child processes
signal.signal(signal.SIGCHLD, signal.SIG_IGN)

SESSION_NAME_RE = re.compile(r'^[a-zA-Z0-9_-]+$')


def validate_session_name(name: str) -> bool:
    return bool(SESSION_NAME_RE.match(name)) and len(name) <= 64


def list_tmux_sessions() -> list[dict]:
    try:
        result = subprocess.run(
            ["tmux", "list-sessions", "-F",
             "#{session_name}\t#{session_created}\t#{session_attached}\t#{session_activity}"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            return []
        sessions = []
        for line in result.stdout.strip().split('\n'):
            if not line.strip():
                continue
            parts = line.split('\t')
            if len(parts) >= 4:
                sessions.append({
                    "name": parts[0],
                    "created": int(parts[1]),
                    "attached": int(parts[2]),
                    "activity": int(parts[3]),
                })
        return sessions
    except Exception:
        return []


def create_tmux_session(name: str, command: str | None = None, cwd: str | None = None) -> bool:
    cmd = ["tmux", "new-session", "-d", "-s", name, "-x", "120", "-y", "36"]
    if command:
        # Unset CLAUDECODE to allow launching claude inside tmux
        # Keep session alive with bash fallback if command exits
        wrapped = f"unset CLAUDECODE; {command}; exec bash"
        cmd.append(wrapped)
    try:
        env = os.environ.copy()
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:" + env.get("PATH", "")
        env.pop("CLAUDECODE", None)
        work_dir = cwd or os.path.expanduser("~")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5, env=env, cwd=work_dir)
        return result.returncode == 0
    except Exception:
        return False


def kill_tmux_session(name: str) -> bool:
    try:
        result = subprocess.run(
            ["tmux", "kill-session", "-t", name],
            capture_output=True, text=True, timeout=5,
        )
        return result.returncode == 0
    except Exception:
        return False


def _set_winsize(fd: int, cols: int, rows: int):
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


async def bridge_websocket_to_tmux(websocket, session_name: str):
    """Bridge a WebSocket connection to a tmux session via PTY."""
    loop = asyncio.get_event_loop()

    # Fork a PTY and attach to the tmux session
    pid, fd = pty.fork()

    if pid == 0:
        # Child process: exec tmux attach
        os.environ["TERM"] = "xterm-256color"
        os.environ.pop("CLAUDECODE", None)
        os.execlp("tmux", "tmux", "attach-session", "-t", session_name)
        # If exec fails, exit
        os._exit(1)

    # Parent process: bridge fd <-> websocket
    # Set non-blocking on PTY fd
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    # Set initial size
    _set_winsize(fd, 120, 36)

    closed = False

    def on_pty_read():
        """Called when PTY has data to read."""
        nonlocal closed
        if closed:
            return
        try:
            data = os.read(fd, 65536)
            if data:
                asyncio.ensure_future(_send_bytes(websocket, data))
            else:
                # EOF
                asyncio.ensure_future(_close_ws(websocket))
        except OSError:
            if not closed:
                asyncio.ensure_future(_close_ws(websocket))

    async def _send_bytes(ws, data):
        try:
            await ws.send_bytes(data)
        except Exception:
            pass

    async def _close_ws(ws):
        try:
            await ws.close()
        except Exception:
            pass

    # Register PTY fd reader
    loop.add_reader(fd, on_pty_read)

    try:
        # Read from websocket, write to PTY
        while True:
            msg = await websocket.receive()

            if msg.get("type") == "websocket.disconnect":
                break

            if "text" in msg:
                text = msg["text"]
                # Check for resize message
                try:
                    import json
                    data = json.loads(text)
                    if isinstance(data, dict) and data.get("type") == "resize":
                        cols = int(data.get("cols", 120))
                        rows = int(data.get("rows", 36))
                        _set_winsize(fd, cols, rows)
                        # Send SIGWINCH to the child process group
                        try:
                            os.kill(pid, signal.SIGWINCH)
                        except ProcessLookupError:
                            pass
                        continue
                except (json.JSONDecodeError, ValueError):
                    pass
                # Regular text input
                try:
                    os.write(fd, text.encode())
                except OSError:
                    break

            elif "bytes" in msg:
                try:
                    os.write(fd, msg["bytes"])
                except OSError:
                    break

    except Exception:
        pass
    finally:
        closed = True
        # Cleanup
        try:
            loop.remove_reader(fd)
        except Exception:
            pass
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass

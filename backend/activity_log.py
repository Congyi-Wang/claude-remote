"""Live activity log — writes conversation events to a log file and stdout."""
import os
import sys
from datetime import datetime, timezone

LOG_PATH = os.getenv("ACTIVITY_LOG", "/home/claude-dev/.claude/claude-remote-activity.log")

def _ts():
    return datetime.now(timezone.utc).strftime("%H:%M:%S")

def _write(line: str):
    """Write to both stdout and log file."""
    print(line, flush=True)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def log_user_message(session_id: str, message: str):
    preview = message[:120].replace("\n", " ")
    _write(f"[{_ts()}] [{session_id[:8]}] USER: {preview}")

def log_assistant_chunk(session_id: str, text: str):
    # Only log first chunk (start of response)
    pass

def log_assistant_done(session_id: str, text: str, cost: float, duration_ms: int):
    preview = text[:120].replace("\n", " ")
    _write(f"[{_ts()}] [{session_id[:8]}] CLAUDE: {preview}")
    _write(f"[{_ts()}] [{session_id[:8]}]   cost=${cost:.4f} time={duration_ms}ms")

def log_error(session_id: str, error: str):
    _write(f"[{_ts()}] [{session_id[:8]}] ERROR: {error}")

def log_session_new(session_id: str):
    _write(f"[{_ts()}] [{session_id[:8]}] NEW SESSION: {session_id}")

def log_connect(session_id: str):
    _write(f"[{_ts()}] [{session_id[:8]}] CONNECTED")

def log_disconnect(session_id: str):
    _write(f"[{_ts()}] [{session_id[:8]}] DISCONNECTED")

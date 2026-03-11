import asyncio
import json
import uuid
import os
from typing import Optional

# Track active sessions: session_id -> process info
_active_sessions: dict[str, dict] = {}


async def send_message(session_id: str, message: str, on_chunk, on_done):
    """Send a message to claude CLI and stream the response via callbacks.

    on_chunk(text): called for each text chunk
    on_done(result): called when complete with full result dict
    """
    # Build command
    cmd = [
        "claude", "-p",
        "--output-format", "stream-json",
        "--resume", session_id,
        "--dangerously-skip-permissions",
        message
    ]

    env = os.environ.copy()
    env.pop("CLAUDECODE", None)  # Allow nested invocation

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
        )

        _active_sessions[session_id] = {"process": proc, "status": "running"}

        full_text = ""
        # Read stderr line by line (stream-json writes to stderr)
        async for line in proc.stderr:
            line_str = line.decode("utf-8", errors="replace").strip()
            if not line_str:
                continue
            try:
                data = json.loads(line_str)
            except json.JSONDecodeError:
                continue

            msg_type = data.get("type", "")

            if msg_type == "assistant":
                # Extract text content
                content = data.get("message", {}).get("content", [])
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        text = item.get("text", "")
                        if text:
                            full_text += text
                            await on_chunk(text)

            elif msg_type == "result":
                result = {
                    "session_id": data.get("session_id", session_id),
                    "text": data.get("result", full_text),
                    "cost_usd": data.get("total_cost_usd", 0),
                    "duration_ms": data.get("duration_ms", 0),
                    "usage": data.get("usage", {}),
                }
                await on_done(result)

        await proc.wait()

    except Exception as e:
        await on_done({"error": str(e), "session_id": session_id})
    finally:
        _active_sessions.pop(session_id, None)


def create_session_id() -> str:
    """Generate a new session ID."""
    return str(uuid.uuid4())


def get_active_sessions() -> list[str]:
    """Return list of currently active (running) session IDs."""
    return list(_active_sessions.keys())


async def stop_session(session_id: str) -> bool:
    """Stop a running session."""
    info = _active_sessions.get(session_id)
    if info and info.get("process"):
        try:
            info["process"].terminate()
            await asyncio.sleep(0.5)
            if info["process"].returncode is None:
                info["process"].kill()
        except Exception:
            pass
        _active_sessions.pop(session_id, None)
        return True
    return False

import asyncio
import json
import uuid
import os
import sys
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
        "--verbose",
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

        # Drain stderr in background to avoid deadlock and log errors
        async def _drain_stderr():
            async for line in proc.stderr:
                msg = line.decode("utf-8", errors="replace").strip()
                if msg:
                    print(f"[claude-cli stderr] {msg}", file=sys.stderr)
        stderr_task = asyncio.create_task(_drain_stderr())

        full_text = ""
        got_result = False
        # Read stdout line by line (stream-json with --verbose writes to stdout)
        async for line in proc.stdout:
            line_str = line.decode("utf-8", errors="replace").strip()
            if not line_str:
                continue
            try:
                data = json.loads(line_str)
            except json.JSONDecodeError:
                print(f"[claude-cli] non-json: {line_str[:200]}", file=sys.stderr)
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
                got_result = True
                result = {
                    "session_id": data.get("session_id", session_id),
                    "text": data.get("result", full_text),
                    "cost_usd": data.get("total_cost_usd", 0),
                    "duration_ms": data.get("duration_ms", 0),
                    "usage": data.get("usage", {}),
                }
                await on_done(result)

        await proc.wait()
        await stderr_task

        # If process ended without a result message, send error
        if not got_result:
            await on_done({"error": f"Claude process exited with code {proc.returncode}", "session_id": session_id})

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

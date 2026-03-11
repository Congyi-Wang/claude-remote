import asyncio
import json
import uuid
import os
import sys
from typing import Optional

# Track active sessions: session_id -> process info
_active_sessions: dict[str, dict] = {}


async def send_message(session_id: str, message: str, on_chunk, on_done, on_session_id=None):
    """Send a message to claude CLI and stream the response via callbacks."""
    # Always try --resume first (maintains conversation context)
    result = await _run_claude(session_id, message, on_chunk, on_done, on_session_id, use_resume=True)

    # If --resume failed with "No conversation found", retry as new session
    if result == "retry_without_resume":
        await _run_claude(session_id, message, on_chunk, on_done, on_session_id, use_resume=False)


async def _run_claude(session_id, message, on_chunk, on_done, on_session_id, use_resume):
    """Run claude CLI. Returns 'retry_without_resume' if resume fails."""
    cmd = [
        "claude", "-p",
        "--output-format", "stream-json",
        "--verbose",
        "--dangerously-skip-permissions",
    ]
    if use_resume:
        cmd.extend(["--resume", session_id])
    cmd.append(message)

    env = os.environ.copy()
    env.pop("CLAUDECODE", None)

    actual_session_id = session_id

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
        )

        _active_sessions[session_id] = {"process": proc, "status": "running"}

        async def _drain_stderr():
            async for line in proc.stderr:
                msg = line.decode("utf-8", errors="replace").strip()
                if msg:
                    print(f"[claude-cli stderr] {msg}", file=sys.stderr)
        stderr_task = asyncio.create_task(_drain_stderr())

        full_text = ""
        got_result = False

        async for line in proc.stdout:
            line_str = line.decode("utf-8", errors="replace").strip()
            if not line_str:
                continue
            try:
                data = json.loads(line_str)
            except json.JSONDecodeError:
                continue

            msg_type = data.get("type", "")

            if msg_type == "system":
                sid = data.get("session_id", "")
                if sid:
                    actual_session_id = sid
                    if sid != session_id:
                        _active_sessions.pop(session_id, None)
                        _active_sessions[sid] = {"process": proc, "status": "running"}
                        if on_session_id:
                            await on_session_id(sid)

            elif msg_type == "assistant":
                content = data.get("message", {}).get("content", [])
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        text = item.get("text", "")
                        if text:
                            full_text += text
                            await on_chunk(text)

            elif msg_type == "result":
                got_result = True
                if data.get("is_error"):
                    errors = data.get("errors", [])
                    error_msg = "; ".join(errors) if errors else "Unknown error"
                    if use_resume and "No conversation found" in error_msg:
                        await proc.wait()
                        await stderr_task
                        _active_sessions.pop(session_id, None)
                        return "retry_without_resume"
                    await on_done({"error": error_msg, "session_id": actual_session_id})
                else:
                    result = {
                        "session_id": data.get("session_id", actual_session_id),
                        "text": data.get("result", full_text),
                        "cost_usd": data.get("total_cost_usd", 0),
                        "duration_ms": data.get("duration_ms", 0),
                        "usage": data.get("usage", {}),
                    }
                    await on_done(result)

        await proc.wait()
        await stderr_task

        if not got_result:
            await on_done({"error": f"Claude exited with code {proc.returncode}", "session_id": actual_session_id})

    except Exception as e:
        await on_done({"error": str(e), "session_id": session_id})
    finally:
        _active_sessions.pop(session_id, None)
        if actual_session_id != session_id:
            _active_sessions.pop(actual_session_id, None)

    return None


def create_session_id() -> str:
    return str(uuid.uuid4())


def get_active_sessions() -> list[str]:
    return list(_active_sessions.keys())


async def stop_session(session_id: str) -> bool:
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

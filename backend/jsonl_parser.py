import json
import os
from typing import Optional

PROJECTS_DIR = os.getenv("CLAUDE_PROJECTS_DIR", "/home/claude-dev/.claude/projects/-home-claude-dev")


def list_session_files() -> list[dict]:
    """List all JSONL session files with basic metadata."""
    sessions = []
    if not os.path.isdir(PROJECTS_DIR):
        return sessions
    for fname in os.listdir(PROJECTS_DIR):
        if not fname.endswith(".jsonl"):
            continue
        session_id = fname.replace(".jsonl", "")
        fpath = os.path.join(PROJECTS_DIR, fname)
        try:
            meta = _extract_session_meta(fpath, session_id)
            if meta:
                sessions.append(meta)
        except Exception:
            continue
    sessions.sort(key=lambda s: s.get("updated_at", ""), reverse=True)
    return sessions


def _extract_session_meta(fpath: str, session_id: str) -> Optional[dict]:
    """Extract metadata from a session JSONL file."""
    slug = ""
    first_user_text = ""
    last_timestamp = ""
    msg_count = 0
    with open(fpath, "r") as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = d.get("type", "")
            if t == "user":
                msg_count += 1
                if not first_user_text:
                    content = d.get("message", {}).get("content", [])
                    first_user_text = _extract_text(content)
                if not slug:
                    slug = d.get("slug", "")
            elif t == "assistant":
                msg_count += 1
            ts = d.get("timestamp", "")
            if ts:
                last_timestamp = ts
    if msg_count == 0:
        return None
    title = first_user_text[:80] if first_user_text else slug or session_id[:8]
    return {
        "id": session_id,
        "title": title,
        "slug": slug,
        "message_count": msg_count,
        "updated_at": last_timestamp,
    }


def get_session_messages(session_id: str) -> list[dict]:
    """Parse messages from a session JSONL file."""
    fpath = os.path.join(PROJECTS_DIR, f"{session_id}.jsonl")
    if not os.path.exists(fpath):
        return []
    messages = []
    with open(fpath, "r") as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = d.get("type", "")
            if t == "user":
                content = d.get("message", {}).get("content", [])
                text = _extract_text(content)
                if text and "[Request interrupted" not in text:
                    messages.append({
                        "role": "user",
                        "text": text,
                        "timestamp": d.get("timestamp", ""),
                    })
            elif t == "assistant":
                content = d.get("message", {}).get("content", [])
                text = _extract_text(content)
                if text:
                    messages.append({
                        "role": "assistant",
                        "text": text,
                        "timestamp": d.get("timestamp", ""),
                    })
    return messages


def get_usage_stats() -> dict:
    """Aggregate token usage across all sessions."""
    total_input = 0
    total_output = 0
    total_cache_read = 0
    total_cache_create = 0
    total_cost = 0.0
    session_count = 0

    if not os.path.isdir(PROJECTS_DIR):
        return {"sessions": 0, "input_tokens": 0, "output_tokens": 0, "cost_usd": 0.0}

    for fname in os.listdir(PROJECTS_DIR):
        if not fname.endswith(".jsonl"):
            continue
        fpath = os.path.join(PROJECTS_DIR, fname)
        session_had_usage = False
        try:
            with open(fpath, "r") as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if d.get("type") == "assistant":
                        usage = d.get("message", {}).get("usage", {})
                        if usage:
                            session_had_usage = True
                            total_input += usage.get("input_tokens", 0)
                            total_output += usage.get("output_tokens", 0)
                            total_cache_read += usage.get("cache_read_input_tokens", 0)
                            total_cache_create += usage.get("cache_creation_input_tokens", 0)
                    # Also check result type for cost
                    if d.get("type") == "result":
                        total_cost += d.get("total_cost_usd", 0.0)
        except Exception:
            continue
        if session_had_usage:
            session_count += 1

    return {
        "sessions": session_count,
        "input_tokens": total_input,
        "output_tokens": total_output,
        "cache_read_tokens": total_cache_read,
        "cache_creation_tokens": total_cache_create,
        "cost_usd": round(total_cost, 4),
    }


def _extract_text(content) -> str:
    """Extract text from message content (list or string)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    return ""

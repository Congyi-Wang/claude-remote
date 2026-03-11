import json
from fastapi import APIRouter, HTTPException, Depends, WebSocket, WebSocketDisconnect, Query
from auth import verify_token
from jsonl_parser import list_session_files, get_session_messages
from session_manager import send_message, create_session_id, get_active_sessions, stop_session

router = APIRouter(prefix="/api/sessions", tags=["sessions"])


def _check_auth(authorization: str = "") -> bool:
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing token")
    token = authorization.replace("Bearer ", "")
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    return True


@router.get("/")
async def list_sessions(authorization: str = Query(default="", alias="token")):
    """List all known sessions from JSONL files."""
    if authorization:
        token = authorization.replace("Bearer ", "")
        if not verify_token(token):
            raise HTTPException(status_code=401, detail="Invalid token")
    active = get_active_sessions()
    sessions = list_session_files()
    for s in sessions:
        s["active"] = s["id"] in active
    return {"sessions": sessions}


@router.get("/{session_id}/messages")
async def get_messages(session_id: str, token: str = ""):
    if token and not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    messages = get_session_messages(session_id)
    return {"messages": messages}


@router.delete("/{session_id}")
async def delete_session(session_id: str, token: str = ""):
    if token and not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    stopped = await stop_session(session_id)
    return {"stopped": stopped, "session_id": session_id}


@router.websocket("/ws/{session_id}")
async def websocket_chat(websocket: WebSocket, session_id: str):
    await websocket.accept()

    # First message should be auth token
    try:
        auth_msg = await websocket.receive_text()
        auth_data = json.loads(auth_msg)
        token = auth_data.get("token", "")
        if not verify_token(token):
            await websocket.send_json({"type": "error", "text": "Invalid token"})
            await websocket.close()
            return
        await websocket.send_json({"type": "auth_ok"})
    except Exception:
        await websocket.close()
        return

    # For "new" sessions, use a placeholder; real ID comes from Claude
    is_new = session_id == "new"
    if is_new:
        session_id = create_session_id()

    try:
        while True:
            # Wait for user message
            msg_text = await websocket.receive_text()
            msg_data = json.loads(msg_text)
            user_message = msg_data.get("message", "")

            if not user_message:
                await websocket.send_json({"type": "error", "text": "Empty message"})
                continue

            await websocket.send_json({"type": "status", "text": "thinking"})

            async def on_chunk(text):
                await websocket.send_json({"type": "chunk", "text": text})

            async def on_done(result):
                await websocket.send_json({"type": "done", **result})

            async def on_session_id(new_id):
                nonlocal session_id
                session_id = new_id
                await websocket.send_json({"type": "session_id", "session_id": new_id})

            await send_message(session_id, user_message, on_chunk, on_done,
                             on_session_id=on_session_id if is_new else None)
            # After first message, session exists in Claude
            is_new = False

    except WebSocketDisconnect:
        pass
    except Exception:
        try:
            await websocket.close()
        except Exception:
            pass

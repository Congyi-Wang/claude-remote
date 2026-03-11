import json
import asyncio
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect, Query
from auth import verify_token
from jsonl_parser import list_session_files, get_session_messages
from session_manager import send_message, create_session_id, get_active_sessions, stop_session
import activity_log

router = APIRouter(prefix="/api/sessions", tags=["sessions"])

PING_INTERVAL = 20  # seconds


@router.get("/")
async def list_sessions(authorization: str = Query(default="", alias="token")):
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

    # Auth
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

    if session_id == "new":
        session_id = create_session_id()

    activity_log.log_connect(session_id)

    # Keepalive ping task
    ping_active = True

    async def _ping_loop():
        while ping_active:
            await asyncio.sleep(PING_INTERVAL)
            if not ping_active:
                break
            try:
                await websocket.send_json({"type": "ping"})
            except Exception:
                break

    ping_task = asyncio.create_task(_ping_loop())

    try:
        while True:
            msg_text = await websocket.receive_text()
            msg_data = json.loads(msg_text)

            if msg_data.get("type") == "pong":
                continue

            user_message = msg_data.get("message", "")
            if not user_message:
                await websocket.send_json({"type": "error", "text": "Empty message"})
                continue

            activity_log.log_user_message(session_id, user_message)
            await websocket.send_json({"type": "status", "text": "thinking"})

            async def on_event(event):
                """Forward structured events to the client."""
                await websocket.send_json(event)

            async def on_done(result):
                error = result.get("error")
                if error:
                    activity_log.log_error(session_id, error)
                else:
                    activity_log.log_assistant_done(
                        result.get("session_id", session_id),
                        result.get("text", ""),
                        result.get("cost_usd", 0),
                        result.get("duration_ms", 0),
                    )
                await websocket.send_json({"type": "done", **result})

            async def on_session_id(new_id):
                nonlocal session_id
                activity_log.log_session_new(new_id)
                session_id = new_id
                await websocket.send_json({"type": "session_id", "session_id": new_id})

            await send_message(session_id, user_message, on_event, on_done,
                             on_session_id=on_session_id)

    except WebSocketDisconnect:
        activity_log.log_disconnect(session_id)
    except Exception:
        activity_log.log_disconnect(session_id)
        try:
            await websocket.close()
        except Exception:
            pass
    finally:
        ping_active = False
        ping_task.cancel()

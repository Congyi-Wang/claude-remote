from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect, Query
from pydantic import BaseModel
from auth import verify_token
from terminal_manager import (
    list_tmux_sessions,
    create_tmux_session,
    kill_tmux_session,
    validate_session_name,
    bridge_websocket_to_tmux,
)

router = APIRouter(prefix="/api/terminals", tags=["terminals"])


class CreateSessionRequest(BaseModel):
    name: str
    command: str | None = None


@router.get("/")
async def list_sessions(token: str = ""):
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    return {"sessions": list_tmux_sessions()}


@router.post("/")
async def create_session(req: CreateSessionRequest, token: str = ""):
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    if not validate_session_name(req.name):
        raise HTTPException(status_code=400, detail="Invalid session name. Use only letters, numbers, _ and -")
    if not create_tmux_session(req.name, req.command):
        raise HTTPException(status_code=500, detail="Failed to create session (may already exist)")
    return {"status": "created", "name": req.name}


@router.delete("/{name}")
async def delete_session(name: str, token: str = ""):
    if not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    if not validate_session_name(name):
        raise HTTPException(status_code=400, detail="Invalid session name")
    if not kill_tmux_session(name):
        raise HTTPException(status_code=404, detail="Session not found")
    return {"status": "deleted", "name": name}


@router.websocket("/ws/{name}")
async def terminal_websocket(websocket: WebSocket, name: str, token: str = ""):
    if not verify_token(token):
        await websocket.close(code=4001, reason="Unauthorized")
        return
    if not validate_session_name(name):
        await websocket.close(code=4002, reason="Invalid session name")
        return

    await websocket.accept()

    try:
        await bridge_websocket_to_tmux(websocket, name)
    except WebSocketDisconnect:
        pass
    except Exception:
        try:
            await websocket.close()
        except Exception:
            pass

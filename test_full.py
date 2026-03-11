#!/usr/bin/env python3
"""Full integration test simulating phone app behavior."""
import asyncio
import json
import sys
import time
import requests
import websockets

BASE = "http://127.0.0.1:8090"
WS_BASE = "ws://127.0.0.1:8090"
PIN = "000427"

passed = 0
failed = 0

def check(name, condition, detail=""):
    global passed, failed
    if condition:
        print(f"  PASS  {name}")
        passed += 1
    else:
        print(f"  FAIL  {name}  {detail}")
        failed += 1
    return condition


async def ws_send_and_recv(ws, message, timeout=120):
    """Send a message and collect all response events."""
    await ws.send(json.dumps({"message": message}))
    events = []
    text = ""
    session_id = None
    while True:
        try:
            r = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        except asyncio.TimeoutError:
            events.append({"type": "timeout"})
            break
        t = r.get("type")
        events.append(r)
        if t == "ping":
            await ws.send(json.dumps({"type": "pong"}))
        elif t == "session_id":
            session_id = r["session_id"]
        elif t == "chunk":
            text += r.get("text", "")
        elif t in ("done", "error"):
            break
    return {"events": events, "text": text, "session_id": session_id,
            "error": events[-1].get("error") if events else None}


async def ws_connect(uri, token):
    """Connect and authenticate. Returns (ws, auth_ok)."""
    ws = await websockets.connect(uri, ping_interval=None, ping_timeout=None)
    await ws.send(json.dumps({"token": token}))
    r = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
    return ws, r.get("type") == "auth_ok"


def get_token():
    r = requests.post(f"{BASE}/api/auth/login", json={"pin": PIN})
    return r.json().get("token", "")


async def test_new_session(token):
    """Test 1: Create new session and send message."""
    print("\n[Test 1: New session]")
    ws, ok = await ws_connect(f"{WS_BASE}/api/sessions/ws/new", token)
    check("WS connect + auth", ok)
    
    result = await ws_send_and_recv(ws, "Say exactly: HELLO_TEST_1")
    check("Got response", len(result["text"]) > 0, f"text='{result['text']}'")
    check("No error", result["error"] is None, f"error={result['error']}")
    check("Got session ID", result["session_id"] is not None)
    
    sid = result["session_id"]
    await ws.close()
    return sid


async def test_resume_same_connection(token):
    """Test 2: Send two messages in same connection, verify context."""
    print("\n[Test 2: Context in same connection]")
    ws, ok = await ws_connect(f"{WS_BASE}/api/sessions/ws/new", token)
    check("WS connect", ok)
    
    r1 = await ws_send_and_recv(ws, "The secret code is MANGO_42. Just say OK.")
    check("First message OK", "error" not in r1["events"][-1] or r1["error"] is None)
    sid = r1["session_id"]
    
    r2 = await ws_send_and_recv(ws, "What is the secret code?")
    check("Second message OK", r2["error"] is None)
    has_code = "MANGO_42" in r2["text"] or "mango_42" in r2["text"].lower() or "MANGO" in r2["text"]
    check("Context maintained (same conn)", has_code, f"text='{r2['text'][:100]}'")
    
    await ws.close()
    return sid


async def test_resume_after_reconnect(token, session_id):
    """Test 3: Reconnect to session from test 2, verify context persists."""
    print("\n[Test 3: Context after reconnect]")
    ws, ok = await ws_connect(f"{WS_BASE}/api/sessions/ws/{session_id}", token)
    check("WS reconnect", ok)
    
    result = await ws_send_and_recv(ws, "What was the secret code I told you earlier?")
    check("Got response", len(result["text"]) > 0)
    check("No error", result["error"] is None, f"error={result['error']}")
    has_code = "MANGO" in result["text"].upper()
    check("Context maintained (after reconnect)", has_code, f"text='{result['text'][:100]}'")
    
    await ws.close()


async def test_resume_host_session(token):
    """Test 4: Open a host-created session (should auto-retry)."""
    print("\n[Test 4: Host-created session fallback]")
    # Find a session that was created by the host, not by our container
    r = requests.get(f"{BASE}/api/sessions/?token={token}")
    sessions = r.json().get("sessions", [])
    
    if not sessions:
        print("  SKIP  No sessions available")
        return
    
    # Pick first session
    sid = sessions[0]["id"]
    ws, ok = await ws_connect(f"{WS_BASE}/api/sessions/ws/{sid}", token)
    check("WS connect to existing session", ok)
    
    result = await ws_send_and_recv(ws, "Say exactly: FALLBACK_OK")
    check("Got response (may be new session)", len(result["text"]) > 0, f"text='{result['text']}'")
    check("No error", result["error"] is None, f"error={result['error']}")
    
    await ws.close()


async def test_ping_keepalive(token):
    """Test 5: Verify ping/pong keepalive works."""
    print("\n[Test 5: Ping keepalive]")
    ws, ok = await ws_connect(f"{WS_BASE}/api/sessions/ws/new", token)
    check("WS connect", ok)
    
    # Wait for at least one ping (server sends every 20s)
    got_ping = False
    start = time.time()
    while time.time() - start < 25:
        try:
            r = json.loads(await asyncio.wait_for(ws.recv(), timeout=25))
            if r.get("type") == "ping":
                got_ping = True
                await ws.send(json.dumps({"type": "pong"}))
                break
        except asyncio.TimeoutError:
            break
    
    check("Received server ping within 25s", got_ping)
    check("Connection still alive after ping", not ws.close_code)
    
    await ws.close()


async def test_rapid_reconnect(token, session_id):
    """Test 6: Rapid disconnect/reconnect (simulates app switching)."""
    print("\n[Test 6: Rapid reconnect stability]")
    success = 0
    for i in range(3):
        try:
            ws, ok = await ws_connect(f"{WS_BASE}/api/sessions/ws/{session_id}", token)
            if ok:
                success += 1
            await ws.close()
            await asyncio.sleep(0.5)
        except Exception as e:
            print(f"    Attempt {i+1} failed: {e}")
    
    check("3/3 rapid reconnects succeed", success == 3, f"got {success}/3")


async def test_via_nginx(token):
    """Test 7: Test through nginx proxy (like the real phone app)."""
    print("\n[Test 7: Through nginx proxy]")
    try:
        ws, ok = await ws_connect("ws://46.224.150.45/claude-remote/api/sessions/ws/new", token)
        check("WS connect via nginx", ok)
        
        result = await ws_send_and_recv(ws, "Say exactly: NGINX_OK")
        check("Response via nginx", len(result["text"]) > 0, f"text='{result['text']}'")
        check("No error via nginx", result["error"] is None, f"error={result['error']}")
        
        await ws.close()
    except Exception as e:
        check("Nginx WebSocket reachable", False, str(e))


async def main():
    print("=== Claude Remote Full Test Suite ===")
    
    token = get_token()
    if not token:
        print("ABORT: No token")
        sys.exit(1)
    print(f"Token acquired: {token[:20]}...")
    
    # Test 1: New session
    sid1 = await test_new_session(token)
    
    # Test 2: Context in same connection
    sid2 = await test_resume_same_connection(token)
    
    # Test 3: Context after reconnect
    if sid2:
        await test_resume_after_reconnect(token, sid2)
    
    # Test 4: Host-created session
    await test_resume_host_session(token)
    
    # Test 5: Ping keepalive
    await test_ping_keepalive(token)
    
    # Test 6: Rapid reconnect
    if sid1:
        await test_rapid_reconnect(token, sid1)
    
    # Test 7: Through nginx
    await test_via_nginx(token)
    
    print(f"\n=== Results: {passed} passed, {failed} failed ===")
    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    asyncio.run(main())

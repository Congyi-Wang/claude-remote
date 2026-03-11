#!/usr/bin/env python3
"""Backend integration test - run after docker compose up to verify everything works."""
import asyncio
import json
import sys
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
        print(f"  FAIL  {name} {detail}")
        failed += 1


def test_health():
    r = requests.get(f"{BASE}/api/health")
    check("Health endpoint", r.status_code == 200, f"status={r.status_code}")


def test_auth():
    # Wrong PIN
    r = requests.post(f"{BASE}/api/auth/login", json={"pin": "000000"})
    check("Reject wrong PIN", r.status_code == 401)

    # Correct PIN
    r = requests.post(f"{BASE}/api/auth/login", json={"pin": PIN})
    check("Accept correct PIN", r.status_code == 200)
    data = r.json()
    check("Returns token", "token" in data)
    return data.get("token", "")


def test_sessions(token):
    r = requests.get(f"{BASE}/api/sessions/?token={token}")
    check("List sessions", r.status_code == 200)
    data = r.json()
    check("Sessions is list", isinstance(data.get("sessions"), list))


async def test_websocket_chat(token):
    uri = f"{WS_BASE}/api/sessions/ws/new"
    async with websockets.connect(uri) as ws:
        # Auth
        await ws.send(json.dumps({"token": token}))
        r = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        check("WS auth OK", r.get("type") == "auth_ok", f"got {r}")

        # Send message
        await ws.send(json.dumps({"message": "respond with exactly: TEST_OK"}))

        got_session = False
        got_chunk = False
        got_done = False
        response_text = ""

        while True:
            try:
                r = json.loads(await asyncio.wait_for(ws.recv(), timeout=120))
                t = r.get("type")
                if t == "session_id":
                    got_session = True
                elif t == "chunk":
                    got_chunk = True
                    response_text += r.get("text", "")
                elif t == "done":
                    got_done = True
                    if not response_text:
                        response_text = r.get("text", "")
                    break
                elif t == "error":
                    check("No WS error", False, f"error: {r.get('text')}")
                    return
            except asyncio.TimeoutError:
                check("Response within timeout", False, "120s timeout")
                return

        check("Got session ID (new session)", got_session)
        check("Got streaming chunks", got_chunk)
        check("Got done message", got_done)
        check("Response not empty", len(response_text) > 0, f"text='{response_text}'")
        check("No error in done", r.get("error") is None, f"error={r.get('error')}")


def main():
    print("=== Claude Remote Backend Tests ===\n")

    print("[Health]")
    test_health()

    print("\n[Auth]")
    token = test_auth()
    if not token:
        print("ABORT: No token")
        sys.exit(1)

    print("\n[Sessions]")
    test_sessions(token)

    print("\n[WebSocket Chat]")
    asyncio.run(test_websocket_chat(token))

    print(f"\n=== Results: {passed} passed, {failed} failed ===")
    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()

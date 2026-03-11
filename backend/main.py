from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from routers import auth, sessions, usage, terminals
import os

app = FastAPI(title="Claude Remote", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(sessions.router)
app.include_router(usage.router)
app.include_router(terminals.router)

# Serve static files
static_dir = os.path.join(os.path.dirname(__file__), "static")
app.mount("/static", StaticFiles(directory=static_dir), name="static")


@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "claude-remote", "version": "2.0.0"}


@app.get("/api/terminals/{name}/page")
async def terminal_page(name: str):
    return FileResponse(os.path.join(static_dir, "terminal.html"), media_type="text/html")

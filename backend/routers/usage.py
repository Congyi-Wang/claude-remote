from fastapi import APIRouter, Query, HTTPException
from auth import verify_token
from jsonl_parser import get_usage_stats

router = APIRouter(prefix="/api/usage", tags=["usage"])


@router.get("/")
async def usage(token: str = ""):
    if token and not verify_token(token):
        raise HTTPException(status_code=401, detail="Invalid token")
    return get_usage_stats()

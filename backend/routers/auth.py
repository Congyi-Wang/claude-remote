from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from auth import verify_pin, create_token

router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginRequest(BaseModel):
    pin: str


class LoginResponse(BaseModel):
    token: str


@router.post("/login", response_model=LoginResponse)
async def login(req: LoginRequest):
    if not verify_pin(req.pin):
        raise HTTPException(status_code=401, detail="Invalid PIN")
    return LoginResponse(token=create_token())

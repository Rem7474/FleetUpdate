from typing import Any, Dict, List, Optional
from pydantic import BaseModel


class Heartbeat(BaseModel):
    agent_id: str
    apps: Dict[str, Dict[str, Any]]
    logs: Optional[List[str]] = None


class CommandRequest(BaseModel):
    command: str
    app: str
    commands: List[str]
    command_id: str
    timeout: int = 600


class CommandResult(BaseModel):
    command_id: str
    status: str
    new_state: Optional[str] = None
    output: Optional[List[str]] = None
    duration: Optional[int] = None
    logs: Optional[str] = None

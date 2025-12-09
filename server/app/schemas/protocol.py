from typing import Any, Dict, List, Optional
from pydantic import BaseModel
from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field


class HeartbeatApp(BaseModel):
    model_config = ConfigDict(extra='ignore')
    type: Optional[str] = None
    branch: Optional[str] = None
    current: Optional[str] = None
    health: Optional[str] = None
    status: Optional[str] = None
    services: Optional[Dict[str, Any]] = None


class HeartbeatPayload(BaseModel):
    model_config = ConfigDict(extra='ignore')
    agent_id: str
    apps: Dict[str, HeartbeatApp] = Field(default_factory=dict)
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


class CommandChunk(BaseModel):
    command_id: str
    chunk: str

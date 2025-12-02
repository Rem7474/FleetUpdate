from datetime import datetime
from typing import Optional
from sqlmodel import SQLModel, Field


class Agent(SQLModel, table=True):
    id: str = Field(primary_key=True)
    last_seen: datetime = Field(default_factory=datetime.utcnow)
    status: str = Field(default="online")
    apps_state: Optional[str] = None  # JSON string of apps state snapshot
    psk_hash: Optional[str] = None
    os_update: Optional[str] = None  # JSON string of OS update status


class Deployment(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    agent_id: str
    app_name: str
    status: str
    started_at: datetime = Field(default_factory=datetime.utcnow)
    finished_at: Optional[datetime] = None
    logs: Optional[str] = None


class DesiredState(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    agent_id: str
    app_name: str
    desired: str  # JSON specification of desired version/state
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class Command(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    command_id: str
    agent_id: str
    payload: str  # JSON payload (e.g., commands)
    status: str = Field(default="pending")  # pending|running|success|failed
    output: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

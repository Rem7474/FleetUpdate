from sqlmodel import SQLModel, create_engine
from . import models  # noqa: F401
from ..config import settings


engine = create_engine(settings.database_url, echo=False)


def init_db() -> None:
    SQLModel.metadata.create_all(engine)

from pydantic import BaseModel
import os


class Settings(BaseModel):
    database_url: str = os.getenv("DATABASE_URL", "sqlite:///" + os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "db.sqlite3")))
    cors_origins: list[str] = os.getenv("CORS_ORIGINS", "http://localhost:5173").split(",")
    server_psk: str = os.getenv("SERVER_PSK", "")
    # UI auth (single user)
    ui_user: str = os.getenv("UI_USER", "")
    ui_password: str = os.getenv("UI_PASSWORD", "")
    ui_password_hash: str | None = os.getenv("UI_PASSWORD_HASH")
    jwt_secret: str = os.getenv("JWT_SECRET", "")


settings = Settings()

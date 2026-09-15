from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class UserCreate(BaseModel):
    login: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=4, max_length=128)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    login: str
    created_at: datetime

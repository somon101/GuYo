"""The avatar a person builds from parts (hair, face, clothes, ...), instead of uploading a photo.

The parts come from the Avatar Studio program (file format "avatar-items/1"): every part keeps the
unique ID it has in the Studio, its slot, which gender it is for, its picture and where it sits for
each gender (x, y, width, rotation, anchor). The person places nothing by hand: a chosen part is
drawn at ITS OWN saved place."""

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class AvatarItem(Base):
    __tablename__ = "avatar_items"

    # The Studio's own ID, kept as is, so uploading the same file again updates the part instead of duplicating it.
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    slot: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    gender: Mapped[str] = mapped_column(String(8), nullable=False)  # male | female | both
    name: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    set_id: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    set_name: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    image_key: Mapped[str] = mapped_column(String(500), nullable=False)
    image_hash: Mapped[str] = mapped_column(String(40), nullable=False, default="")
    width: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    height: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # {"male": {x, y, w, r, pivot}, "female": {...}} -- only the genders the part is for.
    place: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    own_place: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Goes up each time the part's picture or place changes, so phones know to fetch it again.
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    sort: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class AvatarBackground(Base):
    __tablename__ = "avatar_backgrounds"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    kind: Mapped[str] = mapped_column(String(8), nullable=False)  # solid | grad | img
    c1: Mapped[str | None] = mapped_column(String(16), nullable=True)
    c2: Mapped[str | None] = mapped_column(String(16), nullable=True)
    image_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    image_hash: Mapped[str] = mapped_column(String(40), nullable=False, default="")
    width: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    height: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    place: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # {x, y, s} for a picture
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    sort: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class AvatarMeta(Base):
    """One row (id 1): what is common to the whole catalog."""

    __tablename__ = "avatar_meta"

    id: Mapped[int] = mapped_column(primary_key=True)
    canvas: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)  # {"w": 1200, "h": 1600}
    frame: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # which square of the canvas becomes the picture
    slots: Mapped[list] = mapped_column(JSON, nullable=False, default=list)  # [{"id", "name"}] in drawing order
    # Goes up on every upload that changed anything; the app compares it to its own copy.
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

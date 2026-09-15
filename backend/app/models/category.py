from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Category(Base):
    """A named grouping of Words within one Dictionary (e.g. "Еда", "Семья").

    Scoped to a dictionary rather than global: categories organize the
    words of one language/block, and two different dictionaries are free to
    have their own "Еда" without colliding (enforced by the unique
    constraint being per-dictionary, not global)."""

    __tablename__ = "categories"
    __table_args__ = (UniqueConstraint("dictionary_id", "name", name="uq_category_dictionary_name"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    dictionary: Mapped["Dictionary"] = relationship()
    words: Mapped[list["Word"]] = relationship(back_populates="category")

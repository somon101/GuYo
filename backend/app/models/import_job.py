from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ImportJob(Base):
    """One dictionary ZIP import, tracked on the server rather than only in
    the admin's browser tab. A slow upload/merge (large ZIP, many audio
    files) keeps running here regardless of whether the admin navigates
    away, closes the tab, or comes back later -- Admin Web only ever polls
    this row by `id` (the job_id handed back when the import was started)
    for the current state, never holds the operation itself.

    `status` is a plain string ("pending" -> "processing" -> "completed" or
    "failed") rather than a DB enum, matching this project's convention for
    values that might grow later without a migration."""

    __tablename__ = "import_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    dictionary_id: Mapped[int] = mapped_column(
        ForeignKey("dictionaries.id", ondelete="CASCADE"), nullable=False, index=True
    )

    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    # Set only when status == "failed" -- a specific, human-readable reason
    # (which word/category/path, or which JSON field), never a generic
    # "invalid format" message.
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Set only when status == "completed" -- mirrors ImportSummary.
    categories_created: Mapped[int | None] = mapped_column(Integer, nullable=True)
    categories_reused: Mapped[int | None] = mapped_column(Integer, nullable=True)
    words_created: Mapped[int | None] = mapped_column(Integer, nullable=True)
    words_reused: Mapped[int | None] = mapped_column(Integer, nullable=True)
    forms_added: Mapped[int | None] = mapped_column(Integer, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

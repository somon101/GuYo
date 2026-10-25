"""Catalog of picture-based frames, badges and titles; the old fixed looks go.

Revision ID: b5c7d9e1f3a4
Revises: a4b6c8d0e2f3
"""
import sqlalchemy as sa
from alembic import op

revision = "b5c7d9e1f3a4"
down_revision = "a4b6c8d0e2f3"
branch_labels = None
depends_on = None

SEED = (
    ("frame", "Кристальное кольцо", "Ҳалқаи булӯрӣ", "Kristal halqa", "builtin/frame_crystal.png"),
    ("badge", "Кристальная звезда", "Ситораи булӯрӣ", "Kristal yulduz", "builtin/badge_crystal.png"),
    ("title", "Хранитель кристалла", "Нигаҳбони булӯр", "Kristal qo‘riqchisi", "builtin/title_crystal.png"),
)


def _remap(definition: dict, ids: dict[str, int]) -> dict:
    """Old frame/badge/title rewards now point at the new catalog items."""
    seen = set()

    def fix(reward, level, lane):
        if not isinstance(reward, dict) or reward.get("type") not in ("frame", "badge", "title"):
            return reward
        kind = reward["type"]
        if kind == "badge" and level == 20 and lane == "premium":
            kind = "frame"  # the old diamond badge here becomes the season's frame
        seen.add(kind)
        return {"type": kind, "amount": 1, "key": str(ids[kind]), "text": ""}

    for lv in definition.get("levels", []):
        for lane in ("free", "premium"):
            lv[lane] = fix(lv.get(lane), lv.get("level"), lane)
    for g in list(definition.get("team_goals") or []) + [definition.get("team_season_goal")]:
        if isinstance(g, dict):
            g["reward"] = fix(g.get("reward"), None, "team")
    levels = definition.get("levels", [])
    if "frame" not in seen and len(levels) >= 20:
        levels[19]["premium"] = {"type": "frame", "amount": 1, "key": str(ids["frame"]), "text": ""}
    return definition


def upgrade() -> None:
    bind = op.get_bind()
    defs = op.create_table(
        "cosmetic_defs",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("kind", sa.String(8), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("name_tg", sa.String(120), nullable=True),
        sa.Column("name_uz", sa.String(120), nullable=True),
        sa.Column("image_key", sa.String(500), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    ids: dict[str, int] = {}
    for kind, name, tg, uz, key in SEED:
        res = bind.execute(
            sa.text("INSERT INTO cosmetic_defs (kind, name, name_tg, name_uz, image_key) VALUES (:k, :n, :t, :u, :i) RETURNING id"),
            {"k": kind, "n": name, "t": tg, "u": uz, "i": key},
        )
        ids[kind] = res.scalar()

    # The old fixed looks are gone for everyone.
    bind.execute(sa.text("DELETE FROM user_cosmetics WHERE kind IN ('frame', 'badge') AND key !~ '^[0-9]+$'"))
    bind.execute(sa.text("UPDATE users SET equipped_badge_id = NULL WHERE equipped_badge_id IS NOT NULL AND equipped_badge_id NOT IN (SELECT id FROM user_cosmetics)"))
    bind.execute(sa.text("UPDATE users SET equipped_frame_id = NULL WHERE equipped_frame_id IS NOT NULL AND equipped_frame_id NOT IN (SELECT id FROM user_cosmetics)"))

    for table in ("pass_templates", "season_passes"):
        t = sa.table(table, sa.column("id", sa.Integer), sa.column("definition", sa.JSON))
        for row in bind.execute(sa.select(t.c.id, t.c.definition)).all():
            definition = row.definition if isinstance(row.definition, dict) else None
            if definition:
                bind.execute(sa.update(t).where(t.c.id == row.id).values(definition=_remap(definition, ids)))


def downgrade() -> None:
    op.drop_table("cosmetic_defs")

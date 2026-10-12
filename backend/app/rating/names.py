"""A season's name in the app's interface language (not the translation
language): Russian `name`, or `name_tg` / `name_uz` when filled."""

from app.core.content_language import ui_language
from app.models.rating import Season


def season_name(season: Season) -> str:
    lang = ui_language()
    localized = season.name_tg if lang == "tg" else season.name_uz if lang == "uz" else None
    return (localized or "").strip() or season.name

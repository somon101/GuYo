"""The fixed catalog an admin picks an Achievement's icon from -- plain
identifiers only, never free-text HTML/SVG. The Flutter client maps each id
to its own icon widget; Admin Web maps it to the same one for the picker
and preview. Adding a new icon later is one more entry here, both sides
updated together.
"""

ACHIEVEMENT_ICONS: dict[str, str] = {
    "trophy": "🏆",
    "star": "⭐",
    "fire": "🔥",
    "target": "🎯",
    "book": "📚",
    "gem": "💎",
    "medal": "🥇",
    "rocket": "🚀",
    "crown": "👑",
    "lightning": "⚡",
}

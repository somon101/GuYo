/// Mirrors the backend's ACHIEVEMENT_ICONS catalog (backend/app/
/// achievements/icons.py) exactly -- the same fixed id -> emoji mapping
/// Admin Web's icon picker uses, so an achievement looks the same to the
/// admin choosing it and the user who earns it. `Achievement.icon` is
/// always one of these ids; an unknown id (e.g. a future icon this build
/// predates) falls back to a generic badge rather than crashing.
const Map<String, String> achievementIcons = {
  'trophy': '🏆',
  'star': '⭐',
  'fire': '🔥',
  'target': '🎯',
  'book': '📚',
  'gem': '💎',
  'medal': '🥇',
  'rocket': '🚀',
  'crown': '👑',
  'lightning': '⚡',
};

String achievementEmoji(String iconId) => achievementIcons[iconId] ?? '🏅';

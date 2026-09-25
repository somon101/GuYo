// Dictionary language is now free text: an admin can add any language
// beyond the three ready-made ones through "+ Добавить новый язык". These
// are just the default shortcuts offered when creating a dictionary (kept
// as short codes to match the existing dictionaries' stored values), not a
// hard limit -- a custom language's typed name is submitted as-is, with no
// code of its own.
export const DEFAULT_LANGUAGE_PRESETS: { value: string; label: string }[] = [
  { value: "en", label: "English" },
  { value: "ru", label: "Русский" },
  { value: "zh", label: "中文" },
];

// Translation language: intentionally broader than Dictionary language and
// not capped at 3 -- a word can carry translations into any of these,
// independent of which dictionaries exist. Adding a new one here (plus on
// the backend's allow-list) is all a future language needs.
export type TranslationLanguage = "en" | "ru" | "zh" | "tg";

export const TRANSLATION_LANGUAGE_LABELS: Record<TranslationLanguage, string> = {
  en: "English",
  ru: "Русский",
  zh: "中文",
  tg: "Тоҷикӣ",
};

export interface AdminUser {
  /** Internal key -- what the delete and grant-points endpoints take. */
  id: number;
  /** The 9-digit account number people see. Shown as "ID" in the table. */
  public_id: number;
  login: string;
  /** Null on accounts created before these fields existed. */
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  created_at: string;
}

export interface Dictionary {
  id: number;
  name: string;
  language: string;
  is_published: boolean;
  // Every distinct letter of this language, as one string (e.g.
  // "abcdefghijklmnopqrstuvwxyz") -- used by exercises that need
  // distractor letters (e.g. "Собери слово"). Null until an admin sets it.
  alphabet: string | null;
  created_at: string;
  word_count: number;
}

export interface WordTranslation {
  id: number;
  language: TranslationLanguage;
  text: string;
  audio_url: string | null;
}

export interface WordForm {
  id: number;
  language: string;
  text: string;
}

export interface Category {
  id: number;
  dictionary_id: number;
  name: string;
  created_at: string;
  word_count: number;
  /** Uploaded per-category picture, same storage-key convention as rank and
   * achievement icons. Null means no icon is set -- the mobile app then
   * draws its own generic folder icon. */
  icon_url: string | null;
}

export interface Word {
  id: number;
  dictionary_id: number;
  word: string;
  transcription: string | null;
  word_audio_url: string | null;
  image_url: string | null;
  category_id: number | null;
  category_name: string | null;
  created_at: string;
  updated_at: string;
  // Convenience mirror of translations[0], kept for the word-list card.
  translation: string | null;
  translation_audio_url: string | null;
  translations: WordTranslation[];
  forms: WordForm[];
}

// Phrases are a separate entity from Word (own phrase_id, own category
// namespace) built on the same principle: one id, independently readable
// fields, reusable everywhere without duplication. Unlike Word there is
// only ever one fixed translation (Tajik), so it's a plain field rather
// than a child table.
export interface PhraseCategory {
  id: number;
  dictionary_id: number;
  name: string;
  created_at: string;
  phrase_count: number;
}

export interface Phrase {
  id: number;
  dictionary_id: number;
  category_id: number | null;
  category_name: string | null;
  original: string;
  transcription: string | null;
  translation_tg: string;
  original_audio_url: string | null;
  translation_audio_url: string | null;
  created_at: string;
  updated_at: string;
}

// Per-exercise admin setting: how many words one run uses. Keyed by a
// plain string so a future exercise (or "Сопоставление" adopting the same
// knob) is just a new key here, not a new type/table.
export interface ExerciseSettings {
  exercise_key: string;
  word_count: number;
  // Only meaningful for exercises that use them (currently "build_word");
  // null for every other exercise_key.
  wrong_letter_count: number | null;
  min_word_length: number | null;
  case_sensitive: boolean | null;
  // How much a right/wrong answer to this exercise moves a word's score
  // within a lesson (see the "Уроки" system) -- null means "use this
  // exercise's own built-in default".
  correct_points: number | null;
  incorrect_points: number | null;
  // Whether this exercise can be picked for a new Lesson at all. Null
  // means enabled -- same "unset = working default" convention as every
  // other field here.
  enabled: boolean | null;
  // Only meaningful for "listen_word" (how many word choices one round
  // shows); null for every other exercise_key.
  option_count: number | null;
  // Only meaningful for "speaking_word" (0-100 minimum text-similarity to
  // accept a spoken answer as correct); null for every other exercise_key.
  speech_match_threshold: number | null;
}

// --- Аналитика пользователей ---------------------------------------------
// Read-only report built on the exact same "is this phrase available"
// definition as the app's own "Мои фразы" (see the backend's
// app.routers.phrases) -- nothing here is a second, independent notion of
// "learned".

export interface AnalyticsDictionary {
  id: number;
  name: string;
  language: string;
  phrase_count: number;
}

export interface OpenPhraseAnalytics {
  phrase_id: number;
  original: string;
  translation_tg: string;
  category_name: string | null;
}

export interface MissingWord {
  // null when the phrase contains a token that matches no Word (or its
  // forms) in this dictionary at all -- nothing to "learn" for it.
  word_id: number | null;
  text: string;
}

export interface NearPhrase {
  phrase_id: number;
  original: string;
  translation_tg: string;
  category_name: string | null;
  learned_count: number;
  total_count: number;
  missing_words: MissingWord[];
}

export interface WordImpact {
  word_id: number;
  word: string;
  new_phrase_count: number;
  sample_phrases: string[];
}

export interface UserPhraseAnalytics {
  user_id: number;
  user_login: string;
  dictionary_id: number;
  threshold: number;
  learned_word_count: number;
  total_word_count: number;
  open_phrase_count: number;
  total_phrase_count: number;
  remaining_phrase_count: number;
  open_phrases: OpenPhraseAnalytics[];
  near_phrases: NearPhrase[];
  top_words: WordImpact[];
}

// --- Диагностика слова -------------------------------------------------
// WordProgress (level/score) + WordAttempt (every real answer, in a
// Lesson or a Quest -- Practice writes none of this, see backend/app/
// routers/practice.py). Every number here is already aggregated
// server-side; this page only renders it.

export interface WordLevelSummary {
  id: number;
  name: string;
  min_points: number;
  max_points: number | null;
  priority_weight: number;
}

export interface UserWordProgress {
  word_id: number;
  word: string;
  translation: string | null;
  dictionary_id: number;
  score: number;
  level: WordLevelSummary | null;
  total_attempts: number;
  updated_at: string;
}

export interface ExerciseAttemptStats {
  exercise_key: string;
  total_attempts: number;
  total_correct: number;
  total_errors: number;
}

export interface WordAttempt {
  exercise_key: string;
  is_correct: boolean;
  score_after: number;
  created_at: string;
}

export interface WordDiagnostics {
  user_id: number;
  user_login: string;
  word_id: number;
  word: string;
  translation: string | null;
  score: number;
  level: WordLevelSummary | null;
  total_attempts: number;
  total_correct: number;
  total_errors: number;
  by_exercise: ExerciseAttemptStats[];
  last_attempt: WordAttempt | null;
  history: WordAttempt[];
  priority_score: number;
  priority_level: { id: number; name: string } | null;
  stability_percent: number | null;
  stability_level: { id: number; name: string } | null;
  days_since_last_attempt: number | null;
  recency_level: { id: number; name: string } | null;
  level_contribution: number;
  recent_errors_contribution: number;
  recency_contribution: number;
  stability_contribution: number;
  // Every exercise_key this word currently looks weak in (see
  // backend/app/priority/quests_auto.py) -- the same rule personal
  // auto-quests trigger on, surfaced here for one word.
  weak_exercises: string[];
}

// --- Достижения ------------------------------------------------------------
// Achievement is the DEFINITION an admin edits here; whether/when a given
// user actually earned it lives entirely on the backend (UserAchievement) --
// Admin Web never sees or touches individual users' grants directly.

export type AchievementVisibility = "visible" | "hidden";

export interface Achievement {
  id: number;
  title: string;
  description: string;
  icon_url: string | null;
  color: string;
  condition_type: string;
  condition_value: number;
  enabled: boolean;
  visibility: AchievementVisibility;
  show_before_unlock: boolean;
  order: number;
}

export interface ConditionType {
  id: string;
  label: string;
}

// --- Рейтинг -----------------------------------------------------------------
// Entirely separate from Achievements above -- a different backend system
// (app/rating/), a different Admin Web section, never cross-referenced.

export type RatingResetMode = "fixed" | "percent";

export interface RatingSettings {
  points_per_learned_word: number;
  season_reset_mode: RatingResetMode;
  season_reset_value: number;
}

export interface Rank {
  id: number;
  name: string;
  min_points: number;
  max_points: number | null;
  icon_url: string | null;
  color: string;
  order: number;
  enabled: boolean;
}

// "scheduled" is a season that exists with a period but hasn't started
// yet -- what makes queueing several seasons in advance possible without
// ever having two live at once.
export type SeasonStatus = "scheduled" | "active" | "completed";

export interface Season {
  id: number;
  name: string;
  /** ISO datetime. When the season begins. */
  starts_at: string;
  /** ISO datetime, or null for "ends only when an admin ends it". The
   * PLANNED end -- reaching it ends the season automatically. */
  ends_at: string | null;
  /** ISO datetime, or null while the season hasn't ended. When it
   * ACTUALLY ended, which may be earlier than ends_at if an admin ended
   * it by hand. */
  ended_at: string | null;
  status: SeasonStatus;
  /** Stored for later use; nothing renders it in the app yet. */
  icon_url: string | null;
}

// --- Уровни слов и квесты -----------------------------------------------------
// WordLevel replaces the old single "Проходной порог изучения слова" number
// with an admin-defined ladder (app/word_levels/) -- the top enabled level's
// min_points becomes the new "learned" threshold. Quests (app/quests/) are a
// separate system again: reinforcement points stay on WordProgress (reused
// from the exercise-settings points already configured per exercise_key),
// only the rating reward is new.

export interface WordLevel {
  id: number;
  name: string;
  min_points: number;
  max_points: number | null;
  order: number;
  enabled: boolean;
  // How much a word at this level contributes to its own Priority Score
  // (see the "Приоритет" settings page) -- an analytics layer on top of
  // this ladder, edited here alongside the level's own range.
  priority_weight: number;
}

// --- Приоритет -------------------------------------------------------------
// Every number app/priority/calculate.py reads on the backend, editable
// here and nowhere else (see backend/app/priority/'s own module
// docstring) -- word-level weights live on WordLevel itself, above.

export interface PrioritySettings {
  weight_level: number;
  weight_recent_errors: number;
  weight_recency: number;
  weight_stability: number;
  window5_weight: number;
  window10_weight: number;
  window20_weight: number;
  stability_window: number;
  // Personal auto-quests (see backend/app/priority/quests_auto.py).
  personal_quest_min_attempts: number;
  personal_quest_weak_error_rate: number;
  personal_quest_min_words: number;
  personal_quest_max_words: number;
  personal_quest_reward_points: number;
}

export interface PriorityRecencyBand {
  id: number;
  name: string;
  min_days: number;
  max_days: number | null;
  contribution: number;
  order: number;
  enabled: boolean;
}

export interface PriorityStabilityBand {
  id: number;
  name: string;
  min_percent: number;
  max_percent: number;
  contribution: number;
  order: number;
  enabled: boolean;
}

export interface PriorityLevelBand {
  id: number;
  name: string;
  min_score: number;
  max_score: number | null;
  order: number;
  enabled: boolean;
}

export interface Quest {
  id: number;
  name: string;
  word_level_id: number;
  word_level_name: string;
  exercise_key: string;
  reward_points: number;
  /** How many successful attempts count as "done for today" -- the goal a
   * user's progress bar fills toward. NOT a reward rule: every success
   * still grants reward_points, target reached or not. */
  daily_target: number;
  enabled: boolean;
  order: number;
}

// --- Слоганы -------------------------------------------------------------------
// The greeting lines shown under a user's name on Главная. The backend draws
// one per user per day and holds it, so an admin edits the pool, not what any
// one person sees right now.

export interface Slogan {
  id: number;
  text: string;
  enabled: boolean;
  order: number;
  created_at: string;
}

// --- Уведомления ---------------------------------------------------------------
// One inbox row per message. `source` is provenance -- "manual" for a message
// an admin wrote here, and whatever a future automatic rule stamps. Both are
// the same kind of row.

export interface AdminNotification {
  id: number;
  user_id: number;
  user_login: string;
  title: string | null;
  body: string;
  source: string;
  is_read: boolean;
  read_at: string | null;
  created_at: string;
}

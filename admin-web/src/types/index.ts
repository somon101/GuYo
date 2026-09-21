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
  id: number;
  login: string;
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

// The single admin-configured value that isn't specific to any one
// exercise: the score (0-100) a word's WordProgress needs to reach before
// it counts as learned.
export interface LearningSettings {
  threshold_score: number;
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

export type SeasonStatus = "active" | "completed";

export interface Season {
  id: number;
  name: string;
  start_date: string;
  end_date: string | null;
  status: SeasonStatus;
}

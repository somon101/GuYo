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
}

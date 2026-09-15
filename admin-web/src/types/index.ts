// Dictionary language: a strict 3-option set for this stage (see stage 1 spec).
export type Language = "en" | "ru" | "zh";

export const LANGUAGE_LABELS: Record<Language, string> = {
  en: "English",
  ru: "Русский",
  zh: "中文",
};

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
  language: Language;
  created_at: string;
  word_count: number;
}

export interface WordTranslation {
  id: number;
  language: TranslationLanguage;
  text: string;
  audio_url: string | null;
}

export interface Word {
  id: number;
  dictionary_id: number;
  word: string;
  transcription: string | null;
  word_audio_url: string | null;
  image_url: string | null;
  quizlet: string | null;
  created_at: string;
  updated_at: string;
  // Convenience mirror of translations[0], kept for the word-list card.
  translation: string | null;
  translation_audio_url: string | null;
  translations: WordTranslation[];
}

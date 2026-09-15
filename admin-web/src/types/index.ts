export type Language = "en" | "ru" | "zh";

export const LANGUAGE_LABELS: Record<Language, string> = {
  en: "English",
  ru: "Русский",
  zh: "中文",
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

export interface Word {
  id: number;
  dictionary_id: number;
  word: string;
  translation: string;
  transcription: string | null;
  word_audio_url: string | null;
  translation_audio_url: string | null;
  image_url: string | null;
  created_at: string;
  updated_at: string;
}

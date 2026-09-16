import { api } from "./client";
import type {
  AdminUser,
  Category,
  Dictionary,
  Phrase,
  PhraseCategory,
  TranslationLanguage,
  Word,
  WordForm,
  WordTranslation,
} from "../types";

export async function adminLogin(login: string, password: string): Promise<string> {
  const { data } = await api.post("/auth/admin/login", { login, password });
  return data.access_token as string;
}

export async function fetchMe(): Promise<{ id: number; login: string; role: string }> {
  const { data } = await api.get("/auth/me");
  return data;
}

export async function listUsers(): Promise<AdminUser[]> {
  const { data } = await api.get("/users");
  return data;
}

export async function createUser(login: string, password: string): Promise<AdminUser> {
  const { data } = await api.post("/users", { login, password });
  return data;
}

export async function listDictionaries(): Promise<Dictionary[]> {
  const { data } = await api.get("/dictionaries");
  return data;
}

export async function createDictionary(language: string): Promise<Dictionary> {
  const { data } = await api.post("/dictionaries", { language });
  return data;
}

export async function getDictionary(id: number): Promise<Dictionary> {
  const { data } = await api.get(`/dictionaries/${id}`);
  return data;
}

export async function setDictionaryPublished(id: number, isPublished: boolean): Promise<Dictionary> {
  const { data } = await api.patch(`/dictionaries/${id}`, { is_published: isPublished });
  return data;
}

export async function deleteDictionary(id: number): Promise<void> {
  await api.delete(`/dictionaries/${id}`);
}

export async function listWords(dictionaryId: number, categoryId?: number): Promise<Word[]> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/words`, {
    params: categoryId !== undefined ? { category_id: categoryId } : undefined,
  });
  return data;
}

export async function listCategories(dictionaryId: number): Promise<Category[]> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/categories`);
  return data;
}

export async function createCategory(dictionaryId: number, name: string): Promise<Category> {
  const { data } = await api.post(`/dictionaries/${dictionaryId}/categories`, { name });
  return data;
}

export interface CreateWordInput {
  word: string;
  translation: string;
  transcription?: string;
  categoryId?: number | null;
  wordAudio?: File | null;
  translationAudio?: File | null;
  image?: File | null;
}

export async function createWord(dictionaryId: number, input: CreateWordInput): Promise<Word> {
  const form = new FormData();
  form.append("word", input.word);
  form.append("translation", input.translation);
  if (input.transcription) form.append("transcription", input.transcription);
  if (input.categoryId != null) form.append("category_id", String(input.categoryId));
  if (input.wordAudio) form.append("word_audio", input.wordAudio);
  if (input.translationAudio) form.append("translation_audio", input.translationAudio);
  if (input.image) form.append("image", input.image);

  const { data } = await api.post(`/dictionaries/${dictionaryId}/words`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
}

export async function deleteWord(wordId: number): Promise<void> {
  await api.delete(`/words/${wordId}`);
}

export async function getWord(wordId: number): Promise<Word> {
  const { data } = await api.get(`/words/${wordId}`);
  return data;
}

/** Patch for the Word itself: text fields plus its own image/audio.
 * Only fields that are set are changed; the rest of the word (including
 * its translations) is left untouched. Pass a `remove*` flag to clear a
 * field/file instead of replacing it. */
export interface UpdateWordInput {
  word?: string;
  transcription?: string;
  removeTranscription?: boolean;
  categoryId?: number;
  removeCategory?: boolean;
  wordAudio?: File | null;
  removeWordAudio?: boolean;
  image?: File | null;
  removeImage?: boolean;
}

export async function updateWord(wordId: number, input: UpdateWordInput): Promise<Word> {
  const form = new FormData();
  if (input.word !== undefined) form.append("word", input.word);
  if (input.transcription !== undefined) form.append("transcription", input.transcription);
  if (input.removeTranscription) form.append("remove_transcription", "true");
  if (input.categoryId !== undefined) form.append("category_id", String(input.categoryId));
  if (input.removeCategory) form.append("remove_category", "true");
  if (input.wordAudio) form.append("word_audio", input.wordAudio);
  if (input.removeWordAudio) form.append("remove_word_audio", "true");
  if (input.image) form.append("image", input.image);
  if (input.removeImage) form.append("remove_image", "true");

  const { data } = await api.patch(`/words/${wordId}`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
}

/** Appends one more grammatical form of the word in `language`. Always
 * creates a new row -- a word may have several forms in the same language,
 * unlike translations. */
export async function addWordForm(wordId: number, language: string, text: string): Promise<WordForm> {
  const form = new FormData();
  form.append("language", language);
  form.append("text", text);

  const { data } = await api.post(`/words/${wordId}/forms`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
}

export async function deleteWordForm(wordId: number, formId: number): Promise<void> {
  await api.delete(`/words/${wordId}/forms/${formId}`);
}

/** Creates or updates the word's translation into `language`. */
export async function upsertTranslation(
  wordId: number,
  language: TranslationLanguage,
  input: { text: string; audio?: File | null; removeAudio?: boolean },
): Promise<WordTranslation> {
  const form = new FormData();
  form.append("text", input.text);
  if (input.audio) form.append("audio", input.audio);
  if (input.removeAudio) form.append("remove_audio", "true");

  const { data } = await api.put(`/words/${wordId}/translations/${language}`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
}

export async function deleteTranslation(wordId: number, language: TranslationLanguage): Promise<void> {
  await api.delete(`/words/${wordId}/translations/${language}`);
}

/** The fixed categories/words JSON shape shared by import and export --
 * see the backend's ImportPayload/ExportPayload for the authoritative
 * definition. Kept as a loose type here since the admin only ever passes
 * it straight through (parsed from / serialized to a file). */
export interface DictionaryBulkWord {
  word: string;
  translation_tg: string;
  forms: string[];
  forms_tg: string[];
}

export interface DictionaryBulkCategory {
  name: string;
  words: DictionaryBulkWord[];
}

export interface DictionaryBulkData {
  categories: DictionaryBulkCategory[];
}

export interface ImportSummary {
  categories_created: number;
  categories_reused: number;
  words_created: number;
  words_reused: number;
  forms_added: number;
}

export async function importDictionary(dictionaryId: number, payload: DictionaryBulkData): Promise<ImportSummary> {
  const { data } = await api.post(`/dictionaries/${dictionaryId}/import`, payload);
  return data;
}

export async function exportDictionary(dictionaryId: number): Promise<DictionaryBulkData> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/export`);
  return data;
}

// --- Phrases -----------------------------------------------------------
// Separate entity from Word, own id (phrase_id) and own category
// namespace (PhraseCategory), same CRUD shape as Words/Categories.

export async function listPhraseCategories(dictionaryId: number): Promise<PhraseCategory[]> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/phrase-categories`);
  return data;
}

export async function createPhraseCategory(dictionaryId: number, name: string): Promise<PhraseCategory> {
  const { data } = await api.post(`/dictionaries/${dictionaryId}/phrase-categories`, { name });
  return data;
}

export async function listPhrases(dictionaryId: number, categoryId?: number): Promise<Phrase[]> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/phrases`, {
    params: categoryId !== undefined ? { category_id: categoryId } : undefined,
  });
  return data;
}

export interface CreatePhraseInput {
  original: string;
  translationTg: string;
  transcription?: string;
  categoryId?: number | null;
  originalAudio?: File | null;
  translationAudio?: File | null;
}

export async function createPhrase(dictionaryId: number, input: CreatePhraseInput): Promise<Phrase> {
  const form = new FormData();
  form.append("original", input.original);
  form.append("translation_tg", input.translationTg);
  if (input.transcription) form.append("transcription", input.transcription);
  if (input.categoryId != null) form.append("category_id", String(input.categoryId));
  if (input.originalAudio) form.append("original_audio", input.originalAudio);
  if (input.translationAudio) form.append("translation_audio", input.translationAudio);

  const { data } = await api.post(`/dictionaries/${dictionaryId}/phrases`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
}

export async function getPhrase(phraseId: number): Promise<Phrase> {
  const { data } = await api.get(`/phrases/${phraseId}`);
  return data;
}

export interface UpdatePhraseInput {
  original?: string;
  transcription?: string;
  removeTranscription?: boolean;
  translationTg?: string;
  categoryId?: number;
  removeCategory?: boolean;
  originalAudio?: File | null;
  removeOriginalAudio?: boolean;
  translationAudio?: File | null;
  removeTranslationAudio?: boolean;
}

export async function updatePhrase(phraseId: number, input: UpdatePhraseInput): Promise<Phrase> {
  const form = new FormData();
  if (input.original !== undefined) form.append("original", input.original);
  if (input.transcription !== undefined) form.append("transcription", input.transcription);
  if (input.removeTranscription) form.append("remove_transcription", "true");
  if (input.translationTg !== undefined) form.append("translation_tg", input.translationTg);
  if (input.categoryId !== undefined) form.append("category_id", String(input.categoryId));
  if (input.removeCategory) form.append("remove_category", "true");
  if (input.originalAudio) form.append("original_audio", input.originalAudio);
  if (input.removeOriginalAudio) form.append("remove_original_audio", "true");
  if (input.translationAudio) form.append("translation_audio", input.translationAudio);
  if (input.removeTranslationAudio) form.append("remove_translation_audio", "true");

  const { data } = await api.patch(`/phrases/${phraseId}`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
}

export async function deletePhrase(phraseId: number): Promise<void> {
  await api.delete(`/phrases/${phraseId}`);
}

// The fixed categories/phrases JSON shape shared by phrase import/export --
// see the backend's ImportPhrasePayload/ExportPhrasePayload. Same principle
// as DictionaryBulkData for Words, with sentence/translation_tg instead of
// word/translation_tg/forms/forms_tg.
export interface PhraseBulkPhrase {
  sentence: string;
  translation_tg: string;
}

export interface PhraseBulkCategory {
  name: string;
  phrases: PhraseBulkPhrase[];
}

export interface PhraseBulkData {
  categories: PhraseBulkCategory[];
}

export interface ImportPhraseSummary {
  categories_created: number;
  categories_reused: number;
  phrases_created: number;
  phrases_reused: number;
}

export async function importPhrases(dictionaryId: number, payload: PhraseBulkData): Promise<ImportPhraseSummary> {
  const { data } = await api.post(`/dictionaries/${dictionaryId}/phrases/import`, payload);
  return data;
}

export async function exportPhrases(dictionaryId: number): Promise<PhraseBulkData> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/phrases/export`);
  return data;
}

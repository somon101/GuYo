import { api } from "./client";
import type { AdminUser, Dictionary, TranslationLanguage, Word, WordTranslation } from "../types";

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

export async function listWords(dictionaryId: number): Promise<Word[]> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/words`);
  return data;
}

export interface CreateWordInput {
  word: string;
  translation: string;
  transcription?: string;
  wordAudio?: File | null;
  translationAudio?: File | null;
  image?: File | null;
}

export async function createWord(dictionaryId: number, input: CreateWordInput): Promise<Word> {
  const form = new FormData();
  form.append("word", input.word);
  form.append("translation", input.translation);
  if (input.transcription) form.append("transcription", input.transcription);
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
  quizlet?: string;
  removeQuizlet?: boolean;
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
  if (input.quizlet !== undefined) form.append("quizlet", input.quizlet);
  if (input.removeQuizlet) form.append("remove_quizlet", "true");
  if (input.wordAudio) form.append("word_audio", input.wordAudio);
  if (input.removeWordAudio) form.append("remove_word_audio", "true");
  if (input.image) form.append("image", input.image);
  if (input.removeImage) form.append("remove_image", "true");

  const { data } = await api.patch(`/words/${wordId}`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return data;
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

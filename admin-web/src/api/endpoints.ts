import { api } from "./client";
import type { AdminUser, Dictionary, Language, Word } from "../types";

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

export async function createDictionary(name: string, language: Language): Promise<Dictionary> {
  const { data } = await api.post("/dictionaries", { name, language });
  return data;
}

export async function getDictionary(id: number): Promise<Dictionary> {
  const { data } = await api.get(`/dictionaries/${id}`);
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

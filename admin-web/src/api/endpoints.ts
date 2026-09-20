import { api } from "./client";
import type {
  AdminUser,
  AnalyticsDictionary,
  Category,
  Dictionary,
  ExerciseSettings,
  LearningSettings,
  Phrase,
  PhraseCategory,
  TranslationLanguage,
  UserPhraseAnalytics,
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

export async function createDictionary(language: string, alphabet?: string): Promise<Dictionary> {
  const { data } = await api.post("/dictionaries", { language, alphabet: alphabet || undefined });
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

export async function setDictionaryAlphabet(id: number, alphabet: string): Promise<Dictionary> {
  const { data } = await api.patch(`/dictionaries/${id}`, { alphabet });
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

/** Server-tracked state of one ZIP import -- either a dictionary (words)
 * ZIP or a phrases ZIP, both sharing this same shape (see the backend's
 * ImportJobOut). The browser never parses the ZIP or decides whether it's
 * valid -- it only starts the job and polls this by job_id, so a slow
 * import keeps running on the backend (and its result stays retrievable)
 * no matter what the admin's tab does in the meantime. `error_message` is
 * a specific reason (which word/phrase/category/path, or which JSON
 * problem), only set once `status === "failed"`; the count fields are only
 * set once `status === "completed"`, and only the pair matching what this
 * job actually imported (words + forms, or phrases) is non-null. */
export interface ImportJob {
  job_id: string;
  status: "pending" | "processing" | "completed" | "failed";
  error_message: string | null;
  categories_created: number | null;
  categories_reused: number | null;
  words_created: number | null;
  words_reused: number | null;
  forms_added: number | null;
  phrases_created: number | null;
  phrases_reused: number | null;
}

/** Dictionary import/export moves as a ZIP archive (dictionary.json --
 * fixed categories/words shape, each word optionally carrying `audio`/
 * `audio_tg` paths -- plus the audio files themselves under
 * audio/original/ and audio/tg/, see the backend's ImportPayload for the
 * authoritative shape). The admin only ever passes the archive through as
 * an opaque file/blob, never parses it client-side. Starting an import
 * only hands the file to the backend and gets a job_id back immediately;
 * use `getDictionaryImportJob` to poll for its actual result. */
export async function startDictionaryImport(dictionaryId: number, file: File): Promise<ImportJob> {
  const formData = new FormData();
  formData.append("file", file);
  const { data } = await api.post(`/dictionaries/${dictionaryId}/import`, formData);
  return data;
}

export async function getDictionaryImportJob(dictionaryId: number, jobId: string): Promise<ImportJob> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/import/${jobId}`);
  return data;
}

export async function exportDictionary(dictionaryId: number): Promise<Blob> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/export`, { responseType: "blob" });
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

/** Phrase import/export moves as a ZIP archive (phrases.json -- fixed
 * categories/phrases shape, each phrase optionally carrying `audio`/
 * `audio_tg` paths -- plus the audio files themselves under
 * audio/phrases/original/ and audio/phrases/tg/, see the backend's
 * ImportPhrasePayload for the authoritative shape), same principle as the
 * Word dictionary ZIP above. The admin only ever passes the archive through
 * as an opaque file/blob, never parses it client-side. Starting an import
 * only hands the file to the backend and gets a job_id back immediately;
 * use `getPhraseImportJob` to poll for its actual result. */
export async function startPhraseImport(dictionaryId: number, file: File): Promise<ImportJob> {
  const formData = new FormData();
  formData.append("file", file);
  const { data } = await api.post(`/dictionaries/${dictionaryId}/phrases/import`, formData);
  return data;
}

export async function getPhraseImportJob(dictionaryId: number, jobId: string): Promise<ImportJob> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/phrases/import/${jobId}`);
  return data;
}

export async function exportPhrases(dictionaryId: number): Promise<Blob> {
  const { data } = await api.get(`/dictionaries/${dictionaryId}/phrases/export`, { responseType: "blob" });
  return data;
}

// --- Exercise settings ---------------------------------------------------

export async function getExerciseSettings(exerciseKey: string): Promise<ExerciseSettings> {
  const { data } = await api.get(`/exercise-settings/${exerciseKey}`);
  return data;
}

export interface ExerciseSettingsInput {
  wordCount: number;
  // Only "Собери слово" uses these today; omit them for exercises that
  // only have a word count.
  wrongLetterCount?: number | null;
  minWordLength?: number | null;
  caseSensitive?: boolean | null;
  // How many points a right/wrong answer moves a word's score within a
  // lesson -- every exercise has these. Omit to fall back to that
  // exercise's own built-in default.
  correctPoints?: number | null;
  incorrectPoints?: number | null;
}

export async function setExerciseSettings(
  exerciseKey: string,
  input: ExerciseSettingsInput,
): Promise<ExerciseSettings> {
  const { data } = await api.put(`/exercise-settings/${exerciseKey}`, {
    word_count: input.wordCount,
    wrong_letter_count: input.wrongLetterCount ?? null,
    min_word_length: input.minWordLength ?? null,
    case_sensitive: input.caseSensitive ?? null,
    correct_points: input.correctPoints ?? null,
    incorrect_points: input.incorrectPoints ?? null,
  });
  return data;
}

// --- Уроки ("Lessons") --------------------------------------------------
// The one setting that isn't specific to any exercise: the score
// threshold a word needs to reach before it counts as learned.

export async function getLearningSettings(): Promise<LearningSettings> {
  const { data } = await api.get("/learning-settings");
  return data;
}

export async function setLearningSettings(thresholdScore: number): Promise<LearningSettings> {
  const { data } = await api.put("/learning-settings", { threshold_score: thresholdScore });
  return data;
}

// --- Аналитика пользователей ---------------------------------------------
// Read-only: every number here is computed by the backend from existing
// Word/WordForm/WordProgress/Phrase data, using the exact same
// "is this phrase available" definition as the app's own "Мои фразы".

export async function listAnalyticsDictionaries(): Promise<AnalyticsDictionary[]> {
  const { data } = await api.get("/admin/analytics/dictionaries");
  return data;
}

export async function getUserPhraseAnalytics(
  userId: number,
  dictionaryId: number,
): Promise<UserPhraseAnalytics> {
  const { data } = await api.get(`/admin/analytics/users/${userId}`, {
    params: { dictionary_id: dictionaryId },
  });
  return data;
}

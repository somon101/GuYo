import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { isAxiosError } from "axios";
import { API_URL } from "../api/client";
import {
  deleteTranslation,
  getDictionary,
  getWord,
  updateWord,
  upsertTranslation,
} from "../api/endpoints";
import type { Dictionary, TranslationLanguage, Word } from "../types";
import { TRANSLATION_LANGUAGE_LABELS } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

/** Local staging for one file resource: lets the editor pick/replace/remove
 * a file and see the result immediately, without sending anything to the
 * server until "Сохранить изменения" is pressed. */
interface FileStage {
  currentUrl: string | null;
  newFile: File | null;
  removed: boolean;
}

function freshStage(currentUrl: string | null): FileStage {
  return { currentUrl, newFile: null, removed: false };
}

function stagePreviewUrl(stage: FileStage): string | null {
  if (stage.newFile) return URL.createObjectURL(stage.newFile);
  if (stage.removed) return null;
  return mediaUrl(stage.currentUrl);
}

function stageChanged(stage: FileStage): boolean {
  return stage.newFile !== null || (stage.removed && stage.currentUrl !== null);
}

interface TranslationRow {
  language: TranslationLanguage;
  originalText: string;
  text: string;
  audio: FileStage;
  isNew: boolean; // not persisted yet on the server
}

export function WordEditPage() {
  const { dictId, wordId } = useParams<{ dictId: string; wordId: string }>();
  const dictionaryId = Number(dictId);
  const id = Number(wordId);

  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [word, setWord] = useState<Word | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Editable fields, seeded from the loaded word.
  const [wordText, setWordText] = useState("");
  const [transcription, setTranscription] = useState("");
  const [quizlet, setQuizlet] = useState("");
  const [image, setImage] = useState<FileStage>(freshStage(null));
  const [wordAudio, setWordAudio] = useState<FileStage>(freshStage(null));
  const [translations, setTranslations] = useState<TranslationRow[]>([]);

  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [savedNotice, setSavedNotice] = useState(false);

  function loadInto(w: Word) {
    setWordText(w.word);
    setTranscription(w.transcription ?? "");
    setQuizlet(w.quizlet ?? "");
    setImage(freshStage(w.image_url));
    setWordAudio(freshStage(w.word_audio_url));
    setTranslations(
      w.translations.map((t) => ({
        language: t.language,
        originalText: t.text,
        text: t.text,
        audio: freshStage(t.audio_url),
        isNew: false,
      })),
    );
  }

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [w, d] = await Promise.all([getWord(id), getDictionary(dictionaryId)]);
      setWord(w);
      setDictionary(d);
      loadInto(w);
    } catch {
      setLoadError("Не удалось загрузить слово");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, dictionaryId]);

  const hasChanges = useMemo(() => {
    if (!word) return false;
    if (wordText.trim() !== word.word) return true;
    if (transcription.trim() !== (word.transcription ?? "")) return true;
    if (quizlet.trim() !== (word.quizlet ?? "")) return true;
    if (stageChanged(image) || stageChanged(wordAudio)) return true;
    return translations.some((t) => t.text.trim() !== t.originalText || stageChanged(t.audio));
  }, [word, wordText, transcription, quizlet, image, wordAudio, translations]);

  async function handleSave() {
    if (!word) return;
    setIsSaving(true);
    setSaveError(null);
    setSavedNotice(false);
    try {
      const wordPatch: Parameters<typeof updateWord>[1] = {};
      if (wordText.trim() !== word.word) wordPatch.word = wordText.trim();

      const trimmedTranscription = transcription.trim();
      if (trimmedTranscription !== (word.transcription ?? "")) {
        if (trimmedTranscription) wordPatch.transcription = trimmedTranscription;
        else wordPatch.removeTranscription = true;
      }

      const trimmedQuizlet = quizlet.trim();
      if (trimmedQuizlet !== (word.quizlet ?? "")) {
        if (trimmedQuizlet) wordPatch.quizlet = trimmedQuizlet;
        else wordPatch.removeQuizlet = true;
      }

      if (image.newFile) wordPatch.image = image.newFile;
      else if (image.removed && image.currentUrl) wordPatch.removeImage = true;

      if (wordAudio.newFile) wordPatch.wordAudio = wordAudio.newFile;
      else if (wordAudio.removed && wordAudio.currentUrl) wordPatch.removeWordAudio = true;

      const requests: Promise<unknown>[] = [];
      if (Object.keys(wordPatch).length > 0) {
        requests.push(updateWord(id, wordPatch));
      }

      for (const t of translations) {
        const textChanged = t.text.trim() !== t.originalText;
        const audioChanged = stageChanged(t.audio);
        if (!textChanged && !audioChanged) continue;
        requests.push(
          upsertTranslation(id, t.language, {
            text: t.text.trim() || t.originalText,
            audio: t.audio.newFile,
            removeAudio: t.audio.removed && !t.audio.newFile,
          }),
        );
      }

      await Promise.all(requests);
      await reload();
      setSavedNotice(true);
      setTimeout(() => setSavedNotice(false), 4000);
    } catch {
      setSaveError("Не удалось сохранить изменения. Попробуйте ещё раз.");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleDeleteTranslation(language: TranslationLanguage) {
    if (!confirm(`Удалить перевод (${TRANSLATION_LANGUAGE_LABELS[language]})?`)) return;
    try {
      await deleteTranslation(id, language);
      await reload();
    } catch (err) {
      if (isAxiosError(err) && err.response?.status === 409) {
        setSaveError("Нельзя удалить единственный перевод слова — сначала добавьте другой");
      } else {
        setSaveError("Не удалось удалить перевод");
      }
    }
  }

  if (isLoading) return <p className="text-sm text-slate-500">Загрузка…</p>;
  if (loadError || !word || !dictionary) {
    return <p className="text-sm text-red-600">{loadError ?? "Слово не найдено"}</p>;
  }

  return (
    <div className="mx-auto max-w-2xl pb-24">
      <nav className="mb-4 flex flex-wrap items-center gap-1 text-sm text-slate-500">
        <Link to="/dictionaries" className="text-indigo-600 hover:underline">
          Словари
        </Link>
        <span>→</span>
        <Link to={`/dictionaries/${dictionaryId}`} className="text-indigo-600 hover:underline" translate="no">
          {dictionary.name}
        </Link>
        <span>→</span>
        <span className="text-slate-700" translate="no">{word.word}</span>
      </nav>

      <div className="mb-6 flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900" translate="no">{word.word}</h1>
          <p className="mt-1 text-xs text-slate-400">ID слова: {word.id}</p>
        </div>
        <Link
          to={`/dictionaries/${dictionaryId}`}
          className="shrink-0 rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50"
        >
          ← Назад к словарю
        </Link>
      </div>

      <Section title="Основная информация">
        <Field label="Язык">
          <input
            className="w-full max-w-xs rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-500"
            value={dictionary.name}
            disabled
          />
        </Field>
        <Field label="Слово">
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={wordText}
            onChange={(e) => setWordText(e.target.value)}
          />
        </Field>
        {translations[0] && (
          <Field label={`Перевод (${TRANSLATION_LANGUAGE_LABELS[translations[0].language]})`}>
            <input
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
              value={translations[0].text}
              onChange={(e) =>
                setTranslations((rows) =>
                  rows.map((r, i) => (i === 0 ? { ...r, text: e.target.value } : r)),
                )
              }
            />
          </Field>
        )}
        <Field label="Транскрипция" hint="необязательно">
          <input
            className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={transcription}
            onChange={(e) => setTranscription(e.target.value)}
            placeholder="/ˈæpəl/"
          />
        </Field>
      </Section>

      <Section title="Изображение">
        <ImageField stage={image} onChange={setImage} />
      </Section>

      <Section title="Произношение">
        <AudioBlock
          languageLabel={dictionary.name}
          text={word.word}
          captionPrefix="Аудио слова"
          stage={wordAudio}
          onChange={setWordAudio}
        />
        {translations.map((t, i) => (
          <div key={t.language} className={i > 0 ? "mt-5 border-t border-slate-100 pt-5" : "mt-5 border-t border-slate-100 pt-5"}>
            <div className="mb-2 flex items-center justify-between">
              <span className="text-xs font-medium uppercase tracking-wide text-slate-400">
                Перевод: {TRANSLATION_LANGUAGE_LABELS[t.language]}
              </span>
              <button
                type="button"
                onClick={() => handleDeleteTranslation(t.language)}
                disabled={translations.length <= 1}
                title={translations.length <= 1 ? "У слова должен остаться хотя бы один перевод" : undefined}
                className="text-xs text-slate-400 hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:text-slate-400"
              >
                Удалить этот перевод
              </button>
            </div>
            <AudioBlock
              languageLabel={TRANSLATION_LANGUAGE_LABELS[t.language]}
              text={t.text || t.originalText}
              captionPrefix="Аудио перевода"
              stage={t.audio}
              onChange={(next) =>
                setTranslations((rows) => rows.map((r) => (r.language === t.language ? { ...r, audio: next } : r)))
              }
            />
          </div>
        ))}
      </Section>

      <Section title="Другие ресурсы">
        <Field label="Quizlet" hint="ссылка на набор/карточку, необязательно">
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={quizlet}
            onChange={(e) => setQuizlet(e.target.value)}
            placeholder="https://quizlet.com/..."
          />
        </Field>
      </Section>

      <div className="sticky bottom-4 mt-6 flex items-center gap-3 rounded-lg border border-slate-200 bg-white/95 p-4 shadow-sm backdrop-blur">
        <button
          onClick={handleSave}
          disabled={!hasChanges || isSaving}
          className="rounded-md bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {isSaving ? "Сохранение…" : "Сохранить изменения"}
        </button>
        {savedNotice && <span className="text-sm text-emerald-600">Изменения сохранены</span>}
        {saveError && <span className="text-sm text-red-600">{saveError}</span>}
        {!hasChanges && !savedNotice && !saveError && (
          <span className="text-sm text-slate-400">Нет несохранённых изменений</span>
        )}
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-6 rounded-lg border border-slate-200 bg-white p-5">
      <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h2>
      {children}
    </div>
  );
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mb-4 last:mb-0">
      <label className="mb-1 block text-sm font-medium text-slate-700">
        {label} {hint && <span className="font-normal text-slate-400">({hint})</span>}
      </label>
      {children}
    </div>
  );
}

function ImageField({
  stage,
  onChange,
}: {
  stage: FileStage;
  onChange: (stage: FileStage) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const preview = stagePreviewUrl(stage);

  return (
    <div>
      {preview ? (
        <div className="flex items-start gap-4">
          <img
            src={preview}
            alt="Предпросмотр"
            className="h-32 w-32 rounded-md border border-slate-200 object-cover"
          />
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => inputRef.current?.click()}
              className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50"
            >
              Заменить
            </button>
            <button
              type="button"
              onClick={() => onChange({ ...stage, newFile: null, removed: true })}
              className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-red-50 hover:text-red-600"
            >
              Удалить
            </button>
          </div>
        </div>
      ) : (
        <div className="flex items-center gap-3">
          <span className="text-sm text-slate-400">Изображение не добавлено</span>
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50"
          >
            Добавить изображение
          </button>
        </div>
      )}
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0] ?? null;
          if (file) onChange({ currentUrl: stage.currentUrl, newFile: file, removed: false });
          e.target.value = "";
        }}
      />
    </div>
  );
}

function AudioBlock({
  languageLabel,
  text,
  captionPrefix,
  stage,
  onChange,
}: {
  languageLabel: string;
  text: string;
  captionPrefix: string;
  stage: FileStage;
  onChange: (stage: FileStage) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const preview = stagePreviewUrl(stage);

  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-slate-400">{languageLabel}</p>
      <p className="mb-2 text-sm font-medium text-slate-800" translate="no">{text}</p>
      {preview ? (
        <div className="flex flex-wrap items-center gap-3">
          <span className="text-sm text-slate-500">{captionPrefix}:</span>
          <audio controls src={preview} className="h-8 max-w-full" />
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50"
          >
            Заменить аудио
          </button>
          <button
            type="button"
            onClick={() => onChange({ ...stage, newFile: null, removed: true })}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-red-50 hover:text-red-600"
          >
            Удалить
          </button>
        </div>
      ) : (
        <div className="flex items-center gap-3">
          <span className="text-sm text-slate-400">{captionPrefix}: не добавлено</span>
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50"
          >
            Добавить аудио
          </button>
        </div>
      )}
      <input
        ref={inputRef}
        type="file"
        accept="audio/*"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0] ?? null;
          if (file) onChange({ currentUrl: stage.currentUrl, newFile: file, removed: false });
          e.target.value = "";
        }}
      />
    </div>
  );
}

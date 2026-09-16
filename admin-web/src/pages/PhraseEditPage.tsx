import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { API_URL } from "../api/client";
import { getDictionary, getPhrase, listPhraseCategories, updatePhrase } from "../api/endpoints";
import type { Dictionary, Phrase, PhraseCategory } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

/** Local staging for one file resource -- identical convention to
 * WordEditPage's FileStage: pick/replace/remove happens locally, nothing
 * is sent to the server until "Сохранить изменения" is pressed. */
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

export function PhraseEditPage() {
  const { dictId, phraseId } = useParams<{ dictId: string; phraseId: string }>();
  const dictionaryId = Number(dictId);
  const id = Number(phraseId);

  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [phrase, setPhrase] = useState<Phrase | null>(null);
  const [categories, setCategories] = useState<PhraseCategory[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [original, setOriginal] = useState("");
  const [transcription, setTranscription] = useState("");
  const [translationTg, setTranslationTg] = useState("");
  const [categoryId, setCategoryId] = useState<number | null>(null);
  const [originalAudio, setOriginalAudio] = useState<FileStage>(freshStage(null));
  const [translationAudio, setTranslationAudio] = useState<FileStage>(freshStage(null));

  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [savedNotice, setSavedNotice] = useState(false);

  function loadInto(p: Phrase) {
    setOriginal(p.original);
    setTranscription(p.transcription ?? "");
    setTranslationTg(p.translation_tg);
    setCategoryId(p.category_id);
    setOriginalAudio(freshStage(p.original_audio_url));
    setTranslationAudio(freshStage(p.translation_audio_url));
  }

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [p, d, cats] = await Promise.all([
        getPhrase(id),
        getDictionary(dictionaryId),
        listPhraseCategories(dictionaryId),
      ]);
      setPhrase(p);
      setDictionary(d);
      setCategories(cats);
      loadInto(p);
    } catch {
      setLoadError("Не удалось загрузить фразу");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, dictionaryId]);

  const hasChanges = useMemo(() => {
    if (!phrase) return false;
    if (original.trim() !== phrase.original) return true;
    if (transcription.trim() !== (phrase.transcription ?? "")) return true;
    if (translationTg.trim() !== phrase.translation_tg) return true;
    if (categoryId !== phrase.category_id) return true;
    return stageChanged(originalAudio) || stageChanged(translationAudio);
  }, [phrase, original, transcription, translationTg, categoryId, originalAudio, translationAudio]);

  async function handleSave() {
    if (!phrase) return;
    setIsSaving(true);
    setSaveError(null);
    setSavedNotice(false);
    try {
      const patch: Parameters<typeof updatePhrase>[1] = {};
      if (original.trim() !== phrase.original) patch.original = original.trim();
      if (translationTg.trim() !== phrase.translation_tg) patch.translationTg = translationTg.trim();

      const trimmedTranscription = transcription.trim();
      if (trimmedTranscription !== (phrase.transcription ?? "")) {
        if (trimmedTranscription) patch.transcription = trimmedTranscription;
        else patch.removeTranscription = true;
      }

      if (categoryId !== phrase.category_id) {
        if (categoryId !== null) patch.categoryId = categoryId;
        else patch.removeCategory = true;
      }

      if (originalAudio.newFile) patch.originalAudio = originalAudio.newFile;
      else if (originalAudio.removed && originalAudio.currentUrl) patch.removeOriginalAudio = true;

      if (translationAudio.newFile) patch.translationAudio = translationAudio.newFile;
      else if (translationAudio.removed && translationAudio.currentUrl) patch.removeTranslationAudio = true;

      if (Object.keys(patch).length > 0) {
        await updatePhrase(id, patch);
      }

      await reload();
      setSavedNotice(true);
      setTimeout(() => setSavedNotice(false), 4000);
    } catch {
      setSaveError("Не удалось сохранить изменения. Попробуйте ещё раз.");
    } finally {
      setIsSaving(false);
    }
  }

  if (isLoading) return <p className="text-sm text-slate-500">Загрузка…</p>;
  if (loadError || !phrase || !dictionary) {
    return <p className="text-sm text-red-600">{loadError ?? "Фраза не найдена"}</p>;
  }

  return (
    <div className="mx-auto max-w-2xl pb-24">
      <nav className="mb-4 flex flex-wrap items-center gap-1 text-sm text-slate-500">
        <Link to="/dictionaries" className="text-indigo-600 hover:underline">
          Языки
        </Link>
        <span>→</span>
        <Link
          to={`/dictionaries/${dictionaryId}/phrases`}
          className="text-indigo-600 hover:underline"
          translate="no"
        >
          {dictionary.name} · Фразы
        </Link>
        <span>→</span>
        <span className="text-slate-700" translate="no">
          {phrase.original}
        </span>
      </nav>

      <div className="mb-6 flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900" translate="no">
            {phrase.original}
          </h1>
          <p className="mt-1 text-xs text-slate-400">ID фразы: {phrase.id}</p>
        </div>
        <Link
          to={`/dictionaries/${dictionaryId}/phrases`}
          className="shrink-0 rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50"
        >
          ← Назад к фразам
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
        <Field label="Оригинальная фраза">
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={original}
            onChange={(e) => setOriginal(e.target.value)}
          />
        </Field>
        <Field label="Перевод (Тоҷикӣ)">
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={translationTg}
            onChange={(e) => setTranslationTg(e.target.value)}
          />
        </Field>
        <Field label="Транскрипция" hint="необязательно">
          <input
            className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={transcription}
            onChange={(e) => setTranscription(e.target.value)}
          />
        </Field>
        <Field label="Категория" hint="необязательно">
          <select
            className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={categoryId ?? ""}
            onChange={(e) => setCategoryId(e.target.value ? Number(e.target.value) : null)}
          >
            <option value="">Без категории</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </Field>
      </Section>

      <Section title="Аудио оригинала">
        <AudioBlock
          languageLabel={dictionary.name}
          text={original || phrase.original}
          stage={originalAudio}
          onChange={setOriginalAudio}
        />
      </Section>

      <Section title="Аудио перевода">
        <AudioBlock
          languageLabel="Тоҷикӣ"
          text={translationTg || phrase.translation_tg}
          stage={translationAudio}
          onChange={setTranslationAudio}
        />
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

function AudioBlock({
  languageLabel,
  text,
  stage,
  onChange,
}: {
  languageLabel: string;
  text: string;
  stage: FileStage;
  onChange: (stage: FileStage) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const preview = stagePreviewUrl(stage);

  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-slate-400">{languageLabel}</p>
      <p className="mb-2 text-sm font-medium text-slate-800" translate="no">
        {text}
      </p>
      {preview ? (
        <div className="flex flex-wrap items-center gap-3">
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
          <span className="text-sm text-slate-400">Аудио не добавлено</span>
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

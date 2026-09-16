import { useEffect, useState, type FormEvent } from "react";
import { Link, useParams } from "react-router-dom";
import { API_URL } from "../api/client";
import { createPhrase, deletePhrase, getDictionary, listPhraseCategories, listPhrases } from "../api/endpoints";
import type { Dictionary, Phrase, PhraseCategory } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

/** Shared list of a dictionary's phrases: either every phrase ("Все фразы",
 * reached with no :categoryId) or just the phrases filed under one category
 * (reached via /dictionaries/:id/phrases/categories/:categoryId). Mirrors
 * WordsListPage exactly, just against the Phrase entity/API. */
export function PhrasesListPage() {
  const { id, categoryId: categoryIdParam } = useParams<{ id: string; categoryId?: string }>();
  const dictionaryId = Number(id);
  const categoryId = categoryIdParam ? Number(categoryIdParam) : undefined;

  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [categories, setCategories] = useState<PhraseCategory[]>([]);
  const [phrases, setPhrases] = useState<Phrase[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isFormOpen, setIsFormOpen] = useState(false);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [dict, cats, phraseList] = await Promise.all([
        getDictionary(dictionaryId),
        listPhraseCategories(dictionaryId),
        listPhrases(dictionaryId, categoryId),
      ]);
      setDictionary(dict);
      setCategories(cats);
      setPhrases(phraseList);
    } catch {
      setLoadError("Не удалось загрузить язык");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dictionaryId, categoryId]);

  async function handleDelete(phraseId: number) {
    if (!confirm("Удалить эту фразу?")) return;
    await deletePhrase(phraseId);
    reload();
  }

  if (isLoading) {
    return <p className="text-sm text-slate-500">Загрузка…</p>;
  }

  if (loadError || !dictionary) {
    return <p className="text-sm text-red-600">{loadError ?? "Язык не найден"}</p>;
  }

  const currentCategory = categoryId != null ? categories.find((c) => c.id === categoryId) : undefined;
  if (categoryId != null && !currentCategory) {
    return <p className="text-sm text-red-600">Категория не найдена</p>;
  }

  return (
    <div className="mx-auto max-w-3xl">
      <nav className="mb-4 flex flex-wrap items-center gap-1 text-sm text-slate-500">
        <Link to="/dictionaries" className="text-indigo-600 hover:underline">
          Языки
        </Link>
        <span>→</span>
        <Link to={`/dictionaries/${dictionaryId}/phrases`} className="text-indigo-600 hover:underline" translate="no">
          {dictionary.name} · Фразы
        </Link>
        <span>→</span>
        <span className="text-slate-700" translate="no">
          {currentCategory ? currentCategory.name : "Все фразы"}
        </span>
      </nav>

      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-slate-900" translate="no">
            {currentCategory ? currentCategory.name : "Все фразы"}
          </h1>
          <p className="text-sm text-slate-500">{phrases.length} фраз</p>
        </div>
        <button
          onClick={() => setIsFormOpen((v) => !v)}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Добавить фразу
        </button>
      </div>

      {isFormOpen && (
        <AddPhraseForm
          dictionaryId={dictionaryId}
          languageLabel={dictionary.name}
          categories={categories}
          defaultCategoryId={categoryId ?? null}
          onCreated={() => {
            setIsFormOpen(false);
            reload();
          }}
          onCancel={() => setIsFormOpen(false)}
        />
      )}

      {phrases.length === 0 ? (
        <p className="text-sm text-slate-500">
          {currentCategory ? "В этой категории пока нет фраз" : "В этом языке пока нет фраз"}
        </p>
      ) : (
        <ul className="flex flex-col gap-3">
          {phrases.map((p) => (
            <li
              key={p.id}
              className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2 rounded-lg border border-slate-200 bg-white p-4"
            >
              <div translate="no" className="min-w-0 flex-1">
                <p className="text-base font-medium text-slate-900">{p.original}</p>
                {p.transcription && <p className="text-sm text-slate-400">{p.transcription}</p>}
                <p className="text-sm text-slate-600">{p.translation_tg}</p>
                {!currentCategory && p.category_name && (
                  <p className="mt-1 inline-block rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-500">
                    {p.category_name}
                  </p>
                )}
                <div className="mt-2 flex flex-wrap gap-3">
                  {mediaUrl(p.original_audio_url) && (
                    <audio controls src={mediaUrl(p.original_audio_url)!} className="h-8 max-w-[220px]" />
                  )}
                  {mediaUrl(p.translation_audio_url) && (
                    <audio controls src={mediaUrl(p.translation_audio_url)!} className="h-8 max-w-[220px]" />
                  )}
                </div>
              </div>
              <div className="flex shrink-0 items-center gap-4">
                <Link
                  to={`/dictionaries/${dictionaryId}/phrases/${p.id}`}
                  className="text-sm font-medium text-indigo-600 hover:underline"
                >
                  Редактировать
                </Link>
                <button
                  onClick={() => handleDelete(p.id)}
                  className="text-sm text-slate-400 hover:text-red-600"
                >
                  Удалить
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function AddPhraseForm({
  dictionaryId,
  languageLabel,
  categories,
  defaultCategoryId,
  onCreated,
  onCancel,
}: {
  dictionaryId: number;
  languageLabel: string;
  categories: PhraseCategory[];
  defaultCategoryId: number | null;
  onCreated: () => void;
  onCancel: () => void;
}) {
  const [original, setOriginal] = useState("");
  const [translationTg, setTranslationTg] = useState("");
  const [transcription, setTranscription] = useState("");
  const [categoryId, setCategoryId] = useState<number | null>(defaultCategoryId);
  const [originalAudio, setOriginalAudio] = useState<File | null>(null);
  const [translationAudio, setTranslationAudio] = useState<File | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await createPhrase(dictionaryId, {
        original,
        translationTg,
        transcription: transcription || undefined,
        categoryId,
        originalAudio,
        translationAudio,
      });
      onCreated();
    } catch {
      setError("Не удалось сохранить фразу");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="mb-6 flex flex-col gap-4 rounded-lg border border-slate-200 bg-white p-5"
    >
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Язык</label>
          <input
            className="w-full rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-500"
            value={languageLabel}
            disabled
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">
            Категория <span className="font-normal text-slate-400">(необязательно)</span>
          </label>
          <select
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
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
        </div>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Оригинальная фраза</label>
        <input
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={original}
          onChange={(e) => setOriginal(e.target.value)}
          autoFocus
          required
        />
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">
          Транскрипция <span className="font-normal text-slate-400">(необязательно)</span>
        </label>
        <input
          className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={transcription}
          onChange={(e) => setTranscription(e.target.value)}
        />
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Перевод (Тоҷикӣ)</label>
        <input
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={translationTg}
          onChange={(e) => setTranslationTg(e.target.value)}
          required
        />
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <FileField label="Аудио оригинала" accept="audio/*" onChange={setOriginalAudio} />
        <FileField label="Аудио перевода" accept="audio/*" onChange={setTranslationAudio} />
      </div>

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : "Сохранить"}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
        >
          Отмена
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </form>
  );
}

function FileField({
  label,
  accept,
  onChange,
}: {
  label: string;
  accept: string;
  onChange: (file: File | null) => void;
}) {
  return (
    <div>
      <label className="mb-1 block text-sm font-medium text-slate-700">
        {label} <span className="font-normal text-slate-400">(необязательно)</span>
      </label>
      <input
        type="file"
        accept={accept}
        onChange={(e) => onChange(e.target.files?.[0] ?? null)}
        className="w-full text-sm text-slate-600 file:mr-3 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-slate-700 hover:file:bg-slate-200"
      />
    </div>
  );
}

import { useEffect, useState, type FormEvent } from "react";
import { Link, useParams } from "react-router-dom";
import { createPhraseCategory, getDictionary, listPhraseCategories } from "../api/endpoints";
import type { Dictionary, PhraseCategory } from "../types";
import { Modal } from "../components/Modal";
import { LanguageSectionTabs } from "../components/LanguageSectionTabs";

/** Category overview for Фразы -- the exact same shape as the word category
 * overview (DictionaryDetailPage), just pointed at the phrase-category API
 * instead. Phrases and words have fully independent category lists, even
 * within the same language block. */
export function PhraseCategoriesPage() {
  const { id } = useParams<{ id: string }>();
  const dictionaryId = Number(id);

  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [categories, setCategories] = useState<PhraseCategory[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [dict, cats] = await Promise.all([
        getDictionary(dictionaryId),
        listPhraseCategories(dictionaryId),
      ]);
      setDictionary(dict);
      setCategories(cats);
    } catch {
      setLoadError("Не удалось загрузить язык");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dictionaryId]);

  if (isLoading) {
    return <p className="text-sm text-slate-500">Загрузка…</p>;
  }

  if (loadError || !dictionary) {
    return <p className="text-sm text-red-600">{loadError ?? "Язык не найден"}</p>;
  }

  const totalPhrases = categories.reduce((sum, c) => sum + c.phrase_count, 0);

  return (
    <div className="mx-auto max-w-3xl">
      <Link to="/dictionaries" className="mb-4 inline-block text-sm text-indigo-600 hover:underline">
        ← Все языки
      </Link>

      <LanguageSectionTabs dictionaryId={dictionaryId} active="phrases" />

      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-slate-900" translate="no">
            {dictionary.name} · Фразы
          </h1>
          <p className="text-xs text-slate-400">ID: {dictionary.id}</p>
          <p className="text-sm text-slate-500">
            {dictionary.is_published ? "Опубликовано" : "Черновик"} · Категорий: {categories.length} ·
            Всего фраз: {totalPhrases}
          </p>
        </div>
        <button
          onClick={() => setIsModalOpen(true)}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Создать категорию
        </button>
      </div>

      <Link
        to={`/dictionaries/${dictionaryId}/phrases/all`}
        className="mb-4 block rounded-lg border border-slate-200 bg-white p-4 text-sm font-medium text-indigo-600 hover:bg-slate-50"
      >
        Все фразы ({totalPhrases}) →
      </Link>

      {categories.length === 0 ? (
        <p className="text-sm text-slate-500">Категорий пока нет</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {categories.map((c) => (
            <li key={c.id}>
              <Link
                to={`/dictionaries/${dictionaryId}/phrases/categories/${c.id}`}
                className="flex items-center justify-between gap-3 rounded-lg border border-slate-200 bg-white p-4 hover:bg-slate-50"
              >
                <span className="font-medium text-slate-900" translate="no">
                  {c.name}
                </span>
                <span className="shrink-0 text-sm text-slate-400">{c.phrase_count} фраз</span>
              </Link>
            </li>
          ))}
        </ul>
      )}

      {isModalOpen && (
        <CreatePhraseCategoryModal
          dictionaryId={dictionaryId}
          onCreated={() => {
            setIsModalOpen(false);
            reload();
          }}
          onClose={() => setIsModalOpen(false)}
        />
      )}
    </div>
  );
}

function CreatePhraseCategoryModal({
  dictionaryId,
  onCreated,
  onClose,
}: {
  dictionaryId: number;
  onCreated: () => void;
  onClose: () => void;
}) {
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    setIsSaving(true);
    setError(null);
    try {
      await createPhraseCategory(dictionaryId, trimmed);
      onCreated();
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 409) setError("Категория с таким названием уже есть в этом языке");
      else setError("Не удалось создать категорию");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Modal title="Новая категория фраз" onClose={onClose}>
      <form onSubmit={handleSubmit} className="flex flex-col gap-3">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Название</label>
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={name}
            onChange={(e) => setName(e.target.value)}
            autoFocus
            required
          />
        </div>
        <div className="flex gap-2">
          <button
            type="submit"
            disabled={isSaving}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {isSaving ? "Сохранение…" : "Создать"}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            Отмена
          </button>
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
      </form>
    </Modal>
  );
}

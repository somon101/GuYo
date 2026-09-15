import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { createDictionary, listDictionaries, setDictionaryPublished } from "../api/endpoints";
import type { Dictionary } from "../types";
import { DEFAULT_LANGUAGE_PRESETS } from "../types";

export function DictionariesPage() {
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [publishingId, setPublishingId] = useState<number | null>(null);
  const [publishError, setPublishError] = useState<string | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      setDictionaries(await listDictionaries());
    } catch {
      setLoadError("Не удалось загрузить словари");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function handleTogglePublish(dictionary: Dictionary) {
    setPublishError(null);
    setPublishingId(dictionary.id);
    try {
      const updated = await setDictionaryPublished(dictionary.id, !dictionary.is_published);
      setDictionaries((prev) => prev.map((d) => (d.id === updated.id ? updated : d)));
    } catch {
      setPublishError("Не удалось изменить статус публикации");
    } finally {
      setPublishingId(null);
    }
  }

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-slate-900">Словари</h1>
        <button
          onClick={() => setIsFormOpen((v) => !v)}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Создать словарь
        </button>
      </div>

      {isFormOpen && (
        <CreateDictionaryForm
          existingLanguages={dictionaries.map((d) => d.language)}
          onCreated={() => {
            setIsFormOpen(false);
            reload();
          }}
          onCancel={() => setIsFormOpen(false)}
        />
      )}

      {publishError && <p className="mb-4 text-sm text-red-600">{publishError}</p>}

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : dictionaries.length === 0 ? (
        <p className="text-sm text-slate-500">Словарей пока нет</p>
      ) : (
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {dictionaries.map((d) => (
            <li key={d.id} className="rounded-lg border border-slate-200 bg-white p-5">
              <p className="text-base font-medium text-slate-900" translate="no">
                {d.name}
              </p>
              <p className="mt-1 text-xs text-slate-400">ID: {d.id}</p>
              <p className="mt-2 text-sm">
                Статус:{" "}
                <span
                  className={
                    d.is_published
                      ? "font-medium text-emerald-600"
                      : "font-medium text-amber-600"
                  }
                >
                  {d.is_published ? "Опубликовано" : "Черновик"}
                </span>
              </p>
              <p className="mt-1 text-xs text-slate-400">{d.word_count} слов</p>

              <div className="mt-4 flex gap-2">
                <Link
                  to={`/dictionaries/${d.id}`}
                  className="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
                >
                  Открыть
                </Link>
                <button
                  onClick={() => handleTogglePublish(d)}
                  disabled={publishingId === d.id}
                  className={`rounded-md px-3 py-1.5 text-sm font-medium disabled:opacity-60 ${
                    d.is_published
                      ? "border border-slate-300 text-slate-700 hover:bg-slate-50"
                      : "bg-indigo-600 text-white hover:bg-indigo-700"
                  }`}
                >
                  {publishingId === d.id
                    ? "Сохранение…"
                    : d.is_published
                      ? "Снять с публикации"
                      : "Опубликовать"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function CreateDictionaryForm({
  existingLanguages,
  onCreated,
  onCancel,
}: {
  existingLanguages: string[];
  onCreated: () => void;
  onCancel: () => void;
}) {
  // Offer the 3 built-in presets plus any custom language already in use
  // by some other dictionary (so it's reusable next time), deduplicated.
  const presetValues = new Set(DEFAULT_LANGUAGE_PRESETS.map((p) => p.value));
  const customOptions = existingLanguages
    .filter((lang, index, all) => !presetValues.has(lang) && all.indexOf(lang) === index)
    .map((lang) => ({ value: lang, label: lang }));
  const options = [...DEFAULT_LANGUAGE_PRESETS, ...customOptions];

  const ADD_NEW = "__add_new__";
  const [selected, setSelected] = useState<string>(options[0]?.value ?? ADD_NEW);
  const [newLanguageName, setNewLanguageName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const isAddingNew = selected === ADD_NEW;

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const language = isAddingNew ? newLanguageName.trim() : selected;
    if (!language) {
      setError("Введите название языка");
      return;
    }

    setIsSubmitting(true);
    try {
      await createDictionary(language);
      onCreated();
    } catch {
      setError("Не удалось создать словарь");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="mb-6 flex flex-col gap-4 rounded-lg border border-slate-200 bg-white p-5"
    >
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Язык</label>
        <select
          className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={selected}
          onChange={(e) => setSelected(e.target.value)}
          autoFocus
        >
          {options.map((opt) => (
            <option key={opt.value} value={opt.value} translate="no">
              {opt.label}
            </option>
          ))}
          <option value={ADD_NEW}>+ Добавить новый язык</option>
        </select>
      </div>

      {isAddingNew && (
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Название языка</label>
          <input
            className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={newLanguageName}
            onChange={(e) => setNewLanguageName(e.target.value)}
            placeholder="Тоҷикӣ"
            autoFocus
            required
          />
        </div>
      )}

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Создание…" : "Создать"}
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

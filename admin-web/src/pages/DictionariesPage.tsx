import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import {
  createDictionary,
  deleteDictionary,
  listDictionaries,
  setDictionaryAlphabet,
  setDictionaryPublished,
} from "../api/endpoints";
import type { Dictionary } from "../types";
import { DEFAULT_LANGUAGE_PRESETS } from "../types";

export function DictionariesPage() {
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [publishingId, setPublishingId] = useState<number | null>(null);
  const [publishError, setPublishError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      setDictionaries(await listDictionaries());
    } catch {
      setLoadError("Не удалось загрузить языки");
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

  async function handleSaveAlphabet(dictionaryId: number, alphabet: string) {
    const updated = await setDictionaryAlphabet(dictionaryId, alphabet);
    setDictionaries((prev) => prev.map((d) => (d.id === updated.id ? updated : d)));
  }

  async function handleDelete(dictionary: Dictionary) {
    const confirmed = confirm(
      dictionary.word_count > 0
        ? `Удалить язык «${dictionary.name}» и все ${dictionary.word_count} слов(а) в нём? Это действие нельзя отменить.`
        : `Удалить язык «${dictionary.name}»? Это действие нельзя отменить.`,
    );
    if (!confirmed) return;

    setPublishError(null);
    setDeletingId(dictionary.id);
    try {
      await deleteDictionary(dictionary.id);
      setDictionaries((prev) => prev.filter((d) => d.id !== dictionary.id));
    } catch {
      setPublishError("Не удалось удалить язык");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-slate-900">Языки</h1>
        <button
          onClick={() => setIsFormOpen((v) => !v)}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Добавить язык
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
        <p className="text-sm text-slate-500">Языков пока нет</p>
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

              <AlphabetEditor dictionary={d} onSave={(alphabet) => handleSaveAlphabet(d.id, alphabet)} />

              <div className="mt-4 flex flex-wrap items-center gap-2">
                <Link
                  to={`/dictionaries/${d.id}`}
                  className="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
                >
                  Открыть
                </Link>
                <button
                  onClick={() => handleTogglePublish(d)}
                  disabled={publishingId === d.id || deletingId === d.id}
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
                <button
                  onClick={() => handleDelete(d)}
                  disabled={deletingId === d.id || publishingId === d.id}
                  className="ml-auto text-sm text-slate-400 hover:text-red-600 disabled:opacity-60"
                >
                  {deletingId === d.id ? "Удаление…" : "Удалить"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** Inline "Алфавит" field on each language card -- used by exercises that
 * need distractor letters (e.g. "Собери слово"). Never a hardcoded
 * per-language alphabet anywhere else: this is the one place it's set. */
function AlphabetEditor({
  dictionary,
  onSave,
}: {
  dictionary: Dictionary;
  onSave: (alphabet: string) => Promise<void>;
}) {
  const [value, setValue] = useState(dictionary.alphabet ?? "");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [savedNotice, setSavedNotice] = useState(false);

  const isDirty = value !== (dictionary.alphabet ?? "");

  async function handleSave() {
    setIsSaving(true);
    setError(null);
    setSavedNotice(false);
    try {
      await onSave(value.trim());
      setSavedNotice(true);
      setTimeout(() => setSavedNotice(false), 3000);
    } catch {
      setError("Не удалось сохранить алфавит");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="mt-3">
      <label className="mb-1 block text-xs font-medium text-slate-500" htmlFor={`alphabet-${dictionary.id}`}>
        Алфавит (для упражнений с буквами)
      </label>
      <div className="flex items-center gap-2">
        <input
          id={`alphabet-${dictionary.id}`}
          className="w-full rounded-md border border-slate-300 px-2 py-1 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="abcdefghijklmnopqrstuvwxyz"
          translate="no"
        />
        <button
          onClick={handleSave}
          disabled={isSaving || !isDirty}
          className="shrink-0 rounded-md border border-slate-300 px-2 py-1 text-xs font-medium text-slate-600 hover:bg-slate-50 disabled:opacity-50"
        >
          {isSaving ? "…" : "Сохранить"}
        </button>
      </div>
      {savedNotice && <p className="mt-1 text-xs text-emerald-600">Сохранено</p>}
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
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
  const [alphabet, setAlphabet] = useState("");
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
      await createDictionary(language, alphabet.trim() || undefined);
      onCreated();
    } catch {
      setError("Не удалось создать язык");
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

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">
          Алфавит <span className="font-normal text-slate-400">(необязательно, можно задать позже)</span>
        </label>
        <input
          className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={alphabet}
          onChange={(e) => setAlphabet(e.target.value)}
          placeholder="abcdefghijklmnopqrstuvwxyz"
          translate="no"
        />
      </div>

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

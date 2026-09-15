import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { createDictionary, listDictionaries } from "../api/endpoints";
import type { Dictionary, Language } from "../types";
import { LANGUAGE_LABELS } from "../types";

const LANGUAGE_OPTIONS: Language[] = ["en", "ru", "zh"];

export function DictionariesPage() {
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isFormOpen, setIsFormOpen] = useState(false);

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
          onCreated={() => {
            setIsFormOpen(false);
            reload();
          }}
          onCancel={() => setIsFormOpen(false)}
        />
      )}

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : dictionaries.length === 0 ? (
        <p className="text-sm text-slate-500">Словарей пока нет</p>
      ) : (
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {dictionaries.map((d) => (
            <li key={d.id}>
              <Link
                to={`/dictionaries/${d.id}`}
                className="block rounded-lg border border-slate-200 bg-white p-5 transition-colors hover:border-indigo-300 hover:shadow-sm"
              >
                <p className="text-base font-medium text-slate-900" translate="no">{d.name}</p>
                <p className="mt-1 text-sm text-slate-500">
                  {LANGUAGE_LABELS[d.language]} · {d.word_count} слов
                </p>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function CreateDictionaryForm({ onCreated, onCancel }: { onCreated: () => void; onCancel: () => void }) {
  const [name, setName] = useState("");
  const [language, setLanguage] = useState<Language>("en");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await createDictionary(name, language);
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
      className="mb-6 flex flex-col gap-3 rounded-lg border border-slate-200 bg-white p-5 sm:flex-row sm:items-end"
    >
      <div className="flex-1">
        <label className="mb-1 block text-sm font-medium text-slate-700">Название словаря</label>
        <input
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus
          required
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Язык</label>
        <select
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={language}
          onChange={(e) => setLanguage(e.target.value as Language)}
        >
          {LANGUAGE_OPTIONS.map((lang) => (
            <option key={lang} value={lang}>
              {LANGUAGE_LABELS[lang]}
            </option>
          ))}
        </select>
      </div>
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          Создать
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
        >
          Отмена
        </button>
      </div>
      {error && <p className="w-full text-sm text-red-600 sm:mt-2">{error}</p>}
    </form>
  );
}

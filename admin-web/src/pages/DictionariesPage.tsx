import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  createLanguage,
  listDictionaries,
  listLanguages,
  updateLanguage,
  type LanguageDetail,
} from "../api/endpoints";
import type { Dictionary } from "../types";

/** Раздел «Языки».
 *
 * Язык — это слой слов поверх общих понятий: «Человек» / «одам» / «Odam» /
 * «person» — четыре записи одного понятия. Поэтому язык заводится здесь одной
 * строкой, без программиста, а слова у него появляются потом: в карточке
 * понятия, импортом или ИИ-генератором.
 *
 * Карточка языка сразу показывает, чего не хватает: без озвучки не работают
 * упражнения на слух и произношение, без форм не собираются мини-фразы.
 */
export function DictionariesPage() {
  const [languages, setLanguages] = useState<LanguageDetail[]>([]);
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [draft, setDraft] = useState({ code: "", name: "", native_name: "", alphabet: "" });
  const [busy, setBusy] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoadError(null);
    try {
      const [langs, dicts] = await Promise.all([listLanguages(), listDictionaries()]);
      setLanguages(langs);
      setDictionaries(dicts);
    } catch {
      setLoadError("Не удалось загрузить языки");
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function handleAdd() {
    setFormError(null);
    const code = draft.code.trim().toLowerCase();
    if (!/^[a-z]{2,3}$/.test(code)) {
      setFormError("Код языка — две-три латинские буквы, например de или ar");
      return;
    }
    if (!draft.name.trim()) {
      setFormError("Введите название языка");
      return;
    }
    setBusy("add");
    try {
      await createLanguage({
        code,
        name: draft.name.trim(),
        native_name: draft.native_name.trim() || null,
        alphabet: draft.alphabet.trim() || null,
      });
      setDraft({ code: "", name: "", native_name: "", alphabet: "" });
      setAdding(false);
      await load();
    } catch {
      setFormError("Не удалось добавить язык — возможно, такой код уже есть");
    } finally {
      setBusy(null);
    }
  }

  async function handleToggle(language: LanguageDetail) {
    setBusy(language.code);
    try {
      await updateLanguage(language.code, { is_enabled: !language.is_enabled });
      await load();
    } catch {
      setLoadError("Не удалось изменить язык");
    } finally {
      setBusy(null);
    }
  }

  async function handleAlphabet(language: LanguageDetail, alphabet: string) {
    setBusy(language.code);
    try {
      await updateLanguage(language.code, { alphabet });
      await load();
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="mx-auto max-w-4xl">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-[26px] font-bold tracking-tight text-slate-900">Языки</h1>
          <p className="mt-1 text-sm text-slate-500">
            Язык — это слой слов поверх общих понятий. Добавьте язык, а слова у него появятся
            из карточек понятий, импорта или ИИ-генератора.
          </p>
        </div>
        <button
          onClick={() => setAdding((v) => !v)}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          {adding ? "Отмена" : "+ Добавить язык"}
        </button>
      </div>

      {adding && (
        <div className="card mb-6 p-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-sm">
              <span className="mb-1 block text-xs font-medium text-slate-500">Код (2–3 латинские буквы)</span>
              <input
                className="w-full field px-3 py-2 text-sm"
                placeholder="de"
                value={draft.code}
                onChange={(e) => setDraft({ ...draft, code: e.target.value })}
              />
            </label>
            <label className="text-sm">
              <span className="mb-1 block text-xs font-medium text-slate-500">Название</span>
              <input
                className="w-full field px-3 py-2 text-sm"
                placeholder="Немецкий"
                value={draft.name}
                onChange={(e) => setDraft({ ...draft, name: e.target.value })}
              />
            </label>
            <label className="text-sm">
              <span className="mb-1 block text-xs font-medium text-slate-500">Самоназвание</span>
              <input
                className="w-full field px-3 py-2 text-sm"
                placeholder="Deutsch"
                value={draft.native_name}
                onChange={(e) => setDraft({ ...draft, native_name: e.target.value })}
              />
            </label>
            <label className="text-sm">
              <span className="mb-1 block text-xs font-medium text-slate-500">
                Алфавит (для упражнений с буквами)
              </span>
              <input
                className="w-full field px-3 py-2 text-sm"
                placeholder="abcdefghijklmnopqrstuvwxyz"
                value={draft.alphabet}
                onChange={(e) => setDraft({ ...draft, alphabet: e.target.value })}
              />
            </label>
          </div>
          {formError && <p className="mt-3 text-sm text-red-600">{formError}</p>}
          <button
            onClick={handleAdd}
            disabled={busy === "add"}
            className="mt-4 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            {busy === "add" ? "Добавляем…" : "Добавить язык"}
          </button>
        </div>
      )}

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : (
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {languages.map((l) => (
            <li key={l.code} className="card p-5">
              <div className="flex items-baseline justify-between gap-2">
                <p className="text-base font-medium text-slate-900">
                  {l.name}
                  {l.native_name && l.native_name !== l.name ? (
                    <span className="text-slate-400"> · {l.native_name}</span>
                  ) : null}
                </p>
                <span className="text-xs text-slate-400" translate="no">
                  {l.code}
                </span>
              </div>

              <p className="mt-2 text-sm text-slate-600">
                Слов: <b>{l.entries}</b> · фраз: <b>{l.phrase_entries}</b>
              </p>
              <p className="mt-1 text-xs">
                <span className={l.with_audio === 0 ? "font-medium text-red-600" : "text-slate-500"}>
                  озвучка: {l.with_audio}
                </span>
                {" · "}
                <span className="text-slate-500">транскрипция: {l.with_transcription}</span>
                {" · "}
                <span className={l.forms === 0 ? "font-medium text-red-600" : "text-slate-500"}>
                  формы: {l.forms}
                </span>
              </p>

              <AlphabetField language={l} onSave={(value) => handleAlphabet(l, value)} />

              <div className="mt-4 flex flex-wrap items-center gap-2">
                <Link
                  to={`/languages/${l.code}/words`}
                  className="btn-tinted rounded-full px-3 py-1.5 text-sm font-medium"
                >
                  Слова языка
                </Link>
                <button
                  onClick={() => handleToggle(l)}
                  disabled={busy === l.code}
                  className={`rounded-full px-3 py-1.5 text-sm font-medium disabled:opacity-60 ${
                    l.is_enabled ? "btn-tinted" : "bg-indigo-600 text-white hover:bg-indigo-700"
                  }`}
                >
                  {l.is_enabled ? "Выключить" : "Включить"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      {dictionaries.length > 0 && (
        <p className="mt-8 text-xs text-slate-500">
          Слова, фразы и мини-фразы лежат в разделе{" "}
          <Link to="/base" className="text-indigo-600 hover:underline">
            База
          </Link>
          : язык — это срез этих данных, а не отдельное хранилище.
        </p>
      )}
    </div>
  );
}

/** Алфавит языка — им пользуются упражнения «Собери слово». */
function AlphabetField({
  language,
  onSave,
}: {
  language: LanguageDetail;
  onSave: (alphabet: string) => Promise<void>;
}) {
  const [value, setValue] = useState(language.alphabet ?? "");
  const [saving, setSaving] = useState(false);
  const dirty = value !== (language.alphabet ?? "");

  useEffect(() => {
    setValue(language.alphabet ?? "");
  }, [language.alphabet]);

  return (
    <div className="mt-3">
      <span className="mb-1 block text-xs font-medium text-slate-500">
        Алфавит (для упражнений с буквами)
      </span>
      <div className="flex items-center gap-2">
        <input
          className="w-full field px-2 py-1 text-sm"
          value={value}
          placeholder="abcdefghijklmnopqrstuvwxyz"
          translate="no"
          onChange={(e) => setValue(e.target.value)}
        />
        <button
          onClick={async () => {
            setSaving(true);
            try {
              await onSave(value.trim());
            } finally {
              setSaving(false);
            }
          }}
          disabled={saving || !dirty}
          className="shrink-0 btn-tinted rounded-full px-2.5 py-1 text-xs font-medium disabled:opacity-50"
        >
          {saving ? "…" : "Сохранить"}
        </button>
      </div>
    </div>
  );
}

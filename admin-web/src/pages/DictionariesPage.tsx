import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  createLanguage,
  listDictionaries,
  listLanguages,
  previewLanguageGaps,
  saveLanguageGaps,
  updateLanguage,
  type GapItem,
  type LanguageDetail,
} from "../api/endpoints";
import type { Dictionary } from "../types";
import { LanguagePublication } from "../components/LanguagePublication";

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
  // Заполнение пробелов: показ предложений модели и сохранение.
  const [gaps, setGaps] = useState<Record<string, GapItem[]>>({});
  const [gapsNote, setGapsNote] = useState<string | null>(null);

  /// Просит модель заполнить формы и транскрипции для этого языка.
  /// Ничего не сохраняет: сначала человек смотрит, что пришло.
  async function suggestGaps(language: LanguageDetail) {
    setBusy(language.code);
    setGapsNote(null);
    try {
      const res = await previewLanguageGaps(language.code, 20);
      if (res.reason) {
        setGapsNote(res.reason);
        setBusy(null);
        return;
      }
      setGaps((prev) => ({ ...prev, [language.code]: res.items }));
      const forms = res.items.reduce((sum, item) => sum + item.forms.length, 0);
      setGapsNote(
        `Предложено: слов ${res.items.length}, форм ${forms} · токенов ${res.tokens}. Проверьте и нажмите «Сохранить».`,
      );
    } catch {
      setGapsNote("Не удалось получить предложения — проверьте ключ ИИ в настройках");
    } finally {
      setBusy(null);
    }
  }

  async function applyGaps(language: LanguageDetail) {
    const items = gaps[language.code] ?? [];
    if (items.length === 0) return;
    setBusy(language.code);
    try {
      const res = await saveLanguageGaps(language.code, items);
      setGaps((prev) => ({ ...prev, [language.code]: [] }));
      setGapsNote(
        `Сохранено: форм ${res.forms_added}, транскрипций ${res.transcriptions}.` +
          (res.skipped.length ? ` Пропущено: ${res.skipped.length}.` : ""),
      );
      await load();
    } catch {
      setGapsNote("Не удалось сохранить");
    } finally {
      setBusy(null);
    }
  }

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

  /// Переключает «интерфейс приложения переведён на этот язык».
  ///
  /// Только этот признак решает, предлагать ли язык в переключателе интерфейса
  /// в приложении. Строки перевода он не создаёт: сначала их надо добавить в
  /// сборку, затем включить здесь — и язык появится у людей без обновления
  /// приложения через магазин.
  async function handleUiReady(language: LanguageDetail) {
    setBusy(language.code);
    try {
      await updateLanguage(language.code, { ui_ready: !language.ui_ready });
      await load();
    } catch {
      setLoadError("Не удалось изменить перевод интерфейса");
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

              <LanguagePublication language={l} onChanged={load} />

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
                <button
                  onClick={() => handleUiReady(l)}
                  disabled={busy === l.code}
                  title={
                    l.ui_ready
                      ? "Язык показан в переключателе интерфейса приложения"
                      : "Язык не предлагается как язык интерфейса: строки ещё не переведены"
                  }
                  className={`rounded-full px-3 py-1.5 text-sm font-medium disabled:opacity-60 ${
                    l.ui_ready ? "bg-emerald-50 text-emerald-700" : "btn-tinted text-slate-500"
                  }`}
                >
                  {l.ui_ready ? "Интерфейс переведён" : "Интерфейс не переведён"}
                </button>
                <button
                  onClick={() => suggestGaps(l)}
                  disabled={busy === l.code}
                  title="Модель предложит формы и транскрипции для слов, у которых их нет"
                  className="btn-tinted rounded-full px-3 py-1.5 text-sm font-medium disabled:opacity-60"
                >
                  {busy === l.code ? "…" : "Заполнить формы"}
                </button>
              </div>

              {(gaps[l.code]?.length ?? 0) > 0 && (
                <div className="mt-3 rounded-lg bg-[var(--fill)] p-3">
                  <p className="mb-2 text-xs text-slate-500">
                    Предложено слов: {gaps[l.code].length} · форм:{" "}
                    {gaps[l.code].reduce((sum, item) => sum + item.forms.length, 0)} ·
                    транскрипций:{" "}
                    {gaps[l.code].filter((item) => item.transcription && !item.has_transcription).length}
                  </p>
                  <ul className="mb-2 max-h-40 space-y-1 overflow-auto text-xs">
                    {gaps[l.code].slice(0, 20).map((item) => (
                      <li key={item.entry_id} translate="no">
                        <span className="font-medium text-slate-800">{item.word}</span>
                        {item.transcription && (
                          <span className="ml-1 text-slate-400">/{item.transcription}/</span>
                        )}
                        <span className="ml-1 text-slate-500">
                          {item.forms.length ? item.forms.join(", ") : "без форм"}
                        </span>
                      </li>
                    ))}
                  </ul>
                  <button
                    onClick={() => applyGaps(l)}
                    disabled={busy === l.code}
                    className="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
                  >
                    Сохранить
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      {gapsNote && <p className="mt-3 text-xs text-slate-500">{gapsNote}</p>}

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

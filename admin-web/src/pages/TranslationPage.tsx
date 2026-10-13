import axios from "axios";
import { useEffect, useState } from "react";
import {
  getTranslationState,
  startTranslation,
  stopTranslation,
  type TranslationState,
  type TranslatorLanguage,
} from "../api/endpoints";

const LANGUAGES: { code: TranslatorLanguage; label: string; genitive: string }[] = [
  { code: "uz", label: "Узбекский", genitive: "узбекского" },
  { code: "en", label: "Английский", genitive: "английского" },
];

const STATUS_LABELS: Record<TranslationState["status"], string> = {
  idle: "Ещё не запускался",
  running: "Идёт перевод…",
  completed: "Готово",
  failed: "Остановлен с ошибкой",
  stopped: "Остановлен",
};

function errorText(e: unknown): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return "Не удалось выполнить запрос";
}

/** «ИИ-перевод»: DeepSeek fills every missing Uzbek or English translation of words
 * and phrases (backend app/translation/deepseek.py). Results go live at
 * once and stay editable on the word and phrase pages. */
export function TranslationPage() {
  const [state, setState] = useState<TranslationState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [language, setLanguage] = useState<TranslatorLanguage>("uz");

  useEffect(() => {
    getTranslationState()
      .then((s) => {
        setState(s);
        setLanguage(s.language);
      })
      .catch((e) => setError(errorText(e)));
  }, []);

  const running = state?.status === "running";
  useEffect(() => {
    if (!running) return;
    const timer = window.setInterval(() => {
      getTranslationState().then(setState).catch(() => {});
    }, 2000);
    return () => window.clearInterval(timer);
  }, [running]);

  async function act(fn: () => Promise<TranslationState>) {
    setBusy(true);
    setError(null);
    try {
      setState(await fn());
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  if (!state) return <p className="text-sm text-slate-500">{error ?? "Загрузка…"}</p>;

  const percent = state.total ? Math.round((state.done / state.total) * 100) : 0;
  const counts = state.missing[language];
  const missing = counts.words + counts.phrases;
  const current = LANGUAGES.find((l) => l.code === language)!;
  // Progress belongs to the language the run was started for.
  const runLanguage = LANGUAGES.find((l) => l.code === state.language)!;

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h2 className="text-xl font-semibold">Перевод</h2>
        <p className="text-sm text-slate-500 mt-1">
          DeepSeek переводит все слова и фразы, у которых нет перевода на выбранный язык, опираясь на русский оригинал и
          таджикский перевод. Переводы сразу видны пользователям; исправить любой можно на странице слова
          или фразы. Аудио не создаётся.
        </p>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      {!state.key_set && (
        <p className="text-sm text-amber-600">
          Ключ DeepSeek не сохранён — перевести не получится. Он общий для всех ИИ-инструментов и сохраняется выше, на
          вкладке «ИИ».
        </p>
      )}

      <section className="card p-4 space-y-3">
        <h2 className="font-medium">Перевод</h2>
        <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Язык перевода">
          {LANGUAGES.map((l) => (
            <button
              key={l.code}
              type="button"
              role="radio"
              aria-checked={language === l.code}
              disabled={running}
              onClick={() => setLanguage(l.code)}
              className={
                language === l.code
                  ? "rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white"
                  : "btn-tinted rounded-md px-3 py-1.5 text-sm font-medium disabled:opacity-60"
              }
            >
              {l.label}
            </button>
          ))}
        </div>
        <p className="text-sm">
          Без {current.genitive} перевода: <b>{counts.words}</b> слов и <b>{counts.phrases}</b> фраз
        </p>
        <p className="text-sm">
          Статус{state.status !== "idle" && <> ({runLanguage.label.toLowerCase()})</>}: <b>{STATUS_LABELS[state.status]}</b>
          {state.total > 0 && (
            <>
              {" "}— {state.done} из {state.total} ({percent}%), не удалось: {state.failed}
            </>
          )}
        </p>
        {state.total > 0 && (
          <div className="h-2 rounded bg-slate-200 overflow-hidden">
            <div className="h-full bg-emerald-500 transition-all" style={{ width: `${percent}%` }} />
          </div>
        )}
        {state.error && <p className="text-sm text-red-600">{state.error}</p>}
        <div className="flex gap-2">
          {running ? (
            <button className="btn-tinted rounded-md px-4 py-2 text-sm font-medium" disabled={busy} onClick={() => act(stopTranslation)}>
              Остановить
            </button>
          ) : (
            <button
              className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
              disabled={busy || !state.key_set || missing === 0}
              onClick={() => act(() => startTranslation(language))}
            >
              {missing === 0 ? "Всё переведено" : `Перевести ${missing}`}
            </button>
          )}
        </div>
      </section>
    </div>
  );
}

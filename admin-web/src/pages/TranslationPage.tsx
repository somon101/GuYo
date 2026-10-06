import axios from "axios";
import { useEffect, useState, type FormEvent } from "react";
import {
  getTranslationState,
  setTranslationKey,
  startTranslation,
  stopTranslation,
  type TranslationState,
} from "../api/endpoints";

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

/** «ИИ-перевод»: DeepSeek fills every missing Uzbek translation of words
 * and phrases (backend app/translation/deepseek.py). Results go live at
 * once and stay editable on the word and phrase pages. */
export function TranslationPage() {
  const [state, setState] = useState<TranslationState | null>(null);
  const [key, setKey] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    getTranslationState().then(setState).catch((e) => setError(errorText(e)));
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

  function saveKey(e: FormEvent) {
    e.preventDefault();
    if (!key.trim()) return;
    act(() => setTranslationKey(key)).then(() => setKey(""));
  }

  if (!state) return <p className="text-sm text-slate-500">{error ?? "Загрузка…"}</p>;

  const percent = state.total ? Math.round((state.done / state.total) * 100) : 0;
  const missing = state.missing_words + state.missing_phrases;

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h1 className="text-xl font-semibold">ИИ-перевод на узбекский</h1>
        <p className="text-sm text-slate-500 mt-1">
          DeepSeek переводит все слова и фразы без узбекского перевода, опираясь на русский оригинал и
          таджикский перевод. Переводы сразу видны пользователям; исправить любой можно на странице слова
          или фразы. Аудио не создаётся.
        </p>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <section className="card p-4 space-y-3">
        <h2 className="font-medium">Ключ DeepSeek</h2>
        <p className="text-sm">
          {state.key_set ? <>Сохранён: <code>{state.key_masked}</code></> : "Ключ ещё не сохранён"}
        </p>
        <form onSubmit={saveKey} className="flex gap-2">
          <input
            type="password"
            className="flex-1 field px-3 py-2 text-sm"
            placeholder={state.key_set ? "Новый ключ, чтобы заменить" : "sk-…"}
            value={key}
            onChange={(e) => setKey(e.target.value)}
            autoComplete="off"
          />
          <button type="submit" className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60" disabled={busy || !key.trim()}>
            Сохранить
          </button>
        </form>
      </section>

      <section className="card p-4 space-y-3">
        <h2 className="font-medium">Перевод</h2>
        <p className="text-sm">
          Без узбекского перевода: <b>{state.missing_words}</b> слов и <b>{state.missing_phrases}</b> фраз
        </p>
        <p className="text-sm">
          Статус: <b>{STATUS_LABELS[state.status]}</b>
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
              onClick={() => act(startTranslation)}
            >
              {missing === 0 ? "Всё переведено" : `Перевести ${missing}`}
            </button>
          )}
        </div>
      </section>
    </div>
  );
}

import axios from "axios";
import { useCallback, useEffect, useState } from "react";
import {
  getTextCheckRun,
  listTextCheckRuns,
  type TextCheckRun,
  type TextCheckRunDetail,
} from "../api/endpoints";

function errorText(e: unknown): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return "Не удалось загрузить проверки";
}

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString("ru-RU", { day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit" });
}

const PAGE = 20;

/** «История проверок»: every text the checker was asked about, as cards.
 *
 * Each card says who checked and when and shows the first lines of the text; opening
 * one reveals the three things that together explain the answer -- the text as it was
 * written, the PROMPT that was actually sent to the model (all the rules it judged
 * by live there, so without it a wrong verdict cannot be understood), and the whole
 * answer the user saw.
 *
 * A check recorded before the text itself was kept has only its length: those cards
 * are marked so they do not look like a bug. */
export function TextCheckHistory() {
  const [runs, setRuns] = useState<TextCheckRun[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [onlyErrors, setOnlyErrors] = useState(false);
  const [onlyCached, setOnlyCached] = useState(false);
  const [query, setQuery] = useState("");
  const [userId, setUserId] = useState("");
  const [open, setOpen] = useState<TextCheckRunDetail | null>(null);
  const [openLoading, setOpenLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const parsedUser = userId.trim() === "" ? undefined : Number(userId.trim());
      const data = await listTextCheckRuns(
        {
          ...(parsedUser !== undefined && !Number.isNaN(parsedUser) ? { userId: parsedUser } : {}),
          onlyErrors,
          onlyCached,
          ...(query.trim() ? { query: query.trim() } : {}),
        },
        PAGE,
        offset,
      );
      setRuns(data.runs);
      setTotal(data.total);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setLoading(false);
    }
  }, [offset, onlyErrors, onlyCached, query, userId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function openRun(id: number) {
    setOpenLoading(true);
    try {
      setOpen(await getTextCheckRun(id));
    } catch (e) {
      setError(errorText(e));
    } finally {
      setOpenLoading(false);
    }
  }

  const pages = Math.max(1, Math.ceil(total / PAGE));
  const page = Math.floor(offset / PAGE) + 1;

  return (
    <section className="mt-8 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-bold text-slate-900">История проверок</h2>
          <p className="text-sm text-slate-500">
            Каждый текст, который проверяли: кто, когда, что написал и что ответила модель. Всего: {total}.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <input
            className="w-44 rounded-lg border border-slate-200 px-3 py-1.5 text-sm"
            placeholder="Поиск по тексту"
            value={query}
            onChange={(e) => {
              setOffset(0);
              setQuery(e.target.value);
            }}
          />
          <input
            className="w-28 rounded-lg border border-slate-200 px-3 py-1.5 text-sm"
            placeholder="ID автора"
            value={userId}
            onChange={(e) => {
              setOffset(0);
              setUserId(e.target.value);
            }}
          />
          <label className="flex items-center gap-1.5 text-sm text-slate-600">
            <input
              type="checkbox"
              checked={onlyErrors}
              onChange={(e) => {
                setOffset(0);
                setOnlyErrors(e.target.checked);
              }}
            />
            только ошибки
          </label>
          <label className="flex items-center gap-1.5 text-sm text-slate-600">
            <input
              type="checkbox"
              checked={onlyCached}
              onChange={(e) => {
                setOffset(0);
                setOnlyCached(e.target.checked);
              }}
            />
            только из кэша
          </label>
        </div>
      </div>

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}

      <div className="mt-4 space-y-2">
        {loading && runs.length === 0 && <p className="text-sm text-slate-500">Загружаем…</p>}
        {!loading && runs.length === 0 && !error && (
          <p className="text-sm text-slate-500">
            Проверок пока нет. Они появятся здесь, как только кто-то проверит текст в приложении.
          </p>
        )}
        {runs.map((run) => (
          <button
            key={run.id}
            onClick={() => void openRun(run.id)}
            className="block w-full rounded-xl border border-slate-200 p-3 text-left transition hover:border-indigo-300 hover:bg-indigo-50/40"
          >
            <div className="flex flex-wrap items-center gap-2 text-xs text-slate-500">
              <span className="font-semibold text-slate-700">{run.user_login || `id ${run.user_id ?? "—"}`}</span>
              <span>{when(run.created_at)}</span>
              <span>{run.chars} симв.</span>
              {run.cached && (
                <span className="rounded-full bg-slate-100 px-2 py-0.5 font-semibold text-slate-600">из кэша</span>
              )}
              {!run.succeeded && (
                <span className="rounded-full bg-red-100 px-2 py-0.5 font-semibold text-red-700">ошибка ИИ</span>
              )}
              {!run.has_text && (
                <span className="rounded-full bg-amber-100 px-2 py-0.5 font-semibold text-amber-700">
                  сохранилась только длина
                </span>
              )}
            </div>
            <p className="mt-1 line-clamp-2 text-sm text-slate-800">
              {run.has_text ? run.preview : "Текст этой проверки не сохранялся (запись сделана до обновления)."}
            </p>
          </button>
        ))}
      </div>

      {pages > 1 && (
        <div className="mt-4 flex items-center justify-center gap-3 text-sm">
          <button
            className="rounded-lg border border-slate-200 px-3 py-1 disabled:opacity-40"
            disabled={offset === 0}
            onClick={() => setOffset(Math.max(0, offset - PAGE))}
          >
            Назад
          </button>
          <span className="text-slate-500">
            {page} из {pages}
          </span>
          <button
            className="rounded-lg border border-slate-200 px-3 py-1 disabled:opacity-40"
            disabled={offset + PAGE >= total}
            onClick={() => setOffset(offset + PAGE)}
          >
            Вперёд
          </button>
        </div>
      )}

      {(open || openLoading) && (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center overflow-auto bg-slate-900/40 p-4"
          onClick={() => setOpen(null)}
        >
          <div
            className="mt-10 w-full max-w-3xl rounded-2xl bg-white p-5 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            {openLoading && !open && <p className="text-sm text-slate-500">Открываем…</p>}
            {open && (
              <>
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <h3 className="text-base font-bold text-slate-900">
                      Проверка #{open.id} — {open.user_login || `id ${open.user_id ?? "—"}`}
                    </h3>
                    <p className="text-xs text-slate-500">
                      {when(open.created_at)} · {open.chars} симв. · {open.model ?? "модель не записана"}
                      {open.cached ? " · ответ из кэша" : ""}
                      {open.succeeded ? "" : " · модель не ответила"}
                    </p>
                  </div>
                  <button className="text-slate-400 hover:text-slate-700" onClick={() => setOpen(null)}>
                    ✕
                  </button>
                </div>

                <h4 className="mt-4 text-sm font-semibold text-slate-700">Текст пользователя</h4>
                <pre className="mt-1 whitespace-pre-wrap rounded-xl bg-slate-50 p-3 text-sm text-slate-800">
                  {open.text ?? "не сохранялся (запись сделана до обновления)"}
                </pre>

                <h4 className="mt-4 text-sm font-semibold text-slate-700">Промт, отправленный модели</h4>
                <pre className="mt-1 max-h-72 overflow-auto whitespace-pre-wrap rounded-xl bg-slate-50 p-3 text-xs text-slate-700">
                  {open.prompt ?? "не сохранён"}
                </pre>

                <h4 className="mt-4 text-sm font-semibold text-slate-700">Ответ модели</h4>
                <pre className="mt-1 max-h-72 overflow-auto whitespace-pre-wrap rounded-xl bg-slate-50 p-3 text-xs text-slate-700">
                  {open.answer ?? "не сохранён"}
                </pre>

                <h4 className="mt-4 text-sm font-semibold text-slate-700">Настройки проверки</h4>
                <p className="mt-1 text-xs text-slate-600">
                  {Object.entries(open.params).length === 0
                    ? "не записаны"
                    : Object.entries(open.params)
                        .map(([k, v]) => `${k}: ${String(v)}`)
                        .join(" · ")}
                </p>
              </>
            )}
          </div>
        </div>
      )}
    </section>
  );
}

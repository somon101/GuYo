import axios from "axios";
import { useCallback, useEffect, useState } from "react";
import {
  getSyncJournalEntry,
  listSyncJournal,
  type SyncJournalDetail,
  type SyncJournalEntry,
} from "../api/endpoints";

function errorText(e: unknown): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return "Не удалось загрузить синхронизацию";
}

function when(iso: string): string {
  return new Date(iso).toLocaleString("ru-RU", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

const ACTION_LABELS: Record<string, string> = {
  start: "открытие прохода",
  answer: "ответ",
  finish: "закрытие прохода",
};

const PAGE = 50;

/** «Синхронизация»: every packet a device sent to sync a lesson pass, as cards.
 *
 * A pass is handed over as three kinds of actions in order -- open, each answer,
 * finish. Each card says who, which lesson, what the action was, and whether the
 * server accepted it; opening one shows the full payload (what was actually sent)
 * next to the server's verdict. This is what answers "why does the lesson still
 * read 0%?" without a debugger. */
export function SyncJournal() {
  const [entries, setEntries] = useState<SyncJournalEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lessonId, setLessonId] = useState("");
  const [userId, setUserId] = useState("");
  const [onlyRejected, setOnlyRejected] = useState(false);
  const [open, setOpen] = useState<SyncJournalDetail | null>(null);
  const [openLoading, setOpenLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const l = lessonId.trim() === "" ? undefined : Number(lessonId.trim());
      const u = userId.trim() === "" ? undefined : Number(userId.trim());
      const data = await listSyncJournal(
        {
          ...(l !== undefined && !Number.isNaN(l) ? { lessonId: l } : {}),
          ...(u !== undefined && !Number.isNaN(u) ? { userId: u } : {}),
          onlyRejected,
        },
        PAGE,
        offset,
      );
      setEntries(data.entries);
      setTotal(data.total);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setLoading(false);
    }
  }, [offset, lessonId, userId, onlyRejected]);

  useEffect(() => {
    void load();
  }, [load]);

  async function openEntry(id: number) {
    setOpenLoading(true);
    try {
      setOpen(await getSyncJournalEntry(id));
    } catch (e) {
      setError(errorText(e));
    } finally {
      setOpenLoading(false);
    }
  }

  const pages = Math.max(1, Math.ceil(total / PAGE));
  const page = Math.floor(offset / PAGE) + 1;

  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-bold text-slate-900">Синхронизация</h2>
          <p className="text-sm text-slate-500">
            Что телефон прислал, чтобы синхронизировать проход, и что сервер с этим сделал. Всего: {total}.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <input
            className="w-28 rounded-lg border border-slate-200 px-3 py-1.5 text-sm"
            placeholder="Урок ID"
            value={lessonId}
            onChange={(e) => {
              setOffset(0);
              setLessonId(e.target.value);
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
              checked={onlyRejected}
              onChange={(e) => {
                setOffset(0);
                setOnlyRejected(e.target.checked);
              }}
            />
            только отклонённые
          </label>
        </div>
      </div>

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}

      <div className="mt-4 space-y-2">
        {loading && entries.length === 0 && <p className="text-sm text-slate-500">Загружаем…</p>}
        {!loading && entries.length === 0 && !error && (
          <p className="text-sm text-slate-500">Записей пока нет — они появятся после первой синхронизации урока.</p>
        )}
        {entries.map((entry) => (
          <button
            key={entry.id}
            onClick={() => void openEntry(entry.id)}
            className="block w-full rounded-xl border border-slate-200 p-3 text-left transition hover:border-indigo-300 hover:bg-indigo-50/40"
          >
            <div className="flex flex-wrap items-center gap-2 text-xs text-slate-500">
              <span className="font-semibold text-slate-700">{entry.user_login || `id ${entry.user_id ?? "—"}`}</span>
              <span>урок {entry.lesson_id ?? "—"}</span>
              <span>{ACTION_LABELS[entry.action] ?? entry.action}</span>
              {entry.exercise_key && <span>{entry.exercise_key}</span>}
              {entry.word_id !== null && entry.word_id !== undefined && <span>слово {entry.word_id}</span>}
              <span>{when(entry.created_at)}</span>
              {entry.accepted ? (
                <span className="rounded-full bg-green-100 px-2 py-0.5 font-semibold text-green-700">принято</span>
              ) : (
                <span className="rounded-full bg-red-100 px-2 py-0.5 font-semibold text-red-700">отклонено</span>
              )}
            </div>
            {entry.outcome && <p className="mt-1 text-sm text-slate-600">{entry.outcome}</p>}
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
          <div className="mt-10 w-full max-w-2xl rounded-2xl bg-white p-5 shadow-xl" onClick={(e) => e.stopPropagation()}>
            {openLoading && !open && <p className="text-sm text-slate-500">Открываем…</p>}
            {open && (
              <>
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <h3 className="text-base font-bold text-slate-900">
                      {ACTION_LABELS[open.action] ?? open.action} — {open.user_login || `id ${open.user_id ?? "—"}`}
                    </h3>
                    <p className="text-xs text-slate-500">
                      урок {open.lesson_id ?? "—"} · {when(open.created_at)}
                      {open.exercise_key ? ` · ${open.exercise_key}` : ""}
                      {open.word_id !== null && open.word_id !== undefined ? ` · слово ${open.word_id}` : ""}
                    </p>
                  </div>
                  <button className="text-slate-400 hover:text-slate-700" onClick={() => setOpen(null)}>
                    ✕
                  </button>
                </div>

                <div className="mt-3 flex items-center gap-2">
                  {open.accepted ? (
                    <span className="rounded-full bg-green-100 px-2 py-0.5 text-sm font-semibold text-green-700">
                      принято
                    </span>
                  ) : (
                    <span className="rounded-full bg-red-100 px-2 py-0.5 text-sm font-semibold text-red-700">
                      отклонено
                    </span>
                  )}
                  {open.outcome && <span className="text-sm text-slate-600">{open.outcome}</span>}
                </div>

                <h4 className="mt-4 text-sm font-semibold text-slate-700">Что прислал телефон</h4>
                <pre className="mt-1 max-h-80 overflow-auto whitespace-pre-wrap rounded-xl bg-slate-50 p-3 text-xs text-slate-800">
                  {open.payload != null ? JSON.stringify(open.payload, null, 2) : "пустое тело (действие без данных)"}
                </pre>
              </>
            )}
          </div>
        </div>
      )}
    </section>
  );
}

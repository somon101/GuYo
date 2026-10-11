import axios from "axios";
import { useEffect, useState } from "react";
import {
  cancelMiniPhraseJob,
  currentBulkMiniPhrases,
  getMiniPhraseJob,
  startBulkMiniPhrases,
  type MiniPhraseJob,
} from "../api/endpoints";

/** «Массовая генерация»: a server job that keeps generating, rating and
 * fixing until N mini-phrases rated 4–5★ are saved. Progress is polled, so
 * the page can be closed and reopened. */
export function BulkMiniPhrases({
  dictionaryId,
  categoryId,
}: {
  dictionaryId: number;
  categoryId: number | null;
}) {
  const [count, setCount] = useState(500);
  const [job, setJob] = useState<MiniPhraseJob | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    currentBulkMiniPhrases(dictionaryId)
      .then(setJob)
      .catch(() => setJob(null));
  }, [dictionaryId]);

  const running = job?.state === "running";
  useEffect(() => {
    if (!running || !job) return;
    const t = setInterval(() => {
      getMiniPhraseJob(job.id)
        .then(setJob)
        .catch(() => {});
    }, 4000);
    return () => clearInterval(t);
  }, [running, job?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  async function start() {
    setError(null);
    try {
      setJob(await startBulkMiniPhrases(dictionaryId, count, categoryId));
    } catch (e) {
      setError(
        axios.isAxiosError(e) && typeof e.response?.data?.detail === "string"
          ? e.response.data.detail
          : "Не удалось запустить",
      );
    }
  }

  const pct = job
    ? Math.min(100, Math.round((100 * job.saved) / job.target))
    : 0;
  const minutes = job
    ? Math.max(0, Math.round((Date.now() / 1000 - job.started_at) / 60))
    : 0;

  return (
    <div className="rounded-xl bg-[var(--fill)] p-4">
      <p className="text-[15px] font-semibold text-slate-900">
        Массовая генерация
      </p>
      <p className="mt-1 text-sm text-slate-600">
        Сервер сам делает пачки по 25 фраз: ИИ составляет, строгий ИИ-редактор
        ставит каждой 1–5★, плохие исправляются или пересоздаются. Сохраняются{" "}
        <b>сразу в мини-фразы</b> только фразы на 4–5★, без повторов и похожих.
        Темы чередуются. Можно закрыть страницу — работа продолжится.
      </p>

      {!running && (
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-sm text-slate-700">
            <span className="mb-1 block text-xs text-slate-500">
              Сколько хороших фраз нужно
            </span>
            <input
              type="number"
              min={10}
              max={2000}
              className="field w-28 px-3 py-2 text-sm"
              value={count}
              onChange={(e) =>
                setCount(
                  Math.max(10, Math.min(2000, Number(e.target.value) || 500)),
                )
              }
            />
          </label>
          <button
            onClick={start}
            className="rounded-md bg-violet-600 px-4 py-2 text-sm font-medium text-white hover:bg-violet-700"
          >
            Запустить: {count} фраз
          </button>
        </div>
      )}
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}

      {job && (
        <div className="mt-4 flex flex-col gap-2">
          <div className="h-2.5 overflow-hidden rounded-full bg-[var(--card)]">
            <div
              className="h-full rounded-full bg-violet-600 transition-all"
              style={{ width: `${pct}%` }}
            />
          </div>
          <p className="text-sm text-slate-800">
            <b>
              {job.saved} / {job.target}
            </b>{" "}
            сохранено · пачек: {job.batches} · в мусор: {job.rejected} ·
            токенов: {job.tokens.toLocaleString("ru")}
            {job.forms_added > 0 && ` · новых форм: ${job.forms_added}`}
            {job.templates_created > 0 &&
              ` · новых шаблонов: ${job.templates_created}`}
            {running && ` · идёт ${minutes} мин`}
          </p>
          <p
            className={`text-sm ${job.state === "failed" ? "text-red-600" : "text-slate-600"}`}
          >
            {job.state === "failed" ? job.error : job.message}
          </p>
          {running && (
            <button
              onClick={async () => setJob(await cancelMiniPhraseJob(job.id))}
              disabled={job.cancel}
              className="self-start rounded-md px-3 py-1.5 text-sm text-red-600 hover:bg-red-50 disabled:opacity-50"
            >
              {job.cancel
                ? "Останавливается после текущей пачки…"
                : "Остановить"}
            </button>
          )}
          {job.recent.length > 0 && (
            <div className="rounded-lg bg-[var(--card)] p-3">
              <p className="mb-1 text-xs text-slate-500">
                Последние сохранённые:
              </p>
              <p className="text-sm text-slate-700" translate="no">
                {job.recent.join(" · ")}
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

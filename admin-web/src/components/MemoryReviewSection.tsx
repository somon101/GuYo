import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getUserReviewLists, type ReviewListInfo, type UserReviewLists } from "../api/endpoints";

export const pct = (v: number | null | undefined) => (v == null ? "—" : `${Math.round(v * 100)}%`);

export function dateTime(at: string | null | undefined): string {
  if (!at) return "—";
  return new Date(at).toLocaleString("ru-RU", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

const STATUS: Record<ReviewListInfo["status"], { label: string; cls: string }> = {
  active: { label: "Активный — виден в «Повторить сегодня»", cls: "bg-emerald-100 text-emerald-800" },
  queued: { label: "В очереди", cls: "bg-amber-100 text-amber-800" },
  closed: { label: "Закрыт", cls: "bg-slate-100 text-slate-600" },
};

/** «Память»: the user's «Повторить сегодня» lists — the active one, the
 * queue and the last closed ones. Each word opens its full memory card. */
export function MemoryReviewSection({ userId, dictionaryId }: { userId: number; dictionaryId: number }) {
  const [data, setData] = useState<UserReviewLists | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showClosed, setShowClosed] = useState(false);

  useEffect(() => {
    setData(null);
    setError(null);
    getUserReviewLists(userId, dictionaryId)
      .then(setData)
      .catch(() => setError("Не удалось загрузить списки повторения"));
  }, [userId, dictionaryId]);

  return (
    <section className="card p-5">
      <h2 className="mb-1 text-lg font-semibold text-slate-900">Память — «Повторить сегодня»</h2>
      {data && (
        <p className="mb-4 text-xs text-slate-500">
          Список создаётся, когда набирается {data.settings.list_size} выученных слов с шансом вспомнить ниже{" "}
          {pct(data.settings.target)}; в очереди не больше {data.settings.max_open_lists}. Уроки список не меняют —
          слово уходит из него только после правильного ответа в повторении.
        </p>
      )}
      {error ? (
        <p className="text-sm text-red-600">{error}</p>
      ) : !data ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : (
        <div className="flex flex-col gap-4">
          {data.open.length === 0 && <p className="text-sm text-slate-500">Сейчас слов на повторение нет.</p>}
          {data.open.map((l) => (
            <ListCard key={l.id} list={l} userId={userId} />
          ))}
          {data.closed.length > 0 && (
            <button className="self-start text-sm text-sky-700 hover:underline" onClick={() => setShowClosed(!showClosed)}>
              {showClosed ? "Скрыть закрытые" : `Закрытые списки (${data.closed.length})`}
            </button>
          )}
          {showClosed && data.closed.map((l) => <ListCard key={l.id} list={l} userId={userId} />)}
        </div>
      )}
    </section>
  );
}

function ListCard({ list, userId }: { list: ReviewListInfo; userId: number }) {
  const s = STATUS[list.status];
  return (
    <div className="rounded-xl border border-slate-200">
      <div className="flex flex-wrap items-center gap-2 border-b border-slate-100 px-4 py-2 text-xs text-slate-500">
        <span className="font-semibold text-slate-800">Список №{list.id}</span>
        <span className={`rounded-full px-2 py-0.5 font-medium ${s.cls}`}>{s.label}</span>
        <span>
          пройдено {list.done} из {list.words.length}
        </span>
        <span>· создан {dateTime(list.created_at)}</span>
        {list.activated_at && <span>· активен с {dateTime(list.activated_at)}</span>}
        <span>· пуш: {list.notified_at ? dateTime(list.notified_at) : "ещё не было"}</span>
        {list.closed_at && <span>· закрыт {dateTime(list.closed_at)}</span>}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs text-slate-400">
            <tr>
              <th className="px-4 py-2">#</th>
              <th className="px-2 py-2">Слово</th>
              <th className="px-2 py-2">Шанс при попадании</th>
              <th className="px-2 py-2">Шанс сейчас</th>
              <th className="px-2 py-2">Статус</th>
            </tr>
          </thead>
          <tbody>
            {list.words.map((w) => (
              <tr key={w.word_id} className="border-t border-slate-100 hover:bg-slate-50">
                <td className="px-4 py-2 text-slate-400">{w.position}</td>
                <td className="px-2 py-2">
                  <Link className="font-medium text-sky-700 hover:underline" to={`/analytics/users/${userId}/memory/${w.word_id}`}>
                    {w.word}
                  </Link>
                  {w.translation && <span className="ml-2 text-slate-400">{w.translation}</span>}
                </td>
                <td className="px-2 py-2 text-red-600">
                  {pct(w.recall_at_entry)} <span className="text-slate-400">&lt; {pct(w.target)}</span>
                </td>
                <td className="px-2 py-2">{pct(w.recall_now)}</td>
                <td className="px-2 py-2">
                  {w.done_at ? (
                    <span className="text-emerald-700">✓ {dateTime(w.done_at)}</span>
                  ) : (
                    <span className="text-slate-500">ждёт верного ответа</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

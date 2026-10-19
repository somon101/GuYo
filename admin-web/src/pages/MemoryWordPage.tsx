import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { getMemoryWord, type MemoryAttempt, type MemoryDay, type MemoryWord } from "../api/endpoints";
import { dateTime, pct } from "../components/MemoryReviewSection";

const EXERCISES: Record<string, string> = {
  true_or_false: "Правда или ложь",
  matching: "Сопоставление",
  build_word: "Собери слово",
  speaking_word: "Произнеси слово",
  listen_word: "Услышь слово",
};
const exercise = (k: string) => EXERCISES[k] ?? k;

const SOURCES: Record<MemoryAttempt["source"], string> = {
  lesson: "урок",
  quest: "квест",
  practice: "практика",
  review: "повторение",
};

const GRADES: Record<MemoryDay["grade"], { label: string; cls: string }> = {
  again: { label: "Забыл", cls: "bg-red-100 text-red-700" },
  hard: { label: "С трудом", cls: "bg-amber-100 text-amber-800" },
  good: { label: "Хорошо", cls: "bg-emerald-100 text-emerald-800" },
  easy: { label: "Легко", cls: "bg-sky-100 text-sky-800" },
};

const num = (v: number | null | undefined, digits = 1) => (v == null ? "—" : v.toFixed(digits));

/** Аналитика → «Память» → слово: why the memory model put this word into
 * «Повторить сегодня» — its state now, every list it was frozen into and
 * the numbers at that moment, the day-by-day history that produced them
 * (each day's grade and its reason), every answer, the errors, and the
 * forgetting curve. Everything is computed by the server. */
export function MemoryWordPage() {
  const { userId, wordId } = useParams();
  const [data, setData] = useState<MemoryWord | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getMemoryWord(Number(userId), Number(wordId))
      .then(setData)
      .catch(() => setError("Не удалось загрузить карточку слова"));
  }, [userId, wordId]);

  if (error) return <p className="text-sm text-red-600">{error}</p>;
  if (!data) return <p className="text-sm text-slate-500">Загрузка…</p>;
  const st = data.state;
  const target = data.settings.target;
  const current = data.lists.find((l) => l.status !== "closed");

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <Link to="/analytics" className="text-sm text-sky-700 hover:underline">
          ← Аналитика
        </Link>
        <h1 className="mt-2 text-[26px] font-bold tracking-tight text-slate-900">
          {data.word}
          {data.translation && <span className="ml-3 text-lg font-normal text-slate-400">{data.translation}</span>}
        </h1>
        <p className="text-sm text-slate-500">
          Память пользователя {data.user_login} ·{" "}
          <Link className="text-sky-700 hover:underline" to={`/analytics/users/${data.user_id}/words/${data.word_id}`}>
            диагностика слова
          </Link>
        </p>
      </div>

      <section className="card p-5">
        <h2 className="mb-3 text-lg font-semibold text-slate-900">Почему слово в повторении</h2>
        {data.lists.length === 0 ? (
          <p className="text-sm text-slate-600">
            Слово ни разу не попадало в «Повторить сегодня».{" "}
            {st.recall_now != null && st.recall_now < target && st.learned
              ? `Шанс вспомнить уже ${pct(st.recall_now)} (< ${pct(target)}) — попадёт в следующий список, когда наберётся ${data.settings.list_size} таких слов и в очереди будет место.`
              : !st.learned
                ? `Слово ещё не выучено (балл ${st.score} < ${data.settings.learned_threshold}) — в повторение берутся только выученные.`
                : `Шанс вспомнить ${pct(st.recall_now)} — не ниже ${pct(target)}.`}
          </p>
        ) : (
          <>
            {current && (
              <p className="mb-3 rounded-lg bg-sky-50 p-3 text-sm text-sky-900">
                Попало в список №{current.list_id} {dateTime(current.created_at)}: шанс вспомнить был{" "}
                <b>{pct(current.recall_at_entry)}</b> — ниже порога {pct(current.target)}. Место в списке:{" "}
                {current.position} из {current.list_size} (самые забываемые — первыми).{" "}
                {current.done_at
                  ? `Отвечено верно ${dateTime(current.done_at)}.`
                  : current.status === "active"
                    ? "Ждёт правильного ответа в повторении."
                    : "Список ждёт в очереди."}
              </p>
            )}
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-slate-400">
                  <tr>
                    <th className="py-2 pr-2">Список</th>
                    <th className="px-2">Создан</th>
                    <th className="px-2">Шанс / порог</th>
                    <th className="px-2">Прочность</th>
                    <th className="px-2">Трудность</th>
                    <th className="px-2">Посл. повтор</th>
                    <th className="px-2">Дней повт.</th>
                    <th className="px-2">Итог</th>
                  </tr>
                </thead>
                <tbody>
                  {data.lists.map((l) => (
                    <tr key={l.list_id} className="border-t border-slate-100">
                      <td className="py-2 pr-2">
                        №{l.list_id} <span className="text-xs text-slate-400">({l.status === "active" ? "активный" : l.status === "queued" ? "в очереди" : "закрыт"})</span>
                      </td>
                      <td className="px-2">{dateTime(l.created_at)}</td>
                      <td className="px-2 text-red-600">
                        {pct(l.recall_at_entry)} / {pct(l.target)}
                      </td>
                      <td className="px-2">{num(l.stability_at_entry)} дн.</td>
                      <td className="px-2">{num(l.difficulty_at_entry)}</td>
                      <td className="px-2">{dateTime(l.last_review_at_entry)}</td>
                      <td className="px-2">{l.review_days_at_entry}</td>
                      <td className="px-2">{l.done_at ? `✓ ${dateTime(l.done_at)}` : "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </section>

      <section className="card p-5">
        <h2 className="mb-3 text-lg font-semibold text-slate-900">Состояние сейчас</h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat label="Шанс вспомнить" value={pct(st.recall_now)} hint={`порог ${pct(target)}`} bad={st.recall_now != null && st.recall_now < target} />
          <Stat label="Прочность" value={`${num(st.stability)} дн.`} hint="через сколько дней шанс упадёт до 90%" />
          <Stat label="Трудность" value={num(st.difficulty)} hint="1 — легко, 10 — очень трудно" />
          <Stat label="Балл слова" value={String(st.score)} hint={st.learned ? "выучено" : `не выучено (< ${data.settings.learned_threshold})`} />
          <Stat label="Последний повтор" value={dateTime(st.last_review)} />
          <Stat label="Дней повторения" value={String(st.review_days)} />
          <Stat label={`Ниже ${pct(target)}`} value={dateTime(st.falls_below_at)} hint="когда шанс опустится ниже порога" />
        </div>
        <RecallChart points={data.curve} target={target} />
      </section>

      <section className="card p-5">
        <h2 className="mb-1 text-lg font-semibold text-slate-900">История по дням</h2>
        <p className="mb-4 text-xs text-slate-500">
          Один день (по Душанбе) — одна оценка памяти. Все ответы за день оцениваются вместе.
        </p>
        <div className="flex flex-col gap-3">
          {data.days.length === 0 && <p className="text-sm text-slate-500">Ответов по слову ещё нет.</p>}
          {data.days.map((d) => (
            <DayCard key={d.day} day={d} />
          ))}
        </div>
      </section>

      <section className="card p-5">
        <h2 className="mb-3 text-lg font-semibold text-slate-900">Ошибки</h2>
        <div className="mb-4 flex flex-wrap gap-2">
          {data.errors_by_exercise.map((b) => (
            <span key={b.exercise_key} className="rounded-lg bg-slate-100 px-3 py-1 text-sm">
              {exercise(b.exercise_key)}: <b className={b.errors ? "text-red-600" : ""}>{b.errors}</b> ош. из {b.total}
              {b.timeouts > 0 && <span className="text-slate-500"> · {b.timeouts} не успел</span>}
            </span>
          ))}
        </div>
        {data.recent_errors.length === 0 ? (
          <p className="text-sm text-slate-500">Ошибок нет.</p>
        ) : (
          <AttemptsTable attempts={data.recent_errors} withDate />
        )}
      </section>
    </div>
  );
}

function Stat({ label, value, hint, bad }: { label: string; value: string; hint?: string; bad?: boolean }) {
  return (
    <div className="rounded-xl bg-slate-50 p-3">
      <div className="text-xs text-slate-500">{label}</div>
      <div className={`text-lg font-semibold ${bad ? "text-red-600" : "text-slate-900"}`}>{value}</div>
      {hint && <div className="text-[11px] text-slate-400">{hint}</div>}
    </div>
  );
}

function DayCard({ day }: { day: MemoryDay }) {
  const [open, setOpen] = useState(false);
  const g = GRADES[day.grade];
  return (
    <div className="rounded-xl border border-slate-200">
      <button className="flex w-full flex-wrap items-center gap-2 px-4 py-3 text-left text-sm" onClick={() => setOpen(!open)}>
        <span className="font-semibold text-slate-900">{new Date(day.day).toLocaleDateString("ru-RU")}</span>
        <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${g.cls}`}>{g.label}</span>
        <span className="text-slate-500">
          ✓ {day.correct} · ✗ {day.errors}
        </span>
        {day.recall_before != null && <span className="text-slate-500">· шанс перед днём {pct(day.recall_before)}</span>}
        {day.days_since_previous != null && <span className="text-slate-500">· через {num(day.days_since_previous)} дн.</span>}
        <span className="text-slate-500">
          · после: прочность {num(day.stability_after)} дн., трудность {num(day.difficulty_after)}
        </span>
        <span className="ml-auto text-xs text-sky-700">{open ? "скрыть ответы" : `ответы (${day.attempts.length})`}</span>
      </button>
      <p className="px-4 pb-3 text-sm text-slate-600">{day.reason}</p>
      {open && (
        <div className="border-t border-slate-100 px-2 pb-2">
          <AttemptsTable attempts={day.attempts} />
        </div>
      )}
    </div>
  );
}

function AttemptsTable({ attempts, withDate }: { attempts: MemoryAttempt[]; withDate?: boolean }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="text-left text-xs text-slate-400">
          <tr>
            <th className="px-2 py-2">Время</th>
            <th className="px-2">Где</th>
            <th className="px-2">Упражнение</th>
            <th className="px-2">Результат</th>
            <th className="px-2">Ответ</th>
            <th className="px-2">Думал</th>
            <th className="px-2">Балл</th>
          </tr>
        </thead>
        <tbody>
          {attempts.map((a) => (
            <tr key={a.id} className="border-t border-slate-100 align-top">
              <td className="px-2 py-2 whitespace-nowrap text-slate-600">
                {withDate ? dateTime(a.created_at) : new Date(a.created_at).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })}
              </td>
              <td className="px-2 py-2">
                {SOURCES[a.source]}
                {a.lesson_number != null && <span className="text-slate-500"> №{a.lesson_number}</span>}
                {a.review_list_id != null && <span className="text-slate-500"> (список №{a.review_list_id})</span>}
                {a.phrase && <div className="text-xs text-slate-500">фраза: «{a.phrase}»</div>}
                {a.mini_phrase && <div className="text-xs text-slate-500">мини-фраза: «{a.mini_phrase}»</div>}
              </td>
              <td className="px-2 py-2">{exercise(a.exercise_key)}</td>
              <td className="px-2 py-2">
                {a.timed_out ? (
                  <span className="text-amber-700">не успел</span>
                ) : a.is_correct ? (
                  <span className="text-emerald-700">верно</span>
                ) : (
                  <span className="text-red-600">ошибка</span>
                )}
              </td>
              <td className="px-2 py-2 text-slate-600">{a.given_answer ?? "—"}</td>
              <td className="px-2 py-2 text-slate-600">{a.duration_ms != null ? `${(a.duration_ms / 1000).toFixed(1)} с` : "—"}</td>
              <td className="px-2 py-2 text-slate-600">{a.score_after}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** The forgetting curve: recall at the end of each day, with the target line. */
function RecallChart({ points, target }: { points: { at: string; recall: number }[]; target: number }) {
  if (points.length < 2) return null;
  const width = 640;
  const height = 160;
  const pad = 10;
  const x = (i: number) => pad + (i * (width - pad * 2)) / (points.length - 1);
  const y = (r: number) => pad + (1 - r) * (height - pad * 2);
  const path = points.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(p.recall).toFixed(1)}`).join(" ");
  return (
    <div className="mt-5">
      <div className="mb-1 text-xs text-slate-500">
        Шанс вспомнить по дням (пунктир — порог {pct(target)}); скачки вверх — дни повторения
      </div>
      <svg viewBox={`0 0 ${width} ${height}`} className="h-40 w-full">
        <line x1={pad} x2={width - pad} y1={y(target)} y2={y(target)} stroke="#ef4444" strokeDasharray="4 4" strokeWidth={1} />
        <path d={path} fill="none" stroke="#0284c7" strokeWidth={2} />
      </svg>
      <div className="flex justify-between text-[11px] text-slate-400">
        <span>{new Date(points[0].at).toLocaleDateString("ru-RU")}</span>
        <span>{new Date(points[points.length - 1].at).toLocaleDateString("ru-RU")}</span>
      </div>
    </div>
  );
}

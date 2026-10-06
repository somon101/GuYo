import { useEffect, useState } from "react";
import { getUserHistory, type UserHistory, type UserHistoryItem } from "../api/endpoints";

const EXERCISES: Record<string, string> = {
  true_or_false: "Правда или ложь",
  matching: "Сопоставление",
  build_word: "Собери слово",
  speaking_word: "Произнеси слово",
  listen_word: "Услышь слово",
};

const SOURCES: Record<string, string> = { lesson: "урок", practice: "практика", quest: "квест" };

const PERIODS = [1, 7, 30, 90];

function time(at: string): string {
  return new Date(at).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
}

function day(at: string): string {
  return new Date(at).toLocaleDateString("ru-RU", { weekday: "short", day: "numeric", month: "long" });
}

function lessonName(item: UserHistoryItem): string {
  const n = item.lesson_number ?? item.data?.number;
  return n != null ? `урок ${n}` : "урок";
}

/** One readable line per step. */
function describe(item: UserHistoryItem): { icon: string; text: string; tone: "ok" | "bad" | "info" } {
  const d = item.data ?? {};
  switch (item.kind) {
    case "answer": {
      const where = `${SOURCES[item.source ?? ""] ?? item.source}${item.lesson_number ? ` ${item.lesson_number}` : ""}`;
      const ex = EXERCISES[item.exercise_key ?? ""] ?? item.exercise_key;
      const secs = item.duration_ms != null ? ` · ${(item.duration_ms / 1000).toFixed(1)} с` : "";
      if (item.is_correct) {
        return { icon: "✅", tone: "ok", text: `«${item.word}» (${item.translation ?? "—"}) — верно · ${ex} · ${where}${secs}` };
      }
      const given = item.timed_out
        ? "время вышло"
        : item.given_answer
          ? `ответил «${item.given_answer}»`
          : "неверно";
      return { icon: "❌", tone: "bad", text: `«${item.word}» (${item.translation ?? "—"}) — ${given} · ${ex} · ${where}${secs}` };
    }
    case "lesson_created":
      return {
        icon: d.adaptive ? "🤖" : "📘",
        tone: "info",
        text: `${d.adaptive ? "Автоматически создан персональный" : "Создан"} ${lessonName(item)} (${d.words} слов)`,
      };
    case "lesson_opened":
      return { icon: "▶️", tone: "info", text: `Открыл ${lessonName(item)}` };
    case "lesson_left":
      return {
        icon: "🚪",
        tone: "bad",
        text: `Вышел из ${lessonName(item)}${d.exercise ? ` на упражнении ${d.exercise}${d.of ? ` из ${d.of}` : ""}` : ""}`,
      };
    case "lesson_completed":
      return { icon: "🏁", tone: "ok", text: `Прошёл ${lessonName(item)}${d.adaptive ? " (персональный)" : ""}` };
    case "personal_quest_created":
      return { icon: "🎯", tone: "info", text: `Появился персональный квест «${d.name}» (${d.words} слов)` };
    case "quest_opened":
      return { icon: "▶️", tone: "info", text: `Открыл квест${d.name ? ` «${d.name}»` : ""}` };
    case "quest_left":
      return { icon: "🚪", tone: "bad", text: `Вышел из квеста${d.name ? ` «${d.name}»` : ""}` };
    case "quest_answered":
      return {
        icon: d.correct ? "🏆" : "💥",
        tone: d.correct ? "ok" : "bad",
        text: `${d.personal ? "Персональный квест" : "Квест"} «${d.name}»: «${d.word}» — ${d.correct ? "решил" : "не решил"}`,
      };
    case "app_opened":
      return { icon: "📱", tone: "info", text: "Открыл приложение" };
    default:
      return { icon: "•", tone: "info", text: item.kind };
  }
}

const TONE = { ok: "text-slate-700", bad: "text-red-700", info: "text-indigo-700" };

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-lg font-semibold text-slate-900">{value}</div>
      <div className="text-xs text-slate-500">{label}</div>
    </div>
  );
}

/** «История»: every answer and step of one learner, newest first
 * (backend app/analytics/history.py). */
export function UserHistorySection({ userId }: { userId: number }) {
  const [days, setDays] = useState(7);
  const [history, setHistory] = useState<UserHistory | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setHistory(null);
    setError(null);
    getUserHistory(userId, days)
      .then(setHistory)
      .catch(() => setError("Не удалось загрузить историю"));
  }, [userId, days]);

  const s = history?.summary;
  const accuracy = s && s.answers ? Math.round((s.correct / s.answers) * 100) : null;

  const groups: { day: string; items: UserHistoryItem[] }[] = [];
  for (const item of history?.items ?? []) {
    const d = day(item.at);
    if (groups.length === 0 || groups[groups.length - 1].day !== d) groups.push({ day: d, items: [] });
    groups[groups.length - 1].items.push(item);
  }

  return (
    <section className="card p-5">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">История</h2>
        <div className="flex gap-1">
          {PERIODS.map((p) => (
            <button
              key={p}
              onClick={() => setDays(p)}
              className={`rounded-full px-3 py-1 text-xs font-medium ${p === days ? "bg-indigo-600 text-white" : "btn-tinted"}`}
            >
              {p === 1 ? "сутки" : `${p} дн.`}
            </button>
          ))}
        </div>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {!history && !error && <p className="text-sm text-slate-500">Загрузка истории…</p>}

      {s && (
        <>
          <div className="mb-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Stat label="ответов" value={s.answers} />
            <Stat label="точность" value={accuracy != null ? `${accuracy}%` : "—"} />
            <Stat label="время вышло" value={s.timed_out} />
            <Stat label="открытий приложения" value={s.app_opens} />
            <Stat label="уроков создано / пройдено" value={`${s.lessons_created} / ${s.lessons_completed}`} />
            <Stat label="из них персональных" value={s.adaptive_lessons_created} />
            <Stat label="выходов из урока" value={s.lessons_left} />
            <Stat
              label="перс. квесты: появилось / решено"
              value={`${s.personal_quests_created} / ${s.personal_quest_correct} из ${s.personal_quest_answers}`}
            />
          </div>

          {s.top_mistakes.length > 0 && (
            <div className="mb-4">
              <div className="mb-1 text-xs font-semibold text-slate-500">Чаще всего ошибается</div>
              <div className="flex flex-wrap gap-1.5">
                {s.top_mistakes.map((m) => (
                  <span key={m.word_id} className="rounded-full bg-red-50 px-2.5 py-1 text-xs text-red-700">
                    {m.word} ({m.translation ?? "—"}) × {m.wrong}
                  </span>
                ))}
              </div>
            </div>
          )}

          {groups.length === 0 ? (
            <p className="text-sm text-slate-500">За этот период ничего не было.</p>
          ) : (
            <div className="max-h-[600px] overflow-y-auto pr-1">
              {groups.map((g) => (
                <div key={g.day} className="mb-3">
                  <div className="sticky top-0 bg-white py-1 text-xs font-semibold text-slate-500">{g.day}</div>
                  <ul className="flex flex-col gap-0.5">
                    {g.items.map((item, i) => {
                      const line = describe(item);
                      return (
                        <li key={i} className={`flex gap-2 text-sm ${TONE[line.tone]}`}>
                          <span className="w-11 shrink-0 tabular-nums text-slate-400">{time(item.at)}</span>
                          <span className="w-5 shrink-0">{line.icon}</span>
                          <span>{line.text}</span>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              ))}
            </div>
          )}
          <p className="mt-2 text-xs text-slate-400">
            Записанный ответ («ответил …») и события «открыл / вышел» появляются с новой версии приложения.
          </p>
        </>
      )}
    </section>
  );
}

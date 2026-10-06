import { useEffect, useState, type ReactNode } from "react";
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

type Tone = "ok" | "bad" | "info";
type Line = { icon: string; title: string; detail?: string; tone: Tone };

/** One step as a bold title and a quieter detail line. */
function describe(item: UserHistoryItem): Line {
  const d = item.data ?? {};
  switch (item.kind) {
    case "answer": {
      const where = `${SOURCES[item.source ?? ""] ?? item.source}${item.lesson_number ? ` ${item.lesson_number}` : ""}`;
      const ex = EXERCISES[item.exercise_key ?? ""] ?? item.exercise_key;
      const secs = item.duration_ms != null ? `${(item.duration_ms / 1000).toFixed(1)} с` : null;
      const meta = [ex, where, secs].filter(Boolean).join(" · ");
      const title = `${item.word} — ${item.translation ?? "—"}`;
      if (item.is_correct) return { icon: "✅", tone: "ok", title, detail: meta };
      const given = item.timed_out
        ? "Время вышло"
        : item.given_answer
          ? `Ответил «${item.given_answer}»`
          : "Ошибся";
      return { icon: "❌", tone: "bad", title, detail: `${given} · ${meta}` };
    }
    case "lesson_created":
      return {
        icon: d.adaptive ? "🤖" : "📘",
        tone: "info",
        title: d.adaptive ? `Появился персональный ${lessonName(item)}` : `Создал ${lessonName(item)}`,
        detail: `${d.words} слов`,
      };
    case "lesson_opened":
      return { icon: "▶️", tone: "info", title: `Открыл ${lessonName(item)}` };
    case "lesson_left":
      return {
        icon: "🚪",
        tone: "bad",
        title: `Вышел из ${lessonName(item).replace("урок", "урока")}`,
        detail: d.exercise ? `на упражнении ${d.exercise}${d.of ? ` из ${d.of}` : ""}` : undefined,
      };
    case "lesson_completed":
      return { icon: "🏁", tone: "ok", title: `Прошёл ${lessonName(item)}`, detail: d.adaptive ? "персональный" : undefined };
    case "personal_quest_created":
      return { icon: "🎯", tone: "info", title: "Появился персональный квест", detail: `${d.name} · ${d.words} слов` };
    case "quest_opened":
      return { icon: "▶️", tone: "info", title: "Открыл квест", detail: d.name };
    case "quest_left":
      return { icon: "🚪", tone: "bad", title: "Вышел из квеста", detail: d.name };
    case "quest_answered":
      return {
        icon: d.correct ? "🏆" : "💥",
        tone: d.correct ? "ok" : "bad",
        title: `${d.personal ? "Персональный квест" : "Квест"}: ${d.correct ? "решил" : "не решил"}`,
        detail: `${d.name} · ${d.word}`,
      };
    case "app_opened":
      return { icon: "📱", tone: "info", title: "Открыл приложение" };
    default:
      return { icon: "•", tone: "info", title: item.kind };
  }
}

// Theme variables only (index.css), so light and dark both read well.
const DOT: Record<Tone, string> = {
  ok: "bg-[color-mix(in_srgb,var(--sys-green)_18%,transparent)] text-[var(--sys-green-ink)]",
  bad: "bg-[color-mix(in_srgb,var(--sys-red)_18%,transparent)] text-[var(--sys-red-ink)]",
  info: "bg-[color-mix(in_srgb,var(--sys-blue)_18%,transparent)] text-[var(--sys-blue-ink)]",
};
const DETAIL: Record<Tone, string> = { ok: "text-slate-500", bad: "text-[var(--sys-red-ink)]", info: "text-slate-500" };

function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="rounded-xl bg-[var(--fill)] p-3">
      <div className="mb-2 text-xs font-semibold text-slate-500">{title}</div>
      <div className="flex flex-wrap gap-x-6 gap-y-2">{children}</div>
    </div>
  );
}

function Num({ value, label, tone }: { value: string | number; label: string; tone?: "ok" | "bad" }) {
  const color =
    tone === "ok" ? "text-[var(--sys-green-ink)]" : tone === "bad" ? "text-[var(--sys-red-ink)]" : "text-[var(--label)]";
  return (
    <div>
      <div className={`text-2xl font-bold leading-tight tabular-nums ${color}`}>{value}</div>
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
  const wrong = s ? s.answers - s.correct : 0;
  const questsFailed = s ? s.personal_quest_answers - s.personal_quest_correct : 0;

  const groups: { day: string; items: UserHistoryItem[] }[] = [];
  for (const item of history?.items ?? []) {
    const d = day(item.at);
    if (groups.length === 0 || groups[groups.length - 1].day !== d) groups.push({ day: d, items: [] });
    groups[groups.length - 1].items.push(item);
  }

  return (
    <section className="card p-5">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-lg font-semibold text-[var(--label)]">История</h2>
        <div className="flex gap-1">
          {PERIODS.map((p) => (
            <button
              key={p}
              onClick={() => setDays(p)}
              className={`rounded-full px-3 py-1 text-xs font-medium ${
                p === days ? "bg-[var(--sys-blue)] text-white" : "btn-tinted"
              }`}
            >
              {p === 1 ? "сутки" : `${p} дн.`}
            </button>
          ))}
        </div>
      </div>

      {error && <p className="text-sm text-[var(--sys-red-ink)]">{error}</p>}
      {!history && !error && <p className="text-sm text-slate-500">Загрузка истории…</p>}

      {s && (
        <>
          <div className="mb-4 grid gap-2 sm:grid-cols-2">
            <Group title="Ответы">
              <Num value={s.answers} label="всего" />
              <Num
                value={accuracy != null ? `${accuracy}%` : "—"}
                label="верно"
                tone={accuracy == null ? undefined : accuracy >= 80 ? "ok" : "bad"}
              />
              <Num value={wrong} label="ошибок" tone={wrong ? "bad" : undefined} />
              <Num value={s.timed_out} label="время вышло" tone={s.timed_out ? "bad" : undefined} />
            </Group>
            <Group title="Уроки">
              <Num value={s.lessons_created} label="создано" />
              <Num value={s.lessons_completed} label="пройдено" tone={s.lessons_completed ? "ok" : undefined} />
              <Num value={s.lessons_left} label="бросил" tone={s.lessons_left ? "bad" : undefined} />
              <Num value={s.adaptive_lessons_created} label="персональных" />
            </Group>
            <Group title="Персональные квесты">
              <Num value={s.personal_quests_created} label="появилось" />
              <Num value={s.personal_quest_correct} label="решил" tone={s.personal_quest_correct ? "ok" : undefined} />
              <Num value={questsFailed} label="не решил" tone={questsFailed ? "bad" : undefined} />
            </Group>
            <Group title="Приложение">
              <Num value={s.app_opens} label="открытий" />
            </Group>
          </div>

          {s.top_mistakes.length > 0 && (
            <div className="mb-4">
              <div className="mb-1.5 text-xs font-semibold text-slate-500">Чаще всего ошибается</div>
              <div className="flex flex-wrap gap-1.5">
                {s.top_mistakes.map((m) => (
                  <span key={m.word_id} className={`rounded-full px-2.5 py-1 text-xs font-medium ${DOT.bad}`}>
                    {m.word} — {m.translation ?? "—"} · {m.wrong}×
                  </span>
                ))}
              </div>
            </div>
          )}

          {groups.length === 0 ? (
            <p className="text-sm text-slate-500">За этот период ничего не было.</p>
          ) : (
            <div className="max-h-[640px] overflow-y-auto pr-1">
              {groups.map((g) => (
                <div key={g.day} className="mb-4">
                  <div className="sticky top-0 z-10 bg-[var(--card)] py-1.5 text-xs font-semibold uppercase tracking-wide text-slate-500">
                    {g.day}
                  </div>
                  <ul className="flex flex-col">
                    {g.items.map((item, i) => {
                      const line = describe(item);
                      return (
                        <li key={i} className="flex items-start gap-3 border-b border-[var(--separator)] py-2 last:border-0">
                          <span className="w-11 shrink-0 pt-0.5 text-xs tabular-nums text-slate-500">{time(item.at)}</span>
                          <span
                            className="w-7 shrink-0 text-center text-xl leading-6"
                          >
                            {line.icon}
                          </span>
                          <div className="min-w-0">
                            <div className="text-sm font-medium text-[var(--label)]">{line.title}</div>
                            {line.detail && <div className={`text-xs ${DETAIL[line.tone]}`}>{line.detail}</div>}
                          </div>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              ))}
            </div>
          )}
          <p className="mt-2 text-xs text-slate-500">
            Сам ответ («Ответил …») и «открыл / вышел» записываются только из новой версии приложения.
          </p>
        </>
      )}
    </section>
  );
}

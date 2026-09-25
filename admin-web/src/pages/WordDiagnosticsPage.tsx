import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { getWordDiagnostics } from "../api/endpoints";
import { ActivityOverTimeChart, ExerciseBreakdownChart, ProportionBar, ScoreOverTimeChart } from "../components/MiniCharts";
import type { WordAttempt, WordDiagnostics } from "../types";

const PAGE_SIZE = 10;

/** The 5 universal word-scoped exercise types, in the same order and with
 * the same labels the app itself uses (mobile/lib/exercises/
 * exercise_type.dart) -- shown even for a type with zero attempts, so the
 * breakdown always reads as "here is every exercise this word could have
 * been asked through", not just the ones that happened to come up. */
const EXERCISE_LABELS: { key: string; label: string }[] = [
  { key: "true_or_false", label: "Правда или ложь" },
  { key: "matching", label: "Сопоставление" },
  { key: "build_word", label: "Собери слово" },
  { key: "speaking_word", label: "Произнеси слово 🎙️" },
  { key: "listen_word", label: "Услышь слово 🔊" },
];

function exerciseLabel(key: string): string {
  return EXERCISE_LABELS.find((e) => e.key === key)?.label ?? key;
}

function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString("ru-RU", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

function dayBucketKey(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit" });
}

/** «Диагностика слова»: WordProgress (level/score, re-derived fresh, never
 * cached) plus every WordAttempt this (user, word) pair has, already
 * aggregated by the backend -- see GET /admin/analytics/users/{id}/words/
 * {wordId}. This page only renders what it's given; no total, average or
 * per-exercise count is computed here. */
export function WordDiagnosticsPage() {
  const { userId, wordId } = useParams<{ userId: string; wordId: string }>();
  const [data, setData] = useState<WordDiagnostics | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showAllHistory, setShowAllHistory] = useState(false);

  useEffect(() => {
    if (!userId || !wordId) return;
    setIsLoading(true);
    setError(null);
    getWordDiagnostics(Number(userId), Number(wordId))
      .then(setData)
      .catch(() => setError("Не удалось загрузить диагностику этого слова"))
      .finally(() => setIsLoading(false));
  }, [userId, wordId]);

  if (isLoading) return <p className="text-sm text-slate-500">Загрузка…</p>;
  if (error) return <p className="text-sm text-red-600">{error}</p>;
  if (!data) return null;

  // Oldest-first from the backend (right for the charts below); the
  // history TABLE reads more naturally most-recent-first.
  const historyDesc = [...data.history].reverse();
  const visibleHistory = showAllHistory ? historyDesc : historyDesc.slice(0, PAGE_SIZE);

  const byExerciseMap = new Map(data.by_exercise.map((e) => [e.exercise_key, e]));
  const exerciseRows = EXERCISE_LABELS.map(({ key, label }) => {
    const stats = byExerciseMap.get(key);
    return { label, correct: stats?.total_correct ?? 0, errors: stats?.total_errors ?? 0 };
  });

  const activityBuckets = bucketByDay(data.history);
  const scorePoints = data.history.map((a) => ({ label: dayBucketKey(a.created_at), score: a.score_after }));

  return (
    <div className="mx-auto max-w-4xl">
      <Link to="/analytics" className="mb-3 inline-block text-sm font-medium text-indigo-600 hover:text-indigo-700">
        ← К аналитике пользователей
      </Link>

      <div className="mb-6 flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-slate-900" translate="no">
            {data.word}
          </h1>
          {data.translation && (
            <p className="text-sm text-slate-500" translate="no">
              {data.translation}
            </p>
          )}
        </div>
        <p className="text-sm text-slate-500">
          Пользователь: <span className="font-medium text-slate-700">{data.user_login}</span>
        </p>
      </div>

      <DiagnosticsPanel data={data} />

      <Section title="Общая статистика">
        <div className="grid grid-cols-3 gap-3">
          <StatCard label="Попытки" value={data.total_attempts} />
          <StatCard label="Правильные" value={data.total_correct} valueClassName="text-emerald-600" />
          <StatCard label="Ошибки" value={data.total_errors} valueClassName="text-red-600" />
        </div>
      </Section>

      <Section title="Упражнения">
        <ExerciseBreakdownChart rows={exerciseRows} />
      </Section>

      <Section title="Диаграммы">
        <div className="flex flex-col gap-6">
          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-slate-400">Правильно / ошибки, всего</p>
            <div className="flex flex-col gap-2">
              <ProportionBar label="Правильно" value={data.total_correct} max={data.total_attempts} color="#059669" />
              <ProportionBar label="Ошибки" value={data.total_errors} max={data.total_attempts} color="#dc2626" />
            </div>
          </div>
          {activityBuckets.length > 0 && (
            <div>
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-slate-400">Попытки по дням</p>
              <ActivityOverTimeChart buckets={activityBuckets} />
            </div>
          )}
          {scorePoints.length > 1 && (
            <div>
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-slate-400">Очки слова во времени</p>
              <ScoreOverTimeChart points={scorePoints} />
            </div>
          )}
        </div>
      </Section>

      <Section title="История попыток">
        {historyDesc.length === 0 ? (
          <p className="text-sm text-slate-500">Пока не было ни одной попытки.</p>
        ) : (
          <>
            <div className="overflow-hidden rounded-lg border border-slate-200 bg-white">
              <table className="w-full text-left text-sm">
                <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                  <tr>
                    <th className="px-3 py-2 font-medium">Дата/время</th>
                    <th className="px-3 py-2 font-medium">Упражнение</th>
                    <th className="px-3 py-2 font-medium">Результат</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {visibleHistory.map((a, i) => (
                    <HistoryRow key={i} attempt={a} />
                  ))}
                </tbody>
              </table>
            </div>
            {historyDesc.length > PAGE_SIZE && (
              <button
                type="button"
                onClick={() => setShowAllHistory((v) => !v)}
                className="mt-2 text-sm font-medium text-indigo-600 hover:text-indigo-700"
              >
                {showAllHistory ? "Свернуть" : `Показать все (${historyDesc.length})`}
              </button>
            )}
          </>
        )}
      </Section>
    </div>
  );
}

/** The "at a glance" diagnostic block: level, score/range, and when this
 * word was last touched -- the facts an admin wants before reading the
 * detailed sections below. */
function DiagnosticsPanel({ data }: { data: WordDiagnostics }) {
  const range = data.level
    ? data.level.max_points != null
      ? `${data.level.min_points}–${data.level.max_points}`
      : `от ${data.level.min_points}`
    : null;
  return (
    <div className="mb-6 rounded-xl border border-slate-200 bg-white p-4">
      <p className="mb-3 text-xs font-semibold uppercase tracking-wide text-slate-400">Диагностика слова</p>
      <div className="flex flex-wrap items-center gap-x-8 gap-y-3">
        <div>
          <div className="text-xs text-slate-500">Уровень</div>
          <div className="font-medium text-slate-900">{data.level ? data.level.name : "—"}</div>
        </div>
        <div>
          <div className="text-xs text-slate-500">Очки</div>
          <div className="font-medium text-slate-900">
            {data.score}
            {range && <span className="ml-1 font-normal text-slate-400">({range})</span>}
          </div>
        </div>
        <div>
          <div className="text-xs text-slate-500">Последняя попытка</div>
          {data.last_attempt ? (
            <div className="flex items-center gap-1.5 font-medium text-slate-900">
              <ResultBadge isCorrect={data.last_attempt.is_correct} />
              <span>{exerciseLabel(data.last_attempt.exercise_key)}</span>
              <span className="font-normal text-slate-400">· {formatDateTime(data.last_attempt.created_at)}</span>
            </div>
          ) : (
            <div className="font-medium text-slate-400">Ещё не было</div>
          )}
        </div>
      </div>
    </div>
  );
}

function StatCard({ label, value, valueClassName }: { label: string; value: number; valueClassName?: string }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white p-4">
      <div className={`text-2xl font-semibold ${valueClassName ?? "text-slate-900"}`}>{value}</div>
      <div className="text-xs text-slate-500">{label}</div>
    </div>
  );
}

function ResultBadge({ isCorrect }: { isCorrect: boolean }) {
  return isCorrect ? (
    <span className="inline-flex h-4 w-4 items-center justify-center rounded-full bg-emerald-100 text-[10px] font-bold text-emerald-700">
      ✓
    </span>
  ) : (
    <span className="inline-flex h-4 w-4 items-center justify-center rounded-full bg-red-100 text-[10px] font-bold text-red-700">
      ✗
    </span>
  );
}

function HistoryRow({ attempt }: { attempt: WordAttempt }) {
  return (
    <tr>
      <td className="px-3 py-2 text-slate-600">{formatDateTime(attempt.created_at)}</td>
      <td className="px-3 py-2 text-slate-900">{exerciseLabel(attempt.exercise_key)}</td>
      <td className="px-3 py-2">
        <ResultBadge isCorrect={attempt.is_correct} />
      </td>
    </tr>
  );
}

function bucketByDay(history: WordAttempt[]): { label: string; correct: number; errors: number }[] {
  const byDay = new Map<string, { label: string; correct: number; errors: number }>();
  for (const a of history) {
    const label = dayBucketKey(a.created_at);
    const bucket = byDay.get(label) ?? { label, correct: 0, errors: 0 };
    if (a.is_correct) bucket.correct++;
    else bucket.errors++;
    byDay.set(label, bucket);
  }
  return [...byDay.values()];
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-6">
      <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h2>
      {children}
    </section>
  );
}

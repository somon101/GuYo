import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  getPrioritySettings,
  getWordDiagnostics,
  listPriorityLevelBands,
  listRecencyBands,
  listStabilityBands,
} from "../api/endpoints";
import { ActivityOverTimeChart, ExerciseBreakdownChart, ProportionBar, ScoreOverTimeChart } from "../components/MiniCharts";
import { InfoTooltip } from "../components/InfoTooltip";
import { PRIORITY_ROLE_EFFECTS, priorityRoleBands } from "../lib/priorityRoles";
import type {
  PriorityLevelBand,
  PriorityRecencyBand,
  PrioritySettings,
  PriorityStabilityBand,
  WordAttempt,
  WordDiagnostics,
} from "../types";

/** Every Priority setting/band an explanatory tooltip on this page needs
 * to describe the CURRENT configuration -- fetched once via the exact
 * same admin endpoints PrioritySettingsPage itself uses (see
 * ../api/endpoints.ts), never re-derived or hardcoded here. */
interface PriorityConfig {
  settings: PrioritySettings;
  recencyBands: PriorityRecencyBand[];
  stabilityBands: PriorityStabilityBand[];
  levelBands: PriorityLevelBand[];
}

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
  const [config, setConfig] = useState<PriorityConfig | null>(null);
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
    // Config for the explanatory tooltips -- not required for the page's
    // own numbers (those all come from getWordDiagnostics above), so a
    // failure here just means tooltips fall back to their generic text.
    Promise.all([getPrioritySettings(), listRecencyBands(), listStabilityBands(), listPriorityLevelBands()])
      .then(([settings, recencyBands, stabilityBands, levelBands]) => setConfig({ settings, recencyBands, stabilityBands, levelBands }))
      .catch(() => {});
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

      <DiagnosticsPanel data={data} config={config} />

      <Section title="Общая статистика">
        <div className="grid grid-cols-3 gap-3">
          <StatCard
            label="Попытки"
            value={data.total_attempts}
            tooltip={
              <InfoTooltip label="Влияют ли попытки на Priority">
                Само количество попыток НЕ добавляет Priority-баллы напрямую — оно влияет только косвенно, через
                факторы «Недавние ошибки» и «Стабильность», которым эта история нужна, чтобы вообще было что считать.
              </InfoTooltip>
            }
          />
          <StatCard label="Правильные" value={data.total_correct} valueClassName="text-emerald-600" />
          <StatCard
            label="Ошибки"
            value={data.total_errors}
            valueClassName="text-red-600"
            tooltip={
              <InfoTooltip label="Как считаются ошибки">
                Все ошибки за всё время, по всем упражнениям вместе. В Priority Score напрямую не идёт — используется
                только через факторы «Недавние ошибки» (последние 5/10/20 попыток) и «Стабильность». Разбивка по
                упражнениям ниже — та же самая история, просто сгруппированная по типу, а не отдельный счётчик.
              </InfoTooltip>
            }
          />
        </div>
      </Section>

      <Section
        title="Упражнения"
        titleExtra={
          <InfoTooltip label="Учитываются ли ошибки по упражнениям в Priority">
            Показывает, в каком именно упражнении слово даётся тяжелее всего — чисто для диагностики, чтобы понять
            характер проблемы. Эти же ошибки уже один раз учтены в факторе «Недавние ошибки» (по всем упражнениям
            вместе); здесь они не прибавляются к Priority Score повторно.
          </InfoTooltip>
        }
      >
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

/** Count of wrong answers among the LAST `window` attempts, oldest-first
 * `history` sliced from the end -- pure display arithmetic (a count, not
 * a weighted score) backing the "Недавние ошибки" tooltip with this
 * word's real numbers; the actual weighted contribution always comes
 * from the backend's own recent_errors_contribution, never re-derived
 * here. */
function recentErrorCount(history: WordAttempt[], window: number): { errors: number; total: number } {
  const recent = history.slice(-window);
  return { errors: recent.filter((a) => !a.is_correct).length, total: recent.length };
}

/** The "at a glance" diagnostic block: level, score/range, Priority and
 * its 4 factors, and when this word was last touched -- the facts an
 * admin wants before reading the detailed sections below. */
function DiagnosticsPanel({ data, config }: { data: WordDiagnostics; config: PriorityConfig | null }) {
  const range = data.level
    ? data.level.max_points != null
      ? `${data.level.min_points}–${data.level.max_points}`
      : `от ${data.level.min_points}`
    : null;

  const roles = config ? priorityRoleBands(config.levelBands) : null;
  const currentRoleEffect = roles && data.priority_level
    ? PRIORITY_ROLE_EFFECTS.find((r) => roles[r.key]?.id === data.priority_level!.id)
    : undefined;

  const e5 = recentErrorCount(data.history, 5);
  const e10 = recentErrorCount(data.history, 10);
  const e20 = recentErrorCount(data.history, 20);

  const stabilityWindow = config?.settings.stability_window ?? null;
  const stabilityRecent = stabilityWindow != null ? data.history.slice(-stabilityWindow) : [];

  return (
    <div className="mb-6 rounded-xl border border-slate-200 bg-white p-4">
      <p className="mb-3 text-xs font-semibold uppercase tracking-wide text-slate-400">Диагностика слова</p>
      <div className="flex flex-wrap items-center gap-x-8 gap-y-3">
        <div>
          <div className="flex items-center gap-1.5 text-xs text-slate-500">
            Уровень
            <InfoTooltip label="Что означает уровень слова">
              <p className="mb-2 font-medium text-slate-900">Уровень слова</p>
              {data.level ? (
                <>
                  <p className="mb-2">
                    Сейчас — «{data.level.name}», диапазон {data.level.min_points}–{data.level.max_points ?? "∞"} очков
                    (границы и очки за упражнения редактируются на странице «Уровни слов»).
                  </p>
                  <p>
                    Вклад этого уровня в Priority: {data.level.priority_weight} — один из 4 факторов, см. подсказку у
                    «Priority» ниже.
                  </p>
                </>
              ) : (
                <p>Для текущих очков ({data.score}) нет подходящего диапазона в лестнице уровней.</p>
              )}
            </InfoTooltip>
          </div>
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
        <div>
          <div className="flex items-center gap-1.5 text-xs text-slate-500">
            Priority
            <InfoTooltip label="Как считается Priority">
              <p className="mb-2 font-medium text-slate-900">
                {data.level_contribution} + {data.recent_errors_contribution} + {data.recency_contribution} +{" "}
                {data.stability_contribution} = {data.priority_score.toFixed(1)}
              </p>
              <TooltipFacts
                rows={[
                  { label: "Уровень слова", value: data.level_contribution },
                  { label: "Недавние ошибки", value: data.recent_errors_contribution },
                  { label: "Давность контакта", value: data.recency_contribution },
                  { label: "Стабильность", value: data.stability_contribution },
                ]}
              />
              <p className="mt-2">
                Итог попадает в диапазон «{data.priority_level?.name ?? "—"}»
                {currentRoleEffect ? ` (роль «${currentRoleEffect.label}») — ${currentRoleEffect.effect}.` : "."}
              </p>
              <p className="mt-2 text-slate-400">Пересчитывается заново при каждом открытии этой страницы, нигде не хранится.</p>
            </InfoTooltip>
          </div>
          <div className="font-medium text-slate-900">
            {data.priority_score.toFixed(1)}
            {data.priority_level && <span className="ml-1 font-normal text-slate-400">({data.priority_level.name})</span>}
          </div>
        </div>
        <div>
          <div className="flex items-center gap-1.5 text-xs text-slate-500">
            Недавние ошибки
            <InfoTooltip label="Как считаются недавние ошибки">
              <p className="mb-2">
                Доля ошибок отдельно в последних 5, 10 и 20 попытках, взвешенная по настроенным весам окон — чем
                больше вес у меньшего окна, тем сильнее свежие результаты перевешивают старые.
              </p>
              <TooltipFacts
                rows={[
                  { label: "Последние 5", value: `${e5.errors}/${e5.total} ошибок` },
                  { label: "Последние 10", value: `${e10.errors}/${e10.total} ошибок` },
                  { label: "Последние 20", value: `${e20.errors}/${e20.total} ошибок` },
                ]}
              />
              <p className="mt-2">Вклад в Priority: {data.recent_errors_contribution}.</p>
            </InfoTooltip>
          </div>
          <div className="font-medium text-slate-900">{data.recent_errors_contribution}</div>
        </div>
        <div>
          <div className="flex items-center gap-1.5 text-xs text-slate-500">
            Стабильность
            <InfoTooltip label="Как считается стабильность">
              <p className="mb-2">
                {stabilityWindow != null
                  ? `Среди последних ${stabilityWindow} попыток по этому слову ${stabilityRecent.filter((a) => a.is_correct).length} правильных из ${stabilityRecent.length} → ${data.stability_percent ?? "—"}%.`
                  : `Процент правильных среди последних попыток → ${data.stability_percent ?? "—"}%.`}
              </p>
              {data.stability_level && (
                <p>
                  Это попадает в диапазон «{data.stability_level.name}», вклад в Priority: {data.stability_contribution}.
                </p>
              )}
            </InfoTooltip>
          </div>
          <div className="font-medium text-slate-900">
            {data.stability_percent != null ? `${Math.round(data.stability_percent)}%` : "—"}
            {data.stability_level && <span className="ml-1 font-normal text-slate-400">({data.stability_level.name})</span>}
          </div>
        </div>
        <div>
          <div className="flex items-center gap-1.5 text-xs text-slate-500">
            Давность контакта
            <InfoTooltip label="Как считается давность">
              <p className="mb-2">
                {data.days_since_last_attempt == null
                  ? "По этому слову ещё не было попыток — давность не считается."
                  : `С последней попытки прошло ${data.days_since_last_attempt} дн. Чем больше пройдёт времени без новой попытки, тем выше станет этот вклад — даже без единой новой попытки, просто при следующем пересчёте.`}
              </p>
              {data.recency_level && (
                <p className="mt-2">
                  Это попадает в диапазон «{data.recency_level.name}», вклад в Priority: {data.recency_contribution}.
                </p>
              )}
            </InfoTooltip>
          </div>
          <div className="font-medium text-slate-900">
            {data.days_since_last_attempt == null ? "—" : data.days_since_last_attempt === 0 ? "сегодня" : `${data.days_since_last_attempt} дн. назад`}
          </div>
        </div>
      </div>
    </div>
  );
}

function TooltipFacts({ rows }: { rows: { label: string; value: React.ReactNode }[] }) {
  return (
    <dl className="flex flex-col gap-1">
      {rows.map((r, i) => (
        <div key={i} className="flex items-baseline justify-between gap-3">
          <dt className="text-slate-500">{r.label}</dt>
          <dd className="font-medium text-slate-900">{r.value}</dd>
        </div>
      ))}
    </dl>
  );
}

function StatCard({
  label,
  value,
  valueClassName,
  tooltip,
}: {
  label: string;
  value: number;
  valueClassName?: string;
  tooltip?: React.ReactNode;
}) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white p-4">
      <div className={`text-2xl font-semibold ${valueClassName ?? "text-slate-900"}`}>{value}</div>
      <div className="flex items-center gap-1.5 text-xs text-slate-500">
        {label}
        {tooltip}
      </div>
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

function Section({ title, titleExtra, children }: { title: string; titleExtra?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="mb-6">
      <h2 className="mb-2 flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-slate-500">
        {title}
        {titleExtra}
      </h2>
      {children}
    </section>
  );
}

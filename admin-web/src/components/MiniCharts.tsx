/** Small, dependency-free charts for «Диагностика слова» -- the project
 * has no chart library, and these are simple enough (a handful of bars, a
 * short line) that adding one would be more weight than the feature is
 * worth. Every chart here takes already-aggregated numbers and only draws
 * them; none of them compute a total/average/bucket themselves beyond
 * plain layout arithmetic (position on the axis), matching this page's
 * own "backend computes, this only renders" rule. */

const GREEN = "#059669"; // emerald-600
const RED = "#dc2626"; // red-600
const INDIGO = "#4f46e5"; // indigo-600
const TRACK = "#e2e8f0"; // slate-200

/** One labeled horizontal bar, proportional to `value / max`. Used for the
 * overall correct/error comparison and reused per-row inside
 * StackedBarChart's own labels. */
export function ProportionBar({
  label,
  value,
  max,
  color,
}: {
  label: string;
  value: number;
  max: number;
  color: string;
}) {
  const pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  return (
    <div className="flex items-center gap-3">
      <div className="w-32 shrink-0 truncate text-sm text-slate-600" translate="no">
        {label}
      </div>
      <div className="h-3 flex-1 overflow-hidden rounded-full bg-slate-100">
        <div className="h-full rounded-full" style={{ width: `${pct}%`, backgroundColor: color }} />
      </div>
      <div className="w-10 shrink-0 text-right text-sm font-medium text-slate-700">{value}</div>
    </div>
  );
}

/** One row per exercise type: a stacked correct/error bar plus the raw
 * counts, all against the SAME shared scale (the busiest exercise's total
 * attempts) so row widths are honestly comparable to each other. */
export function ExerciseBreakdownChart({
  rows,
}: {
  rows: { label: string; correct: number; errors: number }[];
}) {
  const max = Math.max(1, ...rows.map((r) => r.correct + r.errors));
  return (
    <div className="flex flex-col gap-2.5">
      {rows.map((r) => {
        const total = r.correct + r.errors;
        const correctPct = (r.correct / max) * 100;
        const errorPct = (r.errors / max) * 100;
        return (
          <div key={r.label} className="flex items-center gap-3">
            <div className="w-36 shrink-0 truncate text-sm text-slate-600">{r.label}</div>
            <div className="flex h-3 flex-1 overflow-hidden rounded-full bg-slate-100">
              <div className="h-full" style={{ width: `${correctPct}%`, backgroundColor: GREEN }} />
              <div className="h-full" style={{ width: `${errorPct}%`, backgroundColor: RED }} />
            </div>
            <div className="w-24 shrink-0 text-right text-xs text-slate-500">
              {total} · <span style={{ color: GREEN }}>{r.correct}</span> /{" "}
              <span style={{ color: RED }}>{r.errors}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** Correct/error counts bucketed by day, as a simple stacked column chart
 * -- plain SVG rects, no axis library. `buckets` must already be sorted
 * oldest-first. */
export function ActivityOverTimeChart({
  buckets,
}: {
  buckets: { label: string; correct: number; errors: number }[];
}) {
  if (buckets.length === 0) return null;
  const width = 640;
  const height = 140;
  const barGap = 4;
  const barWidth = Math.max(4, Math.min(28, width / buckets.length - barGap));
  const max = Math.max(1, ...buckets.map((b) => b.correct + b.errors));
  const scale = (n: number) => (n / max) * (height - 24);

  return (
    <div className="overflow-x-auto">
      <svg width={Math.max(width, buckets.length * (barWidth + barGap))} height={height + 20} role="img">
        {buckets.map((b, i) => {
          const x = i * (barWidth + barGap);
          const correctH = scale(b.correct);
          const errorH = scale(b.errors);
          return (
            <g key={b.label}>
              <rect x={x} y={height - correctH - errorH} width={barWidth} height={errorH} fill={RED} rx={1.5} />
              <rect x={x} y={height - correctH} width={barWidth} height={correctH} fill={GREEN} rx={1.5} />
              <rect x={x} y={height} width={barWidth} height={1} fill={TRACK} />
              {buckets.length <= 20 && (
                <text x={x + barWidth / 2} y={height + 14} fontSize={9} textAnchor="middle" fill="#94a3b8">
                  {b.label}
                </text>
              )}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

/** The word's score right after each attempt, as a simple step line --
 * exactly what WordAttempt.score_after already records, point for point,
 * never interpolated or smoothed. */
export function ScoreOverTimeChart({ points }: { points: { label: string; score: number }[] }) {
  if (points.length === 0) return null;
  const width = 640;
  const height = 140;
  const pad = 8;
  const stepX = points.length > 1 ? (width - pad * 2) / (points.length - 1) : 0;
  const y = (score: number) => pad + (1 - score / 100) * (height - pad * 2);

  const path = points.map((p, i) => `${i === 0 ? "M" : "L"} ${pad + i * stepX} ${y(p.score)}`).join(" ");

  return (
    <div className="overflow-x-auto">
      <svg width={width} height={height} role="img">
        {/* Reference lines at 0/50/100 */}
        {[0, 50, 100].map((v) => (
          <line key={v} x1={pad} x2={width - pad} y1={y(v)} y2={y(v)} stroke={TRACK} strokeWidth={1} />
        ))}
        <path d={path} fill="none" stroke={INDIGO} strokeWidth={2} />
        {points.map((p, i) => (
          <circle key={i} cx={pad + i * stepX} cy={y(p.score)} r={2.5} fill={INDIGO} />
        ))}
      </svg>
    </div>
  );
}

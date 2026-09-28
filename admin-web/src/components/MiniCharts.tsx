/** Small, dependency-free charts for «Диагностика слова» -- the project
 * has no chart library, and these are simple enough (a handful of bars, a
 * short line) that adding one would be more weight than the feature is
 * worth. Every chart here takes already-aggregated numbers and only draws
 * them; none of them compute a total/average/bucket themselves beyond
 * plain layout arithmetic (position on the axis), matching this page's
 * own "backend computes, this only renders" rule. */

import { useState } from "react";

// iOS system colours from index.css, so the charts follow light/dark mode.
export const GREEN = "var(--sys-green)";
export const RED = "var(--sys-red)";
const INDIGO = "var(--sys-blue)";
const TRACK = "var(--separator)";
const AXIS_LABEL = "var(--gray-500)";

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
              <rect x={x} y={height - correctH - errorH} width={barWidth} height={errorH} style={{ fill: RED }} rx={1.5} />
              <rect x={x} y={height - correctH} width={barWidth} height={correctH} style={{ fill: GREEN }} rx={1.5} />
              <rect x={x} y={height} width={barWidth} height={1} style={{ fill: TRACK }} />
              {buckets.length <= 20 && (
                <text x={x + barWidth / 2} y={height + 14} fontSize={9} textAnchor="middle" style={{ fill: AXIS_LABEL }}>
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
          <line key={v} x1={pad} x2={width - pad} y1={y(v)} y2={y(v)} strokeWidth={1} style={{ stroke: TRACK }} />
        ))}
        <path d={path} fill="none" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" style={{ stroke: INDIGO }} />
        {points.map((p, i) => (
          <circle key={i} cx={pad + i * stepX} cy={y(p.score)} r={2.5} style={{ fill: INDIGO }} />
        ))}
      </svg>
    </div>
  );
}

/** One value per day as columns. A single series, so there is no legend --
 * the section title names what is plotted. Built from flex columns rather
 * than a fixed-width SVG so it fills any card width, down to a phone. The
 * readout line above the plot shows the hovered/focused day's exact value
 * (touch and keyboard included), and `summary` when nothing is hovered. */
export function DailyColumnChart({
  points,
  summary,
}: {
  points: { key: string; label: string; value: number }[];
  summary: string;
}) {
  const [active, setActive] = useState<number | null>(null);
  if (points.length === 0) return null;
  const max = Math.max(1, ...points.map((p) => p.value));
  const hovered = active != null ? points[active] : null;
  const ticks = [...new Set([0, Math.floor((points.length - 1) / 2), points.length - 1])];

  return (
    <div>
      <div className="mb-2 h-5 text-sm text-slate-500">
        {hovered ? (
          <>
            <span className="font-semibold tabular-nums text-slate-900">{hovered.value}</span> · {hovered.label}
          </>
        ) : (
          summary
        )}
      </div>
      <div className="relative h-32" onMouseLeave={() => setActive(null)}>
        <div className="absolute inset-x-0 top-0 border-t" style={{ borderColor: TRACK }} />
        <span className="absolute -top-2 right-0 -translate-y-full text-[10px] tabular-nums" style={{ color: AXIS_LABEL }}>
          {max}
        </span>
        <div className="absolute inset-x-0 bottom-0 border-t" style={{ borderColor: TRACK }} />
        <div className="absolute inset-0 flex items-end gap-[2px]">
          {points.map((p, i) => (
            <div
              key={p.key}
              tabIndex={0}
              aria-label={`${p.label}: ${p.value}`}
              onMouseEnter={() => setActive(i)}
              onFocus={() => setActive(i)}
              onBlur={() => setActive(null)}
              onClick={() => setActive(i)}
              className="flex h-full flex-1 items-end justify-center rounded-[4px] outline-none focus-visible:bg-[var(--fill)]"
            >
              {p.value > 0 && (
                <div
                  className="w-full max-w-[24px] rounded-t-[4px] transition-opacity"
                  style={{
                    height: `max(2px, ${(p.value / max) * 100}%)`,
                    backgroundColor: INDIGO,
                    opacity: active != null && active !== i ? 0.4 : 1,
                  }}
                />
              )}
            </div>
          ))}
        </div>
      </div>
      <div className="mt-1.5 flex justify-between text-[10px] tabular-nums" style={{ color: AXIS_LABEL }}>
        {ticks.map((i) => (
          <span key={i}>{points[i].label}</span>
        ))}
      </div>
    </div>
  );
}

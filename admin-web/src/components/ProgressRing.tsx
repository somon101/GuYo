import { useEffect, useState } from "react";

function toneFor(percent: number) {
  if (percent >= 70) return "var(--sys-green)";
  if (percent >= 40) return "var(--sys-orange)";
  return "var(--sys-red)";
}

/** A result shown the way Health shows Activity rings: a thick round-capped
 * arc over a tinted track, with the percentage in the middle. The arc
 * sweeps in from zero when it first appears. */
export function ProgressRing({
  percent,
  size = 96,
  stroke = 11,
  caption,
  color,
}: {
  percent: number;
  size?: number;
  stroke?: number;
  caption?: string;
  color?: string;
}) {
  const clamped = Math.max(0, Math.min(100, percent));
  const tone = color ?? toneFor(clamped);
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const [shown, setShown] = useState(0);

  useEffect(() => {
    const frame = requestAnimationFrame(() => setShown(clamped));
    return () => cancelAnimationFrame(frame);
  }, [clamped]);

  return (
    <div className="inline-flex flex-col items-center gap-1.5">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90" role="img" aria-label={`${Math.round(clamped)}%`}>
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="none"
            strokeWidth={stroke}
            style={{ stroke: `color-mix(in srgb, ${tone} 20%, transparent)` }}
          />
          <circle
            className="progress-ring-arc"
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="none"
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={circumference * (1 - shown / 100)}
            style={{ stroke: tone }}
          />
        </svg>
        <div className="absolute inset-0 flex items-center justify-center">
          <span className="text-[19px] font-semibold tabular-nums tracking-tight text-slate-900">
            {Math.round(clamped)}%
          </span>
        </div>
      </div>
      {caption && <span className="text-xs text-slate-500">{caption}</span>}
    </div>
  );
}

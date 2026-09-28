import type { ReactNode } from "react";

export type Segment<T extends string> = { value: T; label: ReactNode };

/** iOS segmented control: a grey track with the chosen segment as a white
 * pill that slides between options. Use for a small set (2-4) of mutually
 * exclusive choices with short labels. */
export function SegmentedControl<T extends string>({
  segments,
  value,
  onChange,
  ariaLabel,
  className = "",
}: {
  segments: Segment<T>[];
  value: T;
  onChange: (value: T) => void;
  ariaLabel: string;
  className?: string;
}) {
  const index = Math.max(
    0,
    segments.findIndex((s) => s.value === value),
  );
  return (
    <div
      role="radiogroup"
      aria-label={ariaLabel}
      className={`relative inline-grid rounded-[9px] bg-[var(--fill)] p-0.5 ${className}`}
      style={{ gridTemplateColumns: `repeat(${segments.length}, minmax(0, 1fr))` }}
    >
      <span
        aria-hidden="true"
        className="segmented-thumb absolute bottom-0.5 left-0.5 top-0.5 rounded-[7px] bg-[var(--segment-thumb)] shadow-[0_3px_8px_rgb(0_0_0/0.12),0_3px_1px_rgb(0_0_0/0.04)]"
        style={{
          width: `calc((100% - 4px) / ${segments.length})`,
          translate: `${index * 100}% 0`,
        }}
      />
      {segments.map((s) => {
        const selected = s.value === value;
        return (
          <button
            key={s.value}
            type="button"
            role="radio"
            aria-checked={selected}
            onClick={() => onChange(s.value)}
            className={`relative z-10 whitespace-nowrap rounded-[7px] px-3.5 py-1 text-[13px] font-medium ${
              selected ? "text-slate-900" : "text-slate-600 hover:text-slate-900"
            }`}
          >
            {s.label}
          </button>
        );
      })}
    </div>
  );
}

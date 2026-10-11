import { useEffect, useRef } from "react";
import { useSearchParams } from "react-router-dom";

/** The search query kept in the URL (?q=), so "Редактировать" → "Назад"
 * comes back to the same results. */
export function useSearchQuery(): [string, (q: string) => void] {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  return [
    q,
    (next: string) => {
      const p = new URLSearchParams(params);
      if (next) p.set("q", next);
      else p.delete("q");
      setParams(p, { replace: true });
    },
  ];
}

/** A search field: 🔍, clear button, «/» focuses it, «Найдено: N». */
export function SearchBox({
  value,
  onChange,
  placeholder = "Поиск",
  found,
}: {
  value: string;
  onChange: (q: string) => void;
  placeholder?: string;
  found?: number;
}) {
  const ref = useRef<HTMLInputElement>(null);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const el = e.target as HTMLElement;
      if (
        e.key === "/" &&
        !["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName) &&
        !el.isContentEditable
      ) {
        e.preventDefault();
        ref.current?.focus();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="mb-4">
      <div className="relative">
        <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">
          🔍
        </span>
        <input
          ref={ref}
          type="text"
          enterKeyHint="search"
          inputMode="search"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => e.key === "Escape" && onChange("")}
          placeholder={`${placeholder}  ( / )`}
          className="field w-full py-2.5 pl-10 pr-10 text-[15px]"
          aria-label={placeholder}
        />
        {value && (
          <button
            type="button"
            onClick={() => {
              onChange("");
              ref.current?.focus();
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full px-2 py-0.5 text-slate-400 hover:text-slate-700"
            aria-label="Очистить поиск"
          >
            ✕
          </button>
        )}
      </div>
      {value && found !== undefined && (
        <p className="mt-1.5 text-xs text-slate-500">
          {found ? `Найдено: ${found}` : "Ничего не найдено"}
        </p>
      )}
    </div>
  );
}

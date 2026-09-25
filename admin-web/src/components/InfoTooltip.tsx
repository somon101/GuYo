import { useEffect, useRef, useState, type ReactNode } from "react";

/** A small "?" icon that opens a compact, click-triggered explanation
 * panel -- used throughout the Priority settings and word-diagnostics
 * pages to explain a metric next to it (see PrioritySettingsPage.tsx and
 * WordDiagnosticsPage.tsx). Positioned via a measured `fixed` panel
 * rather than a CSS-anchored dropdown so it never gets clipped near a
 * screen edge on either desktop or a narrow phone width. Click-triggered
 * (not hover) so it works the same way with a mouse or a touch screen. */
export function InfoTooltip({ children, label = "Пояснение" }: { children: ReactNode; label?: string }) {
  const [isOpen, setIsOpen] = useState(false);
  const [pos, setPos] = useState<{ top: number; left: number; width: number } | null>(null);
  const btnRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isOpen) return;
    const btn = btnRef.current;
    if (!btn) return;
    const rect = btn.getBoundingClientRect();
    const width = Math.min(300, window.innerWidth - 24);
    const left = Math.max(12, Math.min(rect.left + rect.width / 2 - width / 2, window.innerWidth - width - 12));
    setPos({ top: rect.bottom + 8, left, width });

    function handlePointerDown(e: MouseEvent) {
      const target = e.target as Node;
      if (panelRef.current?.contains(target) || btnRef.current?.contains(target)) return;
      setIsOpen(false);
    }
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") setIsOpen(false);
    }
    function close() {
      setIsOpen(false);
    }
    document.addEventListener("mousedown", handlePointerDown);
    document.addEventListener("keydown", handleKey);
    window.addEventListener("resize", close);
    window.addEventListener("scroll", close, true);
    return () => {
      document.removeEventListener("mousedown", handlePointerDown);
      document.removeEventListener("keydown", handleKey);
      window.removeEventListener("resize", close);
      window.removeEventListener("scroll", close, true);
    };
  }, [isOpen]);

  return (
    <span className="relative inline-flex">
      <button
        ref={btnRef}
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setIsOpen((v) => !v);
        }}
        aria-label={label}
        aria-expanded={isOpen}
        className="inline-flex h-4 w-4 shrink-0 items-center justify-center rounded-full border border-slate-300 bg-white text-[10px] font-semibold leading-none text-slate-500 hover:border-indigo-400 hover:text-indigo-600"
      >
        ?
      </button>
      {isOpen && pos && (
        <div
          ref={panelRef}
          style={{ position: "fixed", top: pos.top, left: pos.left, width: pos.width }}
          className="z-50 rounded-lg border border-slate-200 bg-white p-3 text-xs leading-relaxed text-slate-600 shadow-lg"
        >
          {children}
        </div>
      )}
    </span>
  );
}

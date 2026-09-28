import type { ReactNode } from "react";
import { useEffect } from "react";
import { createPortal } from "react-dom";

export function Modal({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
}) {
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onClose]);

  // Portaled to <body> so no animated or transformed ancestor can ever
  // become its containing block -- the dimmed overlay always covers the
  // whole window, header included.
  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/35 p-4 animate-[fade-in_200ms_ease-out]"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="popover max-h-[90vh] w-full max-w-md overflow-y-auto rounded-[20px] p-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between gap-3">
          <h2 className="text-[17px] font-semibold text-slate-900">{title}</h2>
          <button
            type="button"
            onClick={onClose}
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[var(--fill)] text-slate-500 hover:bg-[var(--fill-strong)]"
            aria-label="Закрыть"
          >
            <svg viewBox="0 0 12 12" className="h-3 w-3" aria-hidden="true">
              <path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
            </svg>
          </button>
        </div>
        {children}
      </div>
    </div>,
    document.body,
  );
}

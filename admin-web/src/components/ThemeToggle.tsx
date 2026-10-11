import { useEffect, useState } from "react";

type Theme = "system" | "light" | "dark";
const KEY = "guyo_admin_theme";
const ORDER: Theme[] = ["system", "light", "dark"];
const LABEL: Record<Theme, string> = { system: "Тема: система", light: "Тема: светлая", dark: "Тема: тёмная" };

function read(): Theme {
  try {
    const v = localStorage.getItem(KEY);
    return v === "light" || v === "dark" ? v : "system";
  } catch {
    return "system";
  }
}

function apply(theme: Theme) {
  const root = document.documentElement;
  if (theme === "system") delete root.dataset.theme;
  else root.dataset.theme = theme;
}

// Applied before React renders, so the page never flashes the wrong theme.
apply(read());

/** System → light → dark, remembered in this browser. */
export function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>(read);

  useEffect(() => {
    apply(theme);
    try {
      if (theme === "system") localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, theme);
    } catch {
      // Private mode: the choice simply lasts for this visit.
    }
  }, [theme]);

  const next = ORDER[(ORDER.indexOf(theme) + 1) % ORDER.length];
  return (
    <button
      type="button"
      onClick={() => setTheme(next)}
      title={LABEL[theme]}
      aria-label={`${LABEL[theme]}. Переключить`}
      className="btn-tinted flex h-8 w-8 items-center justify-center rounded-full"
    >
      <svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        {theme === "light" ? (
          <path d="M12 4V2M12 22v-2M4 12H2M22 12h-2M5.6 5.6 4.2 4.2M19.8 19.8l-1.4-1.4M5.6 18.4l-1.4 1.4M19.8 4.2l-1.4 1.4M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z" />
        ) : theme === "dark" ? (
          <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z" />
        ) : (
          <path d="M3 5h18v11H3zM8 20h8M12 16v4" />
        )}
      </svg>
    </button>
  );
}

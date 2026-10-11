import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { NavLink, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { usePageEnter, usePageTransitions } from "../lib/pageTransitions";
import { Backdrop } from "./Backdrop";
import { ChangePasswordButton } from "./ChangePasswordButton";
import { NavIcon } from "./NavIcon";
import logoMark from "../assets/logo-mark.png";

type Tile = "orange" | "green" | "blue" | "pink" | "yellow";

// The side menu, grouped by what the team is looking after. Each group
// wears one of the app's pastel tiles, as on the app's home screen.
const navGroups: { title: string; tile: Tile; items: { to: string; label: string; icon: string }[] }[] = [
  {
    title: "Люди",
    tile: "blue",
    items: [
      { to: "/users", label: "Пользователи", icon: "users" },
      { to: "/analytics", label: "Аналитика", icon: "chart" },
      { to: "/retention", label: "Удержание", icon: "retention" },
      { to: "/notifications", label: "Уведомления", icon: "bell" },
    ],
  },
  {
    title: "Контент",
    tile: "green",
    items: [
      { to: "/dictionaries", label: "Языки", icon: "globe" },
      { to: "/exercises", label: "Упражнения", icon: "dumbbell" },
      { to: "/mini-phrase-templates", label: "Мини-фразы", icon: "blocks" },
      { to: "/translation", label: "ИИ-перевод", icon: "sparkles" },
      { to: "/slogans", label: "Слоганы", icon: "quote" },
      { to: "/statuses", label: "Статусы", icon: "message" },
    ],
  },
  {
    title: "Игра",
    tile: "orange",
    items: [
      { to: "/rating", label: "Рейтинг", icon: "podium" },
      { to: "/achievements", label: "Достижения", icon: "trophy" },
      { to: "/quests", label: "Квесты", icon: "target" },
      { to: "/review", label: "Повтори слово", icon: "repeat" },
    ],
  },
  {
    title: "Доход",
    tile: "yellow",
    items: [
      { to: "/premium", label: "Premium", icon: "crown" },
      { to: "/promo", label: "Промокоды", icon: "ticket" },
    ],
  },
  {
    title: "Система",
    tile: "pink",
    items: [{ to: "/client-errors", label: "Ошибки приложения", icon: "bug" }],
  },
];

const navItems = navGroups.flatMap((g) => g.items.map((item) => ({ ...item, tile: g.tile })));

function isActive(pathname: string, to: string) {
  return pathname === to || pathname.startsWith(`${to}/`);
}

export function Layout({ children }: { children: ReactNode }) {
  const { logout } = useAuth();
  const location = useLocation();
  usePageTransitions();
  const enterDir = usePageEnter(location.pathname);
  const section = navItems.find((item) => isActive(location.pathname, item.to));

  // The violet pill glides to the active item: the rail's one motion.
  const navRef = useRef<HTMLElement>(null);
  const [pill, setPill] = useState<{ y: number; h: number } | null>(null);
  useLayoutEffect(() => {
    const active = navRef.current?.querySelector<HTMLElement>('[aria-current="page"]');
    setPill(active ? { y: active.offsetTop, h: active.offsetHeight } : null);
  }, [location.pathname]);

  return (
    <div className="min-h-screen md:grid md:grid-cols-[264px_1fr]">
      <Backdrop />

      {/* Desktop: the indigo rail. */}
      <aside className="hidden md:sticky md:top-0 md:flex md:h-dvh md:flex-col md:bg-[var(--rail)] md:text-[var(--rail-text)]">
        <div className="flex items-center gap-3 px-6 pb-5 pt-6">
          <img src={logoMark} alt="" className="h-9 w-9 shrink-0 rounded-xl bg-white/95 p-1" />
          <div className="leading-tight">
            <p className="text-[17px] font-bold tracking-tight text-white">GuYo</p>
            <p className="text-[12px] text-[var(--rail-text)]">Админ-панель</p>
          </div>
        </div>

        <nav ref={navRef} aria-label="Разделы" className="relative flex-1 overflow-y-auto px-3 pb-6 [scrollbar-width:none]">
          {pill && (
            <span
              aria-hidden="true"
              className="rail-pill"
              style={{ translate: `0 ${pill.y}px`, height: pill.h, marginInline: 12 }}
            />
          )}
          {navGroups.map((group) => (
            <div key={group.title} className="mt-4 first:mt-0">
              <p className="px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--rail-text)] opacity-70">
                {group.title}
              </p>
              {group.items.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  className={({ isActive: on }) =>
                    `rail-link relative z-10 flex items-center gap-3 rounded-xl px-2.5 py-[7px] text-[14.5px] transition-colors ${
                      on ? "font-semibold text-white" : "text-[var(--rail-text)] hover:bg-white/[0.06] hover:text-white"
                    }`
                  }
                >
                  {({ isActive: on }) => (
                    <>
                      <span
                        className={`rail-tile flex h-8 w-8 shrink-0 items-center justify-center rounded-[10px] ${
                          on ? "bg-white/20 text-white" : "text-[var(--ink)]"
                        }`}
                        style={on ? undefined : { backgroundColor: `var(--tile-${group.tile})` }}
                      >
                        <NavIcon name={item.icon} />
                      </span>
                      {item.label}
                    </>
                  )}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="flex items-center gap-1 border-t border-white/10 p-3 [&_button]:text-[var(--rail-text)]">
          <button
            onClick={logout}
            className="flex flex-1 items-center gap-3 rounded-xl px-2.5 py-2 text-[14.5px] hover:bg-white/[0.06] hover:!text-white"
          >
            <span className="flex h-8 w-8 items-center justify-center rounded-[10px] bg-white/10">
              <svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3M10 16l-4-4 4-4M6 12h10" />
              </svg>
            </span>
            Выйти
          </button>
          <ChangePasswordButton />
        </div>
      </aside>

      <div className="min-w-0">
        {/* Phone: a top bar with the sections as scrolling pills. */}
        <header className="app-header glass-bar sticky top-0 z-30 md:hidden">
          <div className="flex h-14 items-center gap-2.5 px-4">
            <img src={logoMark} alt="" className="h-7 w-7 shrink-0" />
            <span className="flex-1 truncate text-[16px] font-bold text-[var(--ink)]">{section?.label ?? "GuYo"}</span>
            <ChangePasswordButton />
            <button onClick={logout} className="btn-tinted rounded-full px-3.5 py-1.5 text-sm font-medium">
              Выйти
            </button>
          </div>
          <nav aria-label="Разделы" className="flex gap-1.5 overflow-x-auto px-4 pb-3 [scrollbar-width:none]">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive: on }) =>
                  `flex shrink-0 items-center gap-2 whitespace-nowrap rounded-full py-1.5 pl-1.5 pr-3.5 text-sm font-medium transition-colors ${
                    on ? "bg-[var(--sys-blue)] text-white shadow-[var(--shadow-primary)]" : "bg-[var(--card)] text-[var(--ink)]"
                  }`
                }
              >
                {({ isActive: on }) => (
                  <>
                    <span
                      className={`flex h-6 w-6 items-center justify-center rounded-full ${on ? "bg-white/20" : "text-[var(--ink)]"}`}
                      style={on ? undefined : { backgroundColor: `var(--tile-${item.tile})` }}
                    >
                      <NavIcon name={item.icon} />
                    </span>
                    {item.label}
                  </>
                )}
              </NavLink>
            ))}
          </nav>
        </header>

        <main className="mx-auto min-w-0 max-w-[1240px] px-4 pb-16 pt-4 sm:px-6 md:px-10 md:pt-9">
          <div
            key={location.pathname}
            className={enterDir ? "page-view page-enter" : "page-view"}
            data-dir={enterDir ?? undefined}
          >
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}

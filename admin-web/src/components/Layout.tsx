import type { ReactNode } from "react";
import { NavLink, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { usePageEnter, usePageTransitions } from "../lib/pageTransitions";
import { Backdrop } from "./Backdrop";
import { NavIcon } from "./NavIcon";
import logoMark from "../assets/logo-mark.png";

// The side menu, grouped by what the admin is looking after.
const navGroups: { title: string; items: { to: string; label: string; icon: string }[] }[] = [
  {
    title: "Люди",
    items: [
      { to: "/users", label: "Пользователи", icon: "users" },
      { to: "/analytics", label: "Аналитика", icon: "chart" },
      { to: "/retention", label: "Удержание", icon: "retention" },
      { to: "/notifications", label: "Уведомления", icon: "bell" },
    ],
  },
  {
    title: "Контент",
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
    items: [
      { to: "/rating", label: "Рейтинг", icon: "podium" },
      { to: "/achievements", label: "Достижения", icon: "trophy" },
      { to: "/quests", label: "Квесты", icon: "target" },
      { to: "/review", label: "Повтори слово", icon: "repeat" },
    ],
  },
  {
    title: "Доход",
    items: [
      { to: "/premium", label: "Premium", icon: "crown" },
      { to: "/promo", label: "Промокоды", icon: "ticket" },
    ],
  },
  {
    title: "Система",
    items: [{ to: "/client-errors", label: "Ошибки приложения", icon: "bug" }],
  },
];

const navItems = navGroups.flatMap((g) => g.items);

export function Layout({ children }: { children: ReactNode }) {
  const { logout } = useAuth();
  const location = useLocation();
  usePageTransitions();
  const enterDir = usePageEnter(location.pathname);
  const section = navItems.find(
    (item) => location.pathname === item.to || location.pathname.startsWith(`${item.to}/`),
  );

  return (
    <div className="min-h-screen">
      <Backdrop />

      <header className="app-header glass-bar sticky top-0 z-30">
        <div className="mx-auto flex h-14 max-w-[1440px] items-center gap-3 px-4 sm:px-6">
          <div className="flex min-w-0 flex-1 items-center gap-2.5">
            <img src={logoMark} alt="" className="h-7 w-7 shrink-0" />
            <span className="truncate text-[15px] font-semibold tracking-tight text-slate-900">
              GuYo <span className="font-normal text-slate-400">Admin</span>
            </span>
          </div>
          <div className="hidden min-w-0 flex-1 justify-center md:flex">
            <span className="truncate text-[14px] font-medium text-slate-500">{section?.label}</span>
          </div>
          <div className="flex flex-1 justify-end">
            <button onClick={logout} className="rounded-lg px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-[var(--fill)] hover:text-slate-900">
              Выйти
            </button>
          </div>
        </div>
      </header>

      <div className="mx-auto flex max-w-[1440px] flex-col md:flex-row md:gap-8 md:px-6">
        <aside className="md:sticky md:top-14 md:h-[calc(100dvh-3.5rem)] md:w-60 md:shrink-0 md:overflow-y-auto md:py-6">
          <nav
            aria-label="Разделы"
            className="flex gap-1.5 overflow-x-auto px-4 py-3 [scrollbar-width:none] md:flex-col md:gap-5 md:overflow-visible md:p-0"
          >
            {navGroups.map((group) => (
              <div key={group.title} className="contents md:flex md:flex-col md:gap-0.5">
                <p className="hidden px-3 pb-1 text-[11px] font-medium uppercase tracking-[0.08em] text-slate-400 md:block">
                  {group.title}
                </p>
                {group.items.map((item) => (
                  <NavLink
                    key={item.to}
                    to={item.to}
                    className={({ isActive }) =>
                      `flex shrink-0 items-center gap-2.5 whitespace-nowrap rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors md:rounded-lg md:px-3 md:py-[7px] md:text-[14px] ${
                        isActive
                          ? "bg-indigo-50 text-indigo-700"
                          : "bg-[var(--fill)] text-slate-600 hover:bg-[var(--fill-strong)] hover:text-slate-900 md:bg-transparent md:hover:bg-[var(--fill)]"
                      }`
                    }
                  >
                    <span className="hidden md:inline-flex">
                      <NavIcon name={item.icon} />
                    </span>
                    {item.label}
                  </NavLink>
                ))}
              </div>
            ))}
          </nav>
        </aside>

        <main className="min-w-0 flex-1 px-4 pb-16 pt-2 sm:px-6 md:px-0 md:pt-6">
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

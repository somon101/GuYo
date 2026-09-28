import type { ReactNode } from "react";
import { NavLink, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { usePageEnter, usePageTransitions } from "../lib/pageTransitions";
import { Backdrop } from "./Backdrop";
import logoMark from "../assets/logo-mark.png";

const navItems = [
  { to: "/users", label: "Пользователи" },
  { to: "/dictionaries", label: "Языки" },
  { to: "/exercises", label: "Упражнения" },
  { to: "/achievements", label: "Достижения" },
  { to: "/rating", label: "Рейтинг" },
  { to: "/quests", label: "Квесты" },
  { to: "/slogans", label: "Слоганы" },
  { to: "/notifications", label: "Уведомления" },
  { to: "/premium", label: "Premium" },
  { to: "/promo", label: "Промокоды" },
  { to: "/retention", label: "Удержание" },
  { to: "/analytics", label: "Аналитика" },
];

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
            <span className="truncate text-[17px] font-semibold tracking-tight text-slate-900">GuYo Admin</span>
          </div>
          <div className="hidden min-w-0 flex-1 justify-center md:flex">
            <span className="truncate text-[17px] font-semibold text-slate-900">{section?.label}</span>
          </div>
          <div className="flex flex-1 justify-end">
            <button onClick={logout} className="btn-tinted rounded-full px-3.5 py-1.5 text-sm font-medium">
              Выйти
            </button>
          </div>
        </div>
      </header>

      <div className="mx-auto flex max-w-[1440px] flex-col md:flex-row md:gap-8 md:px-6">
        <aside className="md:sticky md:top-14 md:h-[calc(100dvh-3.5rem)] md:w-56 md:shrink-0 md:overflow-y-auto md:py-6">
          <nav
            aria-label="Разделы"
            className="flex gap-1.5 overflow-x-auto px-4 py-3 [scrollbar-width:none] md:flex-col md:gap-0.5 md:overflow-visible md:p-0"
          >
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  `shrink-0 whitespace-nowrap rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors md:rounded-[10px] md:px-3 md:py-[7px] md:text-[15px] ${
                    isActive
                      ? "bg-[var(--sys-blue)] text-white"
                      : "bg-[var(--fill)] text-slate-900 hover:bg-[var(--fill-strong)] md:bg-transparent md:hover:bg-[var(--fill)]"
                  }`
                }
              >
                {item.label}
              </NavLink>
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

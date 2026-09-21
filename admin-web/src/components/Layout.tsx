import type { ReactNode } from "react";
import { NavLink } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import logoMark from "../assets/logo-mark.png";

const navItems = [
  { to: "/users", label: "Пользователи" },
  { to: "/dictionaries", label: "Языки" },
  { to: "/exercises", label: "Упражнения" },
  { to: "/achievements", label: "Достижения" },
  { to: "/rating", label: "Рейтинг" },
  { to: "/quests", label: "Квесты" },
  { to: "/analytics", label: "Аналитика" },
];

export function Layout({ children }: { children: ReactNode }) {
  const { logout } = useAuth();

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <aside className="flex shrink-0 flex-col border-b border-slate-200 bg-white md:w-56 md:border-b-0 md:border-r">
        <div className="flex items-center gap-2 px-5 py-5">
          <img src={logoMark} alt="" className="h-7 w-7" />
          <span className="text-lg font-semibold tracking-tight text-slate-900">
            GuYo Admin
          </span>
        </div>
        <nav className="flex flex-1 flex-row gap-1 px-2 pb-2 md:flex-col md:px-3">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) =>
                `rounded-md px-3 py-2 text-sm font-medium transition-colors ${
                  isActive
                    ? "bg-indigo-50 text-indigo-700"
                    : "text-slate-600 hover:bg-slate-100 hover:text-slate-900"
                }`
              }
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="px-3 pb-4">
          <button
            onClick={logout}
            className="w-full rounded-md px-3 py-2 text-left text-sm font-medium text-slate-500 hover:bg-slate-100 hover:text-slate-900"
          >
            Выйти
          </button>
        </div>
      </aside>
      <main className="flex-1 px-4 py-6 sm:px-6 lg:px-10">{children}</main>
    </div>
  );
}

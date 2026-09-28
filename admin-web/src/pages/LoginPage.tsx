import { useState, type FormEvent } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { isAxiosError } from "axios";
import { Backdrop } from "../components/Backdrop";
import logoMark from "../assets/logo-mark.png";

export function LoginPage() {
  const { isAuthenticated, login } = useAuth();
  const navigate = useNavigate();
  const [loginValue, setLoginValue] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (isAuthenticated) {
    return <Navigate to="/users" replace />;
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await login(loginValue, password);
      navigate("/users", { replace: true });
    } catch (err) {
      if (isAxiosError(err) && err.response?.status === 401) {
        setError("Неверный логин или пароль");
      } else {
        setError("Не удалось подключиться к серверу");
      }
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-10">
      <Backdrop />
      <div className="card w-full max-w-sm p-8">
        <img src={logoMark} alt="" className="mx-auto mb-4 h-14 w-14" />
        <h1 className="mb-1 text-center text-[26px] font-bold tracking-tight text-slate-900">GuYo Admin</h1>
        <p className="mb-7 text-center text-[15px] text-slate-500">Вход для администратора</p>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div>
            <label htmlFor="login" className="mb-1.5 block text-[13px] font-medium text-slate-500">
              Логин
            </label>
            <input
              id="login"
              className="field w-full px-3.5 py-2.5 text-[15px]"
              value={loginValue}
              onChange={(e) => setLoginValue(e.target.value)}
              autoComplete="username"
              autoFocus
              required
            />
          </div>
          <div>
            <label htmlFor="password" className="mb-1.5 block text-[13px] font-medium text-slate-500">
              Пароль
            </label>
            <input
              id="password"
              type="password"
              className="field w-full px-3.5 py-2.5 text-[15px]"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              required
            />
          </div>

          {error && <p className="text-sm text-red-600">{error}</p>}

          <button
            type="submit"
            disabled={isSubmitting}
            className="mt-2 rounded-[12px] bg-indigo-600 px-4 py-3 text-[15px] font-semibold text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {isSubmitting ? "Вход…" : "Войти"}
          </button>
        </form>
      </div>
    </div>
  );
}

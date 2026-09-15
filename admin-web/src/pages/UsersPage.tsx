import { useEffect, useState, type FormEvent } from "react";
import { isAxiosError } from "axios";
import { createUser, listUsers } from "../api/endpoints";
import type { AdminUser } from "../types";

function formatDate(iso: string): string {
  return new Date(iso).toLocaleString("ru-RU", {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

export function UsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isFormOpen, setIsFormOpen] = useState(false);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      setUsers(await listUsers());
    } catch {
      setLoadError("Не удалось загрузить пользователей");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-slate-900">Пользователи</h1>
        <button
          onClick={() => setIsFormOpen((v) => !v)}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Новый пользователь
        </button>
      </div>

      {isFormOpen && (
        <CreateUserForm
          onCreated={() => {
            setIsFormOpen(false);
            reload();
          }}
          onCancel={() => setIsFormOpen(false)}
        />
      )}

      <div className="overflow-hidden rounded-lg border border-slate-200 bg-white">
        {isLoading ? (
          <p className="p-6 text-sm text-slate-500">Загрузка…</p>
        ) : loadError ? (
          <p className="p-6 text-sm text-red-600">{loadError}</p>
        ) : users.length === 0 ? (
          <p className="p-6 text-sm text-slate-500">Пользователей пока нет</p>
        ) : (
          <table className="w-full text-left text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">ID</th>
                <th className="px-4 py-3 font-medium">Логин</th>
                <th className="px-4 py-3 font-medium">Дата создания</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {users.map((u) => (
                <tr key={u.id}>
                  <td className="px-4 py-3 text-slate-500">{u.id}</td>
                  <td className="px-4 py-3 font-medium text-slate-900">{u.login}</td>
                  <td className="px-4 py-3 text-slate-500">{formatDate(u.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function CreateUserForm({ onCreated, onCancel }: { onCreated: () => void; onCancel: () => void }) {
  const [login, setLogin] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await createUser(login, password);
      onCreated();
    } catch (err) {
      if (isAxiosError(err) && err.response?.status === 409) {
        setError("Такой логин уже занят");
      } else {
        setError("Не удалось создать пользователя");
      }
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="mb-6 flex flex-col gap-3 rounded-lg border border-slate-200 bg-white p-5 sm:flex-row sm:items-end"
    >
      <div className="flex-1">
        <label className="mb-1 block text-sm font-medium text-slate-700">Логин</label>
        <input
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={login}
          onChange={(e) => setLogin(e.target.value)}
          autoFocus
          required
          minLength={3}
        />
      </div>
      <div className="flex-1">
        <label className="mb-1 block text-sm font-medium text-slate-700">Пароль</label>
        <input
          type="password"
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          minLength={4}
        />
      </div>
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          Создать
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
        >
          Отмена
        </button>
      </div>
      {error && <p className="w-full text-sm text-red-600 sm:mt-2">{error}</p>}
    </form>
  );
}

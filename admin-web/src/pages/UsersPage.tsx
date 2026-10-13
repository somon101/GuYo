import { useEffect, useState, type FormEvent } from "react";
import { isAxiosError } from "axios";
import { createUser, deleteUser, listUsers, setUserTextCheckUnlimited } from "../api/endpoints";
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

  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [togglingLimitId, setTogglingLimitId] = useState<number | null>(null);

  /** «Проверка текста» without the daily limit for one person -- for a tester
   * or a team member. Deliberately independent of Premium. */
  async function handleUnlimitedToggle(user: AdminUser) {
    const next = !user.text_check_unlimited;
    setTogglingLimitId(user.id);
    try {
      await setUserTextCheckUnlimited(user.id, next);
      setUsers((prev) => prev.map((u) => (u.id === user.id ? { ...u, text_check_unlimited: next } : u)));
    } catch {
      window.alert("Не удалось изменить лимит проверок текста");
    } finally {
      setTogglingLimitId(null);
    }
  }

  // Irreversible (progress, rating, purchases go with it), so the admin
  // types the login to confirm instead of clicking through a yes/no.
  async function handleDelete(user: AdminUser) {
    const typed = window.prompt(
      `Удалить пользователя «${user.login}» навсегда?\nВместе с ним удалятся весь прогресс, рейтинг, друзья и уведомления. Отменить нельзя.\n\nЧтобы подтвердить, введите его логин:`,
    );
    if (typed === null) return;
    if (typed.trim() !== user.login) {
      window.alert("Логин не совпал — пользователь не удалён.");
      return;
    }
    setDeletingId(user.id);
    try {
      await deleteUser(user.id);
      setUsers((prev) => prev.filter((u) => u.id !== user.id));
    } catch {
      window.alert("Не удалось удалить пользователя");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="mx-auto max-w-5xl">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-[26px] font-bold tracking-tight text-slate-900">Пользователи</h1>
        <button
          onClick={() => setIsFormOpen((v) => !v)}
          className="whitespace-nowrap rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
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

      <div className="overflow-x-auto card">
        {isLoading ? (
          <p className="p-6 text-sm text-slate-500">Загрузка…</p>
        ) : loadError ? (
          <p className="p-6 text-sm text-red-600">{loadError}</p>
        ) : users.length === 0 ? (
          <p className="p-6 text-sm text-slate-500">Пользователей пока нет</p>
        ) : (
          <table className="w-full text-left text-sm">
            <thead className="border-b border-slate-100 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">ID</th>
                <th className="px-4 py-3 font-medium">Логин</th>
                <th className="px-4 py-3 font-medium">Имя</th>
                <th className="px-4 py-3 font-medium">Почта</th>
                <th className="whitespace-nowrap px-4 py-3 font-medium">Дата создания</th>
                <th className="whitespace-nowrap px-4 py-3 font-medium" title="Безлимит проверок текста">
                  Проверка текста
                </th>
                <th className="px-4 py-3" aria-label="Действия" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {users.map((u) => (
                <tr key={u.id}>
                  {/* The 9-digit account number, not the internal key. */}
                  <td className="px-4 py-3 font-mono text-slate-500">{u.public_id}</td>
                  <td className="px-4 py-3 font-medium text-slate-900" translate="no">{u.login}</td>
                  <td className="px-4 py-3 text-slate-500" translate="no">
                    {[u.first_name, u.last_name].filter(Boolean).join(" ") || "—"}
                  </td>
                  <td className="px-4 py-3 text-slate-500" translate="no">{u.email ?? "—"}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-slate-500">{formatDate(u.created_at)}</td>
                  <td className="whitespace-nowrap px-4 py-3">
                    <label
                      className="flex cursor-pointer items-center gap-2 text-xs text-slate-500"
                      title="Проверка текста без дневного лимита"
                    >
                      <input
                        type="checkbox"
                        className="switch"
                        checked={u.text_check_unlimited}
                        disabled={togglingLimitId === u.id}
                        onChange={() => handleUnlimitedToggle(u)}
                      />
                      безлимит
                    </label>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <button
                      type="button"
                      onClick={() => handleDelete(u)}
                      disabled={deletingId === u.id}
                      className="rounded-md px-2.5 py-1 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                    >
                      {deletingId === u.id ? "Удаление…" : "Удалить"}
                    </button>
                  </td>
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
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await createUser({ login, password, firstName, lastName, email });
      onCreated();
    } catch (err) {
      if (isAxiosError(err) && err.response?.status === 409) {
        // The backend says WHICH one is taken — login or email.
        const detail = err.response?.data?.detail as string | undefined;
        setError(detail ?? "Такой логин уже занят");
      } else if (isAxiosError(err) && err.response?.status === 422) {
        setError("Проверьте поля: имя, фамилия и корректный адрес почты обязательны");
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
      className="mb-6 grid grid-cols-1 gap-3 card p-5 sm:grid-cols-3"
    >
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Логин</label>
        <input
          className="w-full field px-3 py-2 text-sm"
          value={login}
          // Same rules as the app: English letters, digits, _ and ., case-insensitive.
          onChange={(e) => setLogin(e.target.value.toLowerCase().replace(/[^a-z0-9_.]/g, ""))}
          autoFocus
          required
          minLength={3}
          maxLength={13}
          placeholder="a-z, 0-9, _ ."
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Пароль</label>
        <input
          type="password"
          className="w-full field px-3 py-2 text-sm"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          minLength={4}
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Имя</label>
        <input
          className="w-full field px-3 py-2 text-sm"
          value={firstName}
          onChange={(e) => setFirstName(e.target.value)}
          required
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Фамилия</label>
        <input
          className="w-full field px-3 py-2 text-sm"
          value={lastName}
          onChange={(e) => setLastName(e.target.value)}
          required
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Электронная почта</label>
        <input
          type="email"
          className="w-full field px-3 py-2 text-sm"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
      </div>
      <div className="flex items-end gap-2">
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
          className="btn-tinted rounded-md px-4 py-2 text-sm font-medium"
        >
          Отмена
        </button>
      </div>
      {error && <p className="w-full text-sm text-red-600 sm:mt-2">{error}</p>}
    </form>
  );
}

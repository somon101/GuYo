import axios from "axios";
import { useEffect, useState, type FormEvent } from "react";
import { listSentNotifications, listUsers, sendNotification } from "../api/endpoints";
import type { AdminNotification, AdminUser } from "../types";

function formatDate(value: string): string {
  return new Date(value).toLocaleString("ru-RU", { dateStyle: "short", timeStyle: "short" });
}

/**
 * "Уведомления": write to one user, and see what has been sent.
 *
 * Sending goes through the backend's own send_notification, the same
 * function a future automatic rule will call -- so the list below already
 * shows every notification there is, not just the hand-written ones. When
 * rules arrive, their messages appear here too, told apart by "источник".
 */
export function NotificationsPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [sent, setSent] = useState<AdminNotification[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [filterUserId, setFilterUserId] = useState<number | "">("");

  async function reload(userId?: number) {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [u, n] = await Promise.all([listUsers(), listSentNotifications(userId)]);
      setUsers(u);
      setSent(n);
    } catch {
      setLoadError("Не удалось загрузить данные");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  const filtered = filterUserId === "" ? sent : sent.filter((n) => n.user_id === filterUserId);

  return (
    <div className="p-6">
      <h1 className="mb-1 text-xl font-semibold text-slate-900">Уведомления</h1>
      <p className="mb-6 max-w-2xl text-sm text-slate-500">
        Сообщение приходит выбранному пользователю в раздел «Уведомления» в приложении: у него появляется индикатор, а
        при открытии сообщение отмечается прочитанным. Автоматические уведомления по событиям пока не настраиваются, но
        они будут попадать в этот же список.
      </p>

      <SendForm
        users={users}
        onSent={(notification) => setSent((prev) => [notification, ...prev])}
      />

      <div className="mt-8 mb-3 flex items-center gap-3">
        <h2 className="text-sm font-semibold text-slate-900">Отправленные</h2>
        <select
          className="rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={filterUserId}
          onChange={(e) => setFilterUserId(e.target.value === "" ? "" : Number(e.target.value))}
        >
          <option value="">Все пользователи</option>
          {users.map((u) => (
            <option key={u.id} value={u.id}>
              {u.login}
            </option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : filtered.length === 0 ? (
        <p className="text-sm text-slate-500">Пока ничего не отправлено</p>
      ) : (
        <div className="overflow-hidden rounded-lg border border-slate-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Кому</th>
                <th className="px-4 py-3 font-medium">Сообщение</th>
                <th className="px-4 py-3 font-medium">Источник</th>
                <th className="px-4 py-3 font-medium">Отправлено</th>
                <th className="px-4 py-3 font-medium">Статус</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filtered.map((n) => (
                <tr key={n.id}>
                  <td className="px-4 py-3 font-medium text-slate-900" translate="no">
                    {n.user_login}
                  </td>
                  <td className="max-w-md px-4 py-3 text-slate-700">
                    {n.title && <span className="mr-1 font-medium text-slate-900">{n.title}</span>}
                    {n.body}
                  </td>
                  <td className="px-4 py-3 text-slate-500">
                    {n.source === "manual" ? "вручную" : n.source}
                  </td>
                  <td className="px-4 py-3 text-slate-500">{formatDate(n.created_at)}</td>
                  <td className="px-4 py-3">
                    {n.is_read ? (
                      <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                        прочитано
                      </span>
                    ) : (
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700">
                        не прочитано
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function SendForm({
  users,
  onSent,
}: {
  users: AdminUser[];
  onSent: (notification: AdminNotification) => void;
}) {
  const [userId, setUserId] = useState<number | "">("");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentTo, setSentTo] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSentTo(null);
    if (userId === "") {
      setError("Выберите пользователя");
      return;
    }
    if (!body.trim()) {
      setError("Введите текст сообщения");
      return;
    }
    setIsSubmitting(true);
    try {
      const notification = await sendNotification({
        userId,
        title: title.trim() || undefined,
        body: body.trim(),
      });
      onSent(notification);
      setSentTo(notification.user_login);
      setTitle("");
      setBody("");
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setError(detail ?? "Не удалось отправить сообщение");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="rounded-lg border border-slate-200 bg-white p-5">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Кому</label>
          <select
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={userId}
            onChange={(e) => setUserId(e.target.value === "" ? "" : Number(e.target.value))}
          >
            <option value="">Выберите пользователя</option>
            {users.map((u) => (
              <option key={u.id} value={u.id}>
                {u.login} · {u.public_id}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Заголовок (необязательно)</label>
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={120}
          />
        </div>
      </div>

      <div className="mt-4">
        <label className="mb-1 block text-sm font-medium text-slate-700">Сообщение</label>
        <textarea
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={body}
          onChange={(e) => setBody(e.target.value)}
          rows={3}
          maxLength={2000}
        />
      </div>

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
      {sentTo && <p className="mt-3 text-sm text-emerald-700">Отправлено пользователю {sentTo}</p>}

      <button
        type="submit"
        disabled={isSubmitting}
        className="mt-4 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
      >
        {isSubmitting ? "Отправка…" : "Отправить"}
      </button>
    </form>
  );
}

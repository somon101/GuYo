import axios from "axios";
import { useEffect, useMemo, useState, type FormEvent } from "react";
import {
  getPremiumSettings,
  grantPremium,
  listPremiumGrants,
  listPremiumUsers,
  listUsers,
  revokePremium,
  updatePremiumSettings,
} from "../api/endpoints";
import type { AdminUser, PremiumGrant, PremiumSettings, PremiumUser } from "../types";

const inputClass =
  "w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500";

const PERIODS = [
  { days: 30, label: "1 месяц" },
  { days: 90, label: "3 месяца" },
  { days: 180, label: "6 месяцев" },
  { days: 365, label: "1 год" },
];

function formatDate(value: string): string {
  return new Date(value).toLocaleDateString("ru-RU");
}

function errorDetail(err: unknown, fallback: string): string {
  const detail = axios.isAxiosError(err) ? err.response?.data?.detail : undefined;
  return typeof detail === "string" ? detail : fallback;
}

/**
 * "Premium": payment happens outside the app -- the user transfers money
 * and puts their 9-digit ID in the comment, and the admin grants a period
 * here. Premium then ends on its own when the period runs out.
 */
export function PremiumPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [subscribers, setSubscribers] = useState<PremiumUser[]>([]);
  const [grants, setGrants] = useState<PremiumGrant[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [selectedUserId, setSelectedUserId] = useState<number | "">("");

  async function reload() {
    setLoadError(null);
    try {
      const [u, s, g] = await Promise.all([listUsers(), listPremiumUsers(), listPremiumGrants()]);
      setUsers(u);
      setSubscribers(s);
      setGrants(g);
    } catch {
      setLoadError("Не удалось загрузить данные");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  const loginById = useMemo(() => new Map(users.map((u) => [u.id, u.login])), [users]);

  async function handleRevoke(sub: PremiumUser) {
    if (!window.confirm(`Отключить Premium у ${sub.login}? Оставшиеся дни пропадут.`)) return;
    try {
      await revokePremium(sub.user_id);
      await reload();
    } catch (err) {
      window.alert(errorDetail(err, "Не удалось отключить Premium"));
    }
  }

  const active = subscribers.filter((s) => s.is_premium);

  return (
    <div className="p-6">
      <h1 className="mb-1 text-xl font-semibold text-slate-900">Premium</h1>
      <p className="mb-6 max-w-2xl text-sm text-slate-500">
        Пользователь переводит деньги и указывает в комментарии свой ID (9 цифр, он виден в приложении на экране
        Premium). Найдите его здесь и включите Premium на оплаченный срок. Если подписка уже активна, новый срок
        добавится к её концу. Когда срок закончится, Premium отключится сам.
      </p>

      <GrantForm
        users={users}
        selectedUserId={selectedUserId}
        onSelectUser={setSelectedUserId}
        onGranted={reload}
      />

      <h2 className="mt-8 mb-3 text-sm font-semibold text-slate-900">
        Подписчики{active.length > 0 && <span className="ml-1 font-normal text-slate-500">· активных: {active.length}</span>}
      </h2>
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : subscribers.length === 0 ? (
        <p className="text-sm text-slate-500">Пока никто не оформил Premium</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Пользователь</th>
                <th className="px-4 py-3 font-medium">ID</th>
                <th className="px-4 py-3 font-medium">Статус</th>
                <th className="px-4 py-3 font-medium" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {subscribers.map((s) => (
                <tr key={s.user_id}>
                  <td className="px-4 py-3">
                    <div className="font-medium text-slate-900" translate="no">
                      {s.login}
                    </div>
                    {(s.first_name || s.last_name) && (
                      <div className="text-xs text-slate-500">{[s.first_name, s.last_name].filter(Boolean).join(" ")}</div>
                    )}
                  </td>
                  <td className="px-4 py-3 tabular-nums text-slate-600">{s.public_id}</td>
                  <td className="px-4 py-3">
                    {s.is_premium && s.premium_until ? (
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
                        активен до {formatDate(s.premium_until)}
                      </span>
                    ) : (
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600">
                        не активен
                      </span>
                    )}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right">
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedUserId(s.user_id);
                        window.scrollTo({ top: 0, behavior: "smooth" });
                      }}
                      className="rounded-md px-2 py-1 text-sm font-medium text-indigo-600 hover:bg-indigo-50"
                    >
                      Продлить
                    </button>
                    {s.is_premium && (
                      <button
                        type="button"
                        onClick={() => handleRevoke(s)}
                        className="ml-1 rounded-md px-2 py-1 text-sm font-medium text-red-600 hover:bg-red-50"
                      >
                        Отключить
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {grants.length > 0 && (
        <>
          <h2 className="mt-8 mb-3 text-sm font-semibold text-slate-900">История оплат</h2>
          <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
            <table className="w-full text-left text-sm">
              <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-3 font-medium">Кому</th>
                  <th className="px-4 py-3 font-medium">Период</th>
                  <th className="px-4 py-3 font-medium">Заметка</th>
                  <th className="px-4 py-3 font-medium">Выдал</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {grants.map((g) => (
                  <tr key={g.id} className={g.revoked_at ? "text-slate-400" : ""}>
                    <td className="px-4 py-3 font-medium" translate="no">
                      {loginById.get(g.user_id) ?? `#${g.user_id}`}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">
                      {g.days} дн. · {formatDate(g.starts_at)} — {formatDate(g.ends_at)}
                      {g.revoked_at && <span className="ml-2 text-xs">(отключён {formatDate(g.revoked_at)})</span>}
                    </td>
                    <td className="max-w-xs px-4 py-3">{g.note ?? "—"}</td>
                    <td className="px-4 py-3">{g.granted_by_admin_login ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <SettingsForm />
    </div>
  );
}

function GrantForm({
  users,
  selectedUserId,
  onSelectUser,
  onGranted,
}: {
  users: AdminUser[];
  selectedUserId: number | "";
  onSelectUser: (id: number | "") => void;
  onGranted: () => Promise<void>;
}) {
  const [search, setSearch] = useState("");
  const [days, setDays] = useState(30);
  const [note, setNote] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  // Typing a 9-digit ID or part of a login narrows the list; an exact ID
  // match is picked straight away, since that is what the transfer comment
  // carries.
  const query = search.trim().toLowerCase();
  const matches = query
    ? users.filter((u) => String(u.public_id).includes(query) || u.login.toLowerCase().includes(query))
    : users;

  useEffect(() => {
    const exact = users.find((u) => String(u.public_id) === query);
    if (exact) onSelectUser(exact.id);
  }, [query, users, onSelectUser]);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    if (selectedUserId === "") {
      setError("Выберите пользователя");
      return;
    }
    if (!Number.isInteger(days) || days < 1) {
      setError("Укажите срок в днях");
      return;
    }
    setIsSubmitting(true);
    try {
      const grant = await grantPremium(selectedUserId, { days, note: note.trim() || undefined });
      const login = users.find((u) => u.id === selectedUserId)?.login ?? "";
      setSuccess(`Premium для ${login} активен до ${formatDate(grant.ends_at)}`);
      setNote("");
      await onGranted();
    } catch (err) {
      setError(errorDetail(err, "Не удалось включить Premium"));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="rounded-lg border border-slate-200 bg-white p-5">
      <h2 className="mb-4 text-sm font-semibold text-slate-900">Включить Premium</h2>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Поиск по ID или логину</label>
          <input
            className={inputClass}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="например, 482915306"
            inputMode="search"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Пользователь</label>
          <select
            className={inputClass}
            value={selectedUserId}
            onChange={(e) => onSelectUser(e.target.value === "" ? "" : Number(e.target.value))}
          >
            <option value="">Выберите пользователя</option>
            {matches.map((u) => (
              <option key={u.id} value={u.id}>
                {u.login} · {u.public_id}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="mt-4">
        <label className="mb-1 block text-sm font-medium text-slate-700">Срок</label>
        <div className="flex flex-wrap items-center gap-2">
          {PERIODS.map((p) => (
            <button
              key={p.days}
              type="button"
              onClick={() => setDays(p.days)}
              className={`rounded-md border px-3 py-1.5 text-sm font-medium ${
                days === p.days
                  ? "border-indigo-600 bg-indigo-50 text-indigo-700"
                  : "border-slate-300 text-slate-700 hover:bg-slate-50"
              }`}
            >
              {p.label}
            </button>
          ))}
          <div className="flex items-center gap-2">
            <input
              type="number"
              min={1}
              max={1095}
              className={`${inputClass} w-24`}
              value={days}
              onChange={(e) => setDays(Number(e.target.value))}
            />
            <span className="text-sm text-slate-500">дней</span>
          </div>
        </div>
      </div>

      <div className="mt-4">
        <label className="mb-1 block text-sm font-medium text-slate-700">Заметка об оплате (необязательно)</label>
        <input
          className={inputClass}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={500}
          placeholder="например, Алиф, 50 сомони, 26.09"
        />
      </div>

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
      {success && <p className="mt-3 text-sm text-emerald-700">{success}</p>}

      <button
        type="submit"
        disabled={isSubmitting}
        className="mt-4 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
      >
        {isSubmitting ? "Сохранение…" : "Включить Premium"}
      </button>
      <p className="mt-2 text-xs text-slate-500">Пользователь получит уведомление в приложении.</p>
    </form>
  );
}

// Limits are edited as text so that an empty field can mean "no limit".
type LimitKey =
  | "free_daily_lesson_limit"
  | "free_weekly_lesson_limit"
  | "premium_daily_lesson_limit"
  | "premium_weekly_lesson_limit";

function SettingsForm() {
  const [settings, setSettings] = useState<PremiumSettings | null>(null);
  const [limits, setLimits] = useState<Record<LimitKey, string>>({
    free_daily_lesson_limit: "",
    free_weekly_lesson_limit: "",
    premium_daily_lesson_limit: "",
    premium_weekly_lesson_limit: "",
  });
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  function load(s: PremiumSettings) {
    setSettings(s);
    setLimits({
      free_daily_lesson_limit: s.free_daily_lesson_limit?.toString() ?? "",
      free_weekly_lesson_limit: s.free_weekly_lesson_limit?.toString() ?? "",
      premium_daily_lesson_limit: s.premium_daily_lesson_limit?.toString() ?? "",
      premium_weekly_lesson_limit: s.premium_weekly_lesson_limit?.toString() ?? "",
    });
  }

  useEffect(() => {
    getPremiumSettings()
      .then(load)
      .catch(() => setError("Не удалось загрузить настройки"));
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!settings) return;
    setError(null);
    setSaved(false);

    const parsed = {} as Record<LimitKey, number | null>;
    for (const key of Object.keys(limits) as LimitKey[]) {
      const raw = limits[key].trim();
      if (raw === "") {
        parsed[key] = null;
        continue;
      }
      const n = Number(raw);
      if (!Number.isInteger(n) || n < 0) {
        setError("Лимит — целое число от 0, или пустое поле (без ограничений)");
        return;
      }
      parsed[key] = n;
    }

    setIsSaving(true);
    try {
      load(await updatePremiumSettings({ ...settings, ...parsed }));
      setSaved(true);
    } catch (err) {
      setError(errorDetail(err, "Не удалось сохранить"));
    } finally {
      setIsSaving(false);
    }
  }

  function limitInput(key: LimitKey) {
    return (
      <input
        type="number"
        min={0}
        className={inputClass}
        value={limits[key]}
        onChange={(e) => setLimits((prev) => ({ ...prev, [key]: e.target.value }))}
        placeholder="без ограничений"
      />
    );
  }

  return (
    <form onSubmit={handleSubmit} className="mt-8 rounded-lg border border-slate-200 bg-white p-5">
      <h2 className="mb-1 text-sm font-semibold text-slate-900">Настройки</h2>
      <p className="mb-4 max-w-2xl text-sm text-slate-500">
        Лимит — сколько уроков пользователь может создать сам. Автоуроки не считаются. День и неделя — по времени
        Душанбе, неделя начинается в понедельник. Пустое поле — без ограничений.
      </p>

      {!settings ? (
        error ? <p className="text-sm text-red-600">{error}</p> : <p className="text-sm text-slate-500">Загрузка…</p>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <fieldset className="rounded-md border border-slate-200 p-4">
              <legend className="px-1 text-sm font-medium text-slate-700">Без подписки</legend>
              <label className="mb-1 block text-sm text-slate-600">Уроков в день</label>
              {limitInput("free_daily_lesson_limit")}
              <label className="mb-1 mt-3 block text-sm text-slate-600">Уроков в неделю</label>
              {limitInput("free_weekly_lesson_limit")}
            </fieldset>
            <fieldset className="rounded-md border border-slate-200 p-4">
              <legend className="px-1 text-sm font-medium text-slate-700">Premium</legend>
              <label className="mb-1 block text-sm text-slate-600">Уроков в день</label>
              {limitInput("premium_daily_lesson_limit")}
              <label className="mb-1 mt-3 block text-sm text-slate-600">Уроков в неделю</label>
              {limitInput("premium_weekly_lesson_limit")}
            </fieldset>
          </div>

          <div className="mt-4 space-y-2">
            <label className="flex items-center gap-2 text-sm text-slate-700">
              <input
                type="checkbox"
                checked={settings.adaptive_lessons_premium_only}
                onChange={(e) => setSettings({ ...settings, adaptive_lessons_premium_only: e.target.checked })}
              />
              Автоуроки для закрепления — только для Premium
            </label>
            <label className="flex items-center gap-2 text-sm text-slate-700">
              <input
                type="checkbox"
                checked={settings.personal_quests_premium_only}
                onChange={(e) => setSettings({ ...settings, personal_quests_premium_only: e.target.checked })}
              />
              Персональные квесты — только для Premium
            </label>
          </div>

          <div className="mt-4">
            <label className="mb-1 block text-sm font-medium text-slate-700">Цена (показывается в приложении)</label>
            <input
              className={inputClass}
              value={settings.price_text}
              onChange={(e) => setSettings({ ...settings, price_text: e.target.value })}
              maxLength={200}
              placeholder="например, 30 сомони в месяц · 300 сомони в год"
            />
          </div>
          <div className="mt-4">
            <label className="mb-1 block text-sm font-medium text-slate-700">Как оплатить (показывается в приложении)</label>
            <textarea
              className={inputClass}
              rows={4}
              value={settings.payment_instructions}
              onChange={(e) => setSettings({ ...settings, payment_instructions: e.target.value })}
              maxLength={4000}
              placeholder={"например:\nПереведите сумму на Алиф: +992 ...\nВ комментарии укажите свой ID."}
            />
          </div>

          {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
          {saved && <p className="mt-3 text-sm text-emerald-700">Сохранено</p>}

          <button
            type="submit"
            disabled={isSaving}
            className="mt-4 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {isSaving ? "Сохранение…" : "Сохранить"}
          </button>
        </>
      )}
    </form>
  );
}

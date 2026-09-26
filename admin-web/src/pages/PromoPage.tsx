import axios from "axios";
import { useEffect, useState, type FormEvent } from "react";
import {
  createPromoCode,
  createPromoLink,
  deletePromoCode,
  deletePromoLink,
  getPromoSettings,
  listPromoActivations,
  listPromoCodes,
  listPromoLinks,
  updatePromoCode,
  updatePromoLink,
  updatePromoSettings,
} from "../api/endpoints";
import type { PromoActivation, PromoCode, PromoLink, PromoSettings } from "../types";

const inputClass =
  "w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500";
const primaryButton =
  "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60";
const secondaryButton = "rounded-md px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100";

function formatDate(value: string): string {
  return new Date(value).toLocaleDateString("ru-RU");
}

function errorDetail(err: unknown, fallback: string): string {
  const detail = axios.isAxiosError(err) ? err.response?.data?.detail : undefined;
  return typeof detail === "string" ? detail : fallback;
}

/** "" -> null, otherwise a positive integer, or undefined when invalid. */
function optionalPositive(raw: string): number | null | undefined {
  if (raw.trim() === "") return null;
  const n = Number(raw);
  return Number.isInteger(n) && n > 0 ? n : undefined;
}

function StatusPill({ enabled }: { enabled: boolean }) {
  return enabled ? (
    <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">включён</span>
  ) : (
    <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600">выключен</span>
  );
}

/**
 * "Промокоды": codes the admin makes up, and links to GuYo's own videos.
 * A user enters either one in the app's "Промокод" screen and gets Premium
 * days -- added to the end of an active subscription, like a payment.
 */
export function PromoPage() {
  const [codes, setCodes] = useState<PromoCode[]>([]);
  const [links, setLinks] = useState<PromoLink[]>([]);
  const [activations, setActivations] = useState<PromoActivation[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);

  async function reload() {
    setLoadError(null);
    try {
      const [c, l, a] = await Promise.all([listPromoCodes(), listPromoLinks(), listPromoActivations()]);
      setCodes(c);
      setLinks(l);
      setActivations(a);
    } catch {
      setLoadError("Не удалось загрузить данные");
    }
  }

  useEffect(() => {
    reload();
  }, []);

  return (
    <div className="p-6">
      <h1 className="mb-1 text-xl font-semibold text-slate-900">Промокоды</h1>
      <p className="mb-6 max-w-2xl text-sm text-slate-500">
        Пользователь вводит промокод или вставляет ссылку на видео в приложении (меню «⋮» → «Промокод» или экран
        Premium) и получает дни Premium. Каждый промокод и каждую ссылку один человек может активировать только один
        раз. Регистр букв не важен.
      </p>
      {loadError && <p className="mb-4 text-sm text-red-600">{loadError}</p>}

      <CodesSection codes={codes} onChanged={reload} />
      <LinksSection links={links} onChanged={reload} />

      <h2 className="mt-10 mb-3 text-base font-semibold text-slate-900">Активации</h2>
      {activations.length === 0 ? (
        <p className="text-sm text-slate-500">Пока никто ничего не активировал</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Кто</th>
                <th className="px-4 py-3 font-medium">Что</th>
                <th className="px-4 py-3 font-medium">Дней</th>
                <th className="px-4 py-3 font-medium">Когда</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {activations.map((a) => (
                <tr key={a.id}>
                  <td className="px-4 py-3">
                    <span className="font-medium text-slate-900" translate="no">
                      {a.user_login}
                    </span>
                    <span className="ml-2 text-xs tabular-nums text-slate-500">{a.user_public_id}</span>
                  </td>
                  <td className="max-w-md px-4 py-3 text-slate-700">
                    {a.promo_code_id !== null ? (
                      <span className="font-mono">{a.label}</span>
                    ) : (
                      <>
                        🎬 {a.label}
                        {a.is_first_link && (
                          <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
                            первая ссылка
                          </span>
                        )}
                      </>
                    )}
                  </td>
                  <td className="px-4 py-3 tabular-nums">+{a.days}</td>
                  <td className="px-4 py-3 text-slate-500">
                    {new Date(a.created_at).toLocaleString("ru-RU", { dateStyle: "short", timeStyle: "short" })}
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

// --- Промокоды ----------------------------------------------------------------

function CodesSection({ codes, onChanged }: { codes: PromoCode[]; onChanged: () => Promise<void> }) {
  const [editing, setEditing] = useState<PromoCode | null>(null);

  async function toggle(code: PromoCode) {
    try {
      await updatePromoCode(code.id, { enabled: !code.enabled });
      await onChanged();
    } catch (err) {
      window.alert(errorDetail(err, "Не удалось сохранить"));
    }
  }

  async function remove(code: PromoCode) {
    if (!window.confirm(`Удалить промокод ${code.code}?`)) return;
    try {
      await deletePromoCode(code.id);
      await onChanged();
    } catch (err) {
      window.alert(errorDetail(err, "Не удалось удалить"));
    }
  }

  return (
    <section>
      <h2 className="mb-3 text-base font-semibold text-slate-900">Промокоды</h2>
      <CodeForm
        key={editing?.id ?? "new"}
        editing={editing}
        onDone={async () => {
          setEditing(null);
          await onChanged();
        }}
        onCancel={() => setEditing(null)}
      />
      {codes.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Промокод</th>
                <th className="px-4 py-3 font-medium">Дней</th>
                <th className="px-4 py-3 font-medium">Активаций</th>
                <th className="px-4 py-3 font-medium">Действует до</th>
                <th className="px-4 py-3 font-medium">Статус</th>
                <th className="px-4 py-3 font-medium" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {codes.map((c) => (
                <tr key={c.id}>
                  <td className="px-4 py-3">
                    <div className="font-mono font-medium text-slate-900">{c.code}</div>
                    {c.note && <div className="text-xs text-slate-500">{c.note}</div>}
                  </td>
                  <td className="px-4 py-3 tabular-nums">{c.days}</td>
                  <td className="px-4 py-3 tabular-nums">
                    {c.activations}
                    {c.max_activations !== null && <span className="text-slate-500"> из {c.max_activations}</span>}
                  </td>
                  <td className="px-4 py-3 text-slate-600">{c.expires_at ? formatDate(c.expires_at) : "бессрочно"}</td>
                  <td className="px-4 py-3">
                    <StatusPill enabled={c.enabled} />
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right">
                    <button type="button" className={secondaryButton} onClick={() => setEditing(c)}>
                      Изменить
                    </button>
                    <button type="button" className={secondaryButton} onClick={() => toggle(c)}>
                      {c.enabled ? "Выключить" : "Включить"}
                    </button>
                    {c.activations === 0 && (
                      <button
                        type="button"
                        className="rounded-md px-3 py-2 text-sm font-medium text-red-600 hover:bg-red-50"
                        onClick={() => remove(c)}
                      >
                        Удалить
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function CodeForm({
  editing,
  onDone,
  onCancel,
}: {
  editing: PromoCode | null;
  onDone: () => Promise<void>;
  onCancel: () => void;
}) {
  const [code, setCode] = useState(editing?.code ?? "");
  const [days, setDays] = useState(editing ? String(editing.days) : "30");
  const [maxActivations, setMaxActivations] = useState(editing?.max_activations?.toString() ?? "");
  const [expiresOn, setExpiresOn] = useState(editing?.expires_at ? editing.expires_at.slice(0, 10) : "");
  const [note, setNote] = useState(editing?.note ?? "");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const daysValue = optionalPositive(days);
    const maxValue = optionalPositive(maxActivations);
    if (!code.trim()) return setError("Введите промокод");
    if (daysValue === null || daysValue === undefined) return setError("Дней — целое число больше нуля");
    if (maxValue === undefined) return setError("Лимит активаций — целое число больше нуля или пусто");

    const input = {
      code: code.trim(),
      days: daysValue,
      max_activations: maxValue,
      // The end of the chosen day in Dushanbe, the app's day boundary.
      expires_at: expiresOn ? `${expiresOn}T23:59:59+05:00` : null,
      note: note.trim() || null,
    };
    setIsSaving(true);
    try {
      if (editing) {
        await updatePromoCode(editing.id, input);
      } else {
        await createPromoCode({ ...input, enabled: true });
      }
      await onDone();
      if (!editing) {
        setCode("");
        setNote("");
      }
    } catch (err) {
      setError(errorDetail(err, "Не удалось сохранить"));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="rounded-lg border border-slate-200 bg-white p-5">
      <h3 className="mb-4 text-sm font-semibold text-slate-900">
        {editing ? `Изменить промокод ${editing.code}` : "Новый промокод"}
      </h3>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
        <div className="sm:col-span-2">
          <label className="mb-1 block text-sm font-medium text-slate-700">Промокод</label>
          <input
            className={`${inputClass} font-mono uppercase placeholder:normal-case placeholder:font-sans`}
            value={code}
            onChange={(e) => setCode(e.target.value)}
            maxLength={40}
            placeholder="например, GUYO2026"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Дней Premium</label>
          <input type="number" min={1} className={inputClass} value={days} onChange={(e) => setDays(e.target.value)} />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Лимит активаций</label>
          <input
            type="number"
            min={1}
            className={inputClass}
            value={maxActivations}
            onChange={(e) => setMaxActivations(e.target.value)}
            placeholder="без лимита"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Действует до</label>
          <input type="date" className={inputClass} value={expiresOn} onChange={(e) => setExpiresOn(e.target.value)} />
        </div>
        <div className="sm:col-span-3">
          <label className="mb-1 block text-sm font-medium text-slate-700">Заметка для себя (необязательно)</label>
          <input
            className={inputClass}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            maxLength={300}
            placeholder="например, для стрима 26.09"
          />
        </div>
      </div>
      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
      <div className="mt-4 flex gap-2">
        <button type="submit" disabled={isSaving} className={primaryButton}>
          {isSaving ? "Сохранение…" : editing ? "Сохранить" : "Создать промокод"}
        </button>
        {editing && (
          <button type="button" className={secondaryButton} onClick={onCancel}>
            Отмена
          </button>
        )}
      </div>
    </form>
  );
}

// --- Ссылки на видео ----------------------------------------------------------

function LinksSection({ links, onChanged }: { links: PromoLink[]; onChanged: () => Promise<void> }) {
  const [editing, setEditing] = useState<PromoLink | null>(null);
  const [settings, setSettings] = useState<PromoSettings | null>(null);

  useEffect(() => {
    getPromoSettings()
      .then(setSettings)
      .catch(() => undefined);
  }, []);

  async function toggle(link: PromoLink) {
    try {
      await updatePromoLink(link.id, { enabled: !link.enabled });
      await onChanged();
    } catch (err) {
      window.alert(errorDetail(err, "Не удалось сохранить"));
    }
  }

  async function remove(link: PromoLink) {
    if (!window.confirm(`Удалить ссылку ${link.title ?? link.url}?`)) return;
    try {
      await deletePromoLink(link.id);
      await onChanged();
    } catch (err) {
      window.alert(errorDetail(err, "Не удалось удалить"));
    }
  }

  return (
    <section className="mt-10">
      <h2 className="mb-1 text-base font-semibold text-slate-900">Ссылки на видео</h2>
      <p className="mb-3 max-w-2xl text-sm text-slate-500">
        Добавьте ссылку на своё видео, а в видео попросите вставить её в приложении. Первая ссылка, которую человек
        активирует (любая), даёт больше дней, каждая следующая — меньше. Разные варианты одной ссылки (youtu.be, с
        «?si=…», мобильная версия) считаются одним видео.
      </p>

      {settings && <LinkRewards settings={settings} onSaved={setSettings} />}

      <LinkForm
        key={editing?.id ?? "new"}
        editing={editing}
        repeatDays={settings?.promo_link_repeat_days}
        onDone={async () => {
          setEditing(null);
          await onChanged();
        }}
        onCancel={() => setEditing(null)}
      />

      {links.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Видео</th>
                <th className="px-4 py-3 font-medium">Повторно, дней</th>
                <th className="px-4 py-3 font-medium">Активаций</th>
                <th className="px-4 py-3 font-medium">Статус</th>
                <th className="px-4 py-3 font-medium" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {links.map((l) => (
                <tr key={l.id}>
                  <td className="max-w-md px-4 py-3">
                    {l.title && <div className="font-medium text-slate-900">{l.title}</div>}
                    <a
                      href={l.url}
                      target="_blank"
                      rel="noreferrer"
                      className="break-all text-xs text-indigo-600 hover:underline"
                    >
                      {l.url}
                    </a>
                  </td>
                  <td className="px-4 py-3 tabular-nums">
                    {l.repeat_days ?? <span className="text-slate-500">{settings?.promo_link_repeat_days ?? "—"} (общее)</span>}
                  </td>
                  <td className="px-4 py-3 tabular-nums">{l.activations}</td>
                  <td className="px-4 py-3">
                    <StatusPill enabled={l.enabled} />
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right">
                    <button type="button" className={secondaryButton} onClick={() => setEditing(l)}>
                      Изменить
                    </button>
                    <button type="button" className={secondaryButton} onClick={() => toggle(l)}>
                      {l.enabled ? "Выключить" : "Включить"}
                    </button>
                    {l.activations === 0 && (
                      <button
                        type="button"
                        className="rounded-md px-3 py-2 text-sm font-medium text-red-600 hover:bg-red-50"
                        onClick={() => remove(l)}
                      >
                        Удалить
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function LinkRewards({ settings, onSaved }: { settings: PromoSettings; onSaved: (s: PromoSettings) => void }) {
  const [first, setFirst] = useState(String(settings.promo_link_first_days));
  const [repeat, setRepeat] = useState(String(settings.promo_link_repeat_days));
  const [isSaving, setIsSaving] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const firstValue = optionalPositive(first);
    const repeatValue = optionalPositive(repeat);
    if (!firstValue || !repeatValue) {
      setMessage({ ok: false, text: "Оба значения — целые числа больше нуля" });
      return;
    }
    setIsSaving(true);
    try {
      onSaved(await updatePromoSettings({ promo_link_first_days: firstValue, promo_link_repeat_days: repeatValue }));
      setMessage({ ok: true, text: "Сохранено" });
    } catch (err) {
      setMessage({ ok: false, text: errorDetail(err, "Не удалось сохранить") });
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-4 rounded-lg border border-slate-200 bg-white p-5">
      <h3 className="mb-4 text-sm font-semibold text-slate-900">Награда за ссылки</h3>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Первая ссылка, дней</label>
          <input type="number" min={1} className={inputClass} value={first} onChange={(e) => setFirst(e.target.value)} />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Каждая следующая, дней</label>
          <input type="number" min={1} className={inputClass} value={repeat} onChange={(e) => setRepeat(e.target.value)} />
          <p className="mt-1 text-xs text-slate-500">Если у ссылки не указано своё значение</p>
        </div>
      </div>
      {message && <p className={`mt-3 text-sm ${message.ok ? "text-emerald-700" : "text-red-600"}`}>{message.text}</p>}
      <button type="submit" disabled={isSaving} className={`mt-4 ${primaryButton}`}>
        {isSaving ? "Сохранение…" : "Сохранить"}
      </button>
    </form>
  );
}

function LinkForm({
  editing,
  repeatDays,
  onDone,
  onCancel,
}: {
  editing: PromoLink | null;
  repeatDays: number | undefined;
  onDone: () => Promise<void>;
  onCancel: () => void;
}) {
  const [url, setUrl] = useState(editing?.url ?? "");
  const [title, setTitle] = useState(editing?.title ?? "");
  const [ownDays, setOwnDays] = useState(editing?.repeat_days?.toString() ?? "");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const daysValue = optionalPositive(ownDays);
    if (!url.trim()) return setError("Вставьте ссылку");
    if (daysValue === undefined) return setError("Дней — целое число больше нуля или пусто");

    const input = { url: url.trim(), title: title.trim() || null, repeat_days: daysValue };
    setIsSaving(true);
    try {
      if (editing) {
        await updatePromoLink(editing.id, input);
      } else {
        await createPromoLink({ ...input, enabled: true });
      }
      await onDone();
      if (!editing) {
        setUrl("");
        setTitle("");
        setOwnDays("");
      }
    } catch (err) {
      setError(errorDetail(err, "Не удалось сохранить"));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="rounded-lg border border-slate-200 bg-white p-5">
      <h3 className="mb-4 text-sm font-semibold text-slate-900">{editing ? "Изменить ссылку" : "Новая ссылка"}</h3>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
        <div className="sm:col-span-2">
          <label className="mb-1 block text-sm font-medium text-slate-700">Ссылка на видео</label>
          <input
            className={inputClass}
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            maxLength={1000}
            placeholder="https://youtu.be/…"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Название (необязательно)</label>
          <input
            className={inputClass}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={200}
            placeholder="например, Урок 5"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Повторно, дней</label>
          <input
            type="number"
            min={1}
            className={inputClass}
            value={ownDays}
            onChange={(e) => setOwnDays(e.target.value)}
            placeholder={repeatDays ? `общее: ${repeatDays}` : "общее"}
          />
        </div>
      </div>
      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
      <div className="mt-4 flex gap-2">
        <button type="submit" disabled={isSaving} className={primaryButton}>
          {isSaving ? "Сохранение…" : editing ? "Сохранить" : "Добавить ссылку"}
        </button>
        {editing && (
          <button type="button" className={secondaryButton} onClick={onCancel}>
            Отмена
          </button>
        )}
      </div>
    </form>
  );
}

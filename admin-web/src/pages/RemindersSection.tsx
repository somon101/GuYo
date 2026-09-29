import axios from "axios";
import { useEffect, useState } from "react";
import { createReminder, deleteReminder, getReminders, updateReminder, updateReminderSettings } from "../api/endpoints";
import { InfoTooltip } from "../components/InfoTooltip";
import type { ReminderKind, ReminderRule, ReminderRuleInput, ReminderSettings } from "../types";

const GROUPS: {
  kind: ReminderKind;
  title: string;
  help: string;
  daysLabel: string;
  newDays: number;
  hourSetting?: keyof ReminderSettings;
  hourLabel?: string;
}[] = [
  {
    kind: "inactivity",
    title: "Если человек не заходит",
    help: "Приходит, когда человек пропустил ровно столько дней подряд (1 — пропустил вчерашний день). Отправляется в час, когда он обычно занимается.",
    daysLabel: "Пропущено дней",
    newDays: 14,
    hourSetting: "default_hour",
    hourLabel: "Если неизвестно, когда человек обычно занимается, отправлять в",
  },
  {
    kind: "streak_risk",
    title: "Серия под угрозой",
    help: "Приходит вечером тому, кто занимался вчера, но ещё не открывал приложение сегодня. Число дней — с какой длины серии предупреждать.",
    daysLabel: "От длины серии",
    newDays: 2,
    hourSetting: "streak_risk_hour",
    hourLabel: "Отправлять в",
  },
  {
    kind: "streak_milestone",
    title: "Поздравления с серией",
    help: "Приходит в тот день, когда серия человека достигает указанного числа дней.",
    daysLabel: "День серии",
    newDays: 50,
  },
];

const HOURS = Array.from({ length: 24 }, (_, h) => h);

function errorText(err: unknown, fallback: string): string {
  const detail = axios.isAxiosError(err) ? err.response?.data?.detail : undefined;
  return typeof detail === "string" ? detail : fallback;
}

/** «Напоминания»: the automatic messages the backend sends by itself
 * (app/notifications/reminders.py). Each goes out as a push and into the
 * app's inbox, like a hand-written message. */
export function RemindersSection() {
  const [rules, setRules] = useState<ReminderRule[]>([]);
  const [settings, setSettings] = useState<ReminderSettings | null>(null);
  const [drafts, setDrafts] = useState<{ key: number; kind: ReminderKind }[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [settingsStatus, setSettingsStatus] = useState<string | null>(null);

  useEffect(() => {
    getReminders()
      .then((data) => {
        setRules(data.rules);
        setSettings(data.settings);
      })
      .catch(() => setLoadError("Не удалось загрузить напоминания"));
  }, []);

  async function changeHour(key: keyof ReminderSettings, hour: number) {
    if (!settings) return;
    const next = { ...settings, [key]: hour };
    setSettings(next);
    setSettingsStatus(null);
    try {
      await updateReminderSettings(next);
      setSettingsStatus("Время сохранено");
    } catch (err) {
      setSettingsStatus(errorText(err, "Не удалось сохранить время"));
    }
  }

  if (loadError) return <p className="mt-8 text-sm text-red-600">{loadError}</p>;
  if (!settings) return <p className="mt-8 text-sm text-slate-500">Загрузка напоминаний…</p>;

  return (
    <section className="mt-8">
      <h2 className="text-lg font-semibold text-slate-900">Напоминания</h2>
      <p className="mb-4 mt-1 max-w-2xl text-sm text-slate-500">
        Отправляются автоматически: push на телефон и сообщение в разделе «Уведомления» в приложении. Если на один срок
        добавлено несколько текстов, человеку придёт случайный из них. <code>{"{дни}"}</code> в тексте заменяется числом
        дней, <code>{"{дни+1}"}</code> — числом на один больше.
      </p>
      {settingsStatus && <p className="mb-3 text-sm text-slate-500">{settingsStatus}</p>}

      <div className="flex flex-col gap-4">
        {GROUPS.map((group) => {
          const groupRules = rules
            .filter((r) => r.kind === group.kind)
            .sort((a, b) => a.days - b.days || a.id - b.id);
          const groupDrafts = drafts.filter((d) => d.kind === group.kind);
          const hourSetting = group.hourSetting;
          return (
            <div key={group.kind} className="card p-5">
              <div className="mb-3 flex items-center gap-1.5">
                <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">{group.title}</h3>
                <InfoTooltip>{group.help}</InfoTooltip>
              </div>

              {hourSetting && (
                <label className="mb-4 flex flex-wrap items-center gap-2 text-sm text-slate-700">
                  {group.hourLabel}
                  <select
                    className="field px-2 py-1 text-sm"
                    value={settings[hourSetting]}
                    onChange={(e) => changeHour(hourSetting, Number(e.target.value))}
                  >
                    {HOURS.map((h) => (
                      <option key={h} value={h}>
                        {String(h).padStart(2, "0")}:00
                      </option>
                    ))}
                  </select>
                  по Душанбе
                </label>
              )}

              <div className="flex flex-col divide-y divide-[var(--separator)]">
                {groupRules.map((rule) => (
                  <RuleRow
                    key={rule.id}
                    kind={group.kind}
                    daysLabel={group.daysLabel}
                    rule={rule}
                    onSaved={(saved) => setRules((prev) => prev.map((r) => (r.id === saved.id ? saved : r)))}
                    onDeleted={() => setRules((prev) => prev.filter((r) => r.id !== rule.id))}
                  />
                ))}
                {groupDrafts.map((draft) => (
                  <RuleRow
                    key={`draft-${draft.key}`}
                    kind={group.kind}
                    daysLabel={group.daysLabel}
                    initialDays={group.newDays}
                    onSaved={(saved) => {
                      setRules((prev) => [...prev, saved]);
                      setDrafts((prev) => prev.filter((d) => d.key !== draft.key));
                    }}
                    onDeleted={() => setDrafts((prev) => prev.filter((d) => d.key !== draft.key))}
                  />
                ))}
              </div>
              {groupRules.length === 0 && groupDrafts.length === 0 && (
                <p className="text-sm text-slate-500">Нет ни одного текста — такие напоминания не отправляются.</p>
              )}

              <button
                type="button"
                onClick={() => setDrafts((prev) => [...prev, { key: Date.now(), kind: group.kind }])}
                className="btn-tinted mt-3 rounded-md px-3 py-1.5 text-sm font-medium"
              >
                + Добавить текст
              </button>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function RuleRow({
  kind,
  daysLabel,
  rule,
  initialDays = 1,
  onSaved,
  onDeleted,
}: {
  kind: ReminderKind;
  daysLabel: string;
  rule?: ReminderRule;
  initialDays?: number;
  onSaved: (rule: ReminderRule) => void;
  onDeleted: () => void;
}) {
  const [days, setDays] = useState(String(rule?.days ?? initialDays));
  const [title, setTitle] = useState(rule?.title ?? "");
  const [body, setBody] = useState(rule?.body ?? "");
  const [enabled, setEnabled] = useState(rule?.enabled ?? true);
  const [isBusy, setIsBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isDirty =
    !rule ||
    String(rule.days) !== days ||
    (rule.title ?? "") !== title ||
    rule.body !== body ||
    rule.enabled !== enabled;

  async function save() {
    const daysNumber = Number(days);
    if (!Number.isInteger(daysNumber) || daysNumber < 1) {
      setError("Число дней — целое, от 1");
      return;
    }
    if (!body.trim()) {
      setError("Введите текст");
      return;
    }
    const input: ReminderRuleInput = { kind, days: daysNumber, title: title.trim() || null, body: body.trim(), enabled };
    setIsBusy(true);
    setError(null);
    try {
      onSaved(rule ? await updateReminder(rule.id, input) : await createReminder(input));
    } catch (err) {
      setError(errorText(err, "Не удалось сохранить"));
    } finally {
      setIsBusy(false);
    }
  }

  async function remove() {
    if (!rule) {
      onDeleted();
      return;
    }
    if (!window.confirm("Удалить этот текст напоминания?")) return;
    setIsBusy(true);
    try {
      await deleteReminder(rule.id);
      onDeleted();
    } catch (err) {
      setError(errorText(err, "Не удалось удалить"));
      setIsBusy(false);
    }
  }

  return (
    <div className="grid grid-cols-1 gap-3 py-3 first:pt-0 sm:grid-cols-[110px_1fr]">
      <div>
        <label className="mb-1 block text-xs text-slate-500">{daysLabel}</label>
        <input
          type="number"
          min={1}
          className="w-full field px-3 py-2 text-sm"
          value={days}
          onChange={(e) => setDays(e.target.value)}
        />
      </div>
      <div className="flex flex-col gap-2">
        <input
          className="w-full field px-3 py-2 text-sm"
          placeholder="Заголовок (необязательно)"
          value={title}
          maxLength={120}
          onChange={(e) => setTitle(e.target.value)}
        />
        <textarea
          className="w-full field px-3 py-2 text-sm"
          rows={2}
          placeholder="Текст напоминания"
          value={body}
          maxLength={1000}
          onChange={(e) => setBody(e.target.value)}
        />
        <div className="flex flex-wrap items-center gap-3">
          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" className="switch" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
            Включено
          </label>
          <div className="ml-auto flex gap-2">
            <button
              type="button"
              onClick={remove}
              disabled={isBusy}
              className="rounded-md px-3 py-1.5 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
            >
              {rule ? "Удалить" : "Отмена"}
            </button>
            <button
              type="button"
              onClick={save}
              disabled={isBusy || !isDirty}
              className="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
            >
              {isBusy ? "…" : "Сохранить"}
            </button>
          </div>
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
      </div>
    </div>
  );
}

import axios from "axios";
import { useEffect, useState } from "react";
import {
  applyPassTemplate,
  copyPassTemplate,
  createPassTemplate,
  deletePassTemplate,
  ensureMonthlySeasons,
  getDefaultPassDefinition,
  getPassSettings,
  getSeasonPassDef,
  listPassTemplates,
  listSeasons,
  makePassTemplateDefault,
  updatePassSettings,
  updatePassTemplate,
  updateSeasonPassDef,
  type PassDefinition,
  type PassLevelDef,
  type PassReward,
  type PassSettings,
  type PassTaskDef,
  type PassTemplate,
} from "../api/endpoints";
import type { Season } from "../types";

const inputClass = "field px-2 py-1.5 text-sm";

const REWARD_LABELS: Record<string, string> = {
  rating_points: "Очки рейтинга",
  premium_days: "Дни Premium",
  streak_freeze: "Заморозка серии",
};
const METRIC_LABELS: Record<string, string> = {
  word: "Выучить слов",
  lesson: "Пройти уроков",
  review: "Ответов в «Повторить сегодня»",
  quest: "Выполнить квестов",
  streak: "Дней серии",
};
const STATUS_LABELS: Record<string, string> = { active: "идёт", scheduled: "запланирован", completed: "завершён" };

function errorText(e: unknown, fallback: string): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return fallback;
}

/** «Пропуск сезона»: how much XP each action gives, the level ladders (templates,
 * any number, one is the default) and the copy each season carries. */
export function SeasonPassPage() {
  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">Пропуск сезона</h1>
      <p className="mb-6 text-sm text-slate-500">
        За занятия человек получает опыт (XP) и открывает уровни: на каждом свои награды, бесплатная и для Premium.
        Каждую неделю есть задания на бонусный XP. Сезоны идут по календарным месяцам и создаются сами; у каждого
        своя копия шаблона, поэтому правка шаблона не меняет идущий сезон.
      </p>
      <SettingsSection />
      <TemplatesSection />
      <SeasonsSection />
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-8">
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h2>
      {children}
    </section>
  );
}

// --- XP ----------------------------------------------------------------------

function SettingsSection() {
  const [s, setS] = useState<PassSettings | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    getPassSettings()
      .then(setS)
      .catch(() => setMessage("Не удалось загрузить"));
  }, []);

  if (!s) return <Section title="Опыт (XP)">{message && <p className="text-sm text-red-600">{message}</p>}</Section>;

  const fields: { key: keyof PassSettings; label: string }[] = [
    { key: "xp_word", label: "За изученное слово" },
    { key: "xp_lesson", label: "За пройденный урок" },
    { key: "xp_review", label: "За слово в «Повторить сегодня»" },
    { key: "xp_quest", label: "За выполненное задание квеста" },
    { key: "xp_streak", label: "За день серии" },
    { key: "freeze_cap", label: "Больше заморозок серии у человека не бывает" },
  ];

  async function save() {
    if (!s) return;
    setMessage(null);
    try {
      setS(await updatePassSettings(s));
      setMessage("Сохранено");
    } catch (e) {
      setMessage(errorText(e, "Не удалось сохранить"));
    }
  }

  return (
    <Section title="Опыт (XP)">
      <div className="card flex flex-col gap-3 p-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {fields.map((f) => (
            <label key={f.key} className="flex items-center justify-between gap-3 text-sm text-slate-700">
              {f.label}
              <input
                type="number"
                min={0}
                className={`${inputClass} w-24`}
                value={s[f.key] as number}
                onChange={(e) => setS({ ...s, [f.key]: Math.max(0, Number(e.target.value) || 0) })}
              />
            </label>
          ))}
        </div>
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            checked={s.auto_monthly_seasons}
            onChange={(e) => setS({ ...s, auto_monthly_seasons: e.target.checked })}
          />
          Создавать сезоны сами, по одному на календарный месяц (текущий и следующий)
        </label>
        <div className="flex items-center gap-3">
          <button onClick={save} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
            Сохранить
          </button>
          {message && <span className="text-sm text-slate-500">{message}</span>}
        </div>
      </div>
    </Section>
  );
}

// --- Definition editor -----------------------------------------------------------

function RewardEditor({ value, onChange }: { value: PassReward | null; onChange: (v: PassReward | null) => void }) {
  return (
    <div className="flex items-center gap-1">
      <select
        className={`${inputClass} w-36`}
        value={value?.type ?? ""}
        onChange={(e) =>
          onChange(e.target.value ? { type: e.target.value as PassReward["type"], amount: value?.amount ?? 1 } : null)
        }
      >
        <option value="">— нет —</option>
        {Object.entries(REWARD_LABELS).map(([k, v]) => (
          <option key={k} value={k}>
            {v}
          </option>
        ))}
      </select>
      {value && (
        <input
          type="number"
          min={1}
          className={`${inputClass} w-16`}
          value={value.amount}
          onChange={(e) => onChange({ ...value, amount: Math.max(1, Number(e.target.value) || 1) })}
        />
      )}
    </div>
  );
}

function renumber(levels: PassLevelDef[]): PassLevelDef[] {
  return levels.map((l, i) => ({ ...l, level: i + 1 }));
}

function DefinitionEditor({
  value,
  onChange,
}: {
  value: PassDefinition;
  onChange: (v: PassDefinition) => void;
}) {
  const setLevel = (i: number, patch: Partial<PassLevelDef>) =>
    onChange({ ...value, levels: value.levels.map((l, j) => (j === i ? { ...l, ...patch } : l)) });
  const setTask = (i: number, patch: Partial<PassTaskDef>) =>
    onChange({ ...value, tasks: value.tasks.map((t, j) => (j === i ? { ...t, ...patch } : t)) });

  return (
    <div className="flex flex-col gap-5">
      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Уровни</p>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-1 py-1 font-medium">№</th>
                <th className="px-1 py-1 font-medium">XP на уровень</th>
                <th className="px-1 py-1 font-medium">Бесплатная награда</th>
                <th className="px-1 py-1 font-medium">Награда Premium</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {value.levels.map((l, i) => (
                <tr key={i} className="border-t border-slate-100">
                  <td className="px-1 py-1 text-slate-500">{l.level}</td>
                  <td className="px-1 py-1">
                    <input
                      type="number"
                      min={1}
                      className={`${inputClass} w-20`}
                      value={l.xp}
                      onChange={(e) => setLevel(i, { xp: Math.max(1, Number(e.target.value) || 1) })}
                    />
                  </td>
                  <td className="px-1 py-1">
                    <RewardEditor value={l.free} onChange={(v) => setLevel(i, { free: v })} />
                  </td>
                  <td className="px-1 py-1">
                    <RewardEditor value={l.premium} onChange={(v) => setLevel(i, { premium: v })} />
                  </td>
                  <td className="px-1 py-1">
                    <button
                      className="text-xs text-red-600 hover:underline"
                      onClick={() => onChange({ ...value, levels: renumber(value.levels.filter((_, j) => j !== i)) })}
                    >
                      убрать
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <button
          className="mt-2 text-sm font-medium text-indigo-600 hover:text-indigo-700"
          onClick={() =>
            onChange({
              ...value,
              levels: renumber([
                ...value.levels,
                { level: 0, xp: value.levels[value.levels.length - 1]?.xp ?? 80, free: { type: "rating_points", amount: 20 }, premium: null },
              ]),
            })
          }
        >
          + Добавить уровень
        </button>
      </div>

      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">
          Недельные задания (прогресс каждую неделю начинается заново)
        </p>
        {value.tasks.map((t, i) => (
          <div key={i} className="mb-2 flex flex-wrap items-center gap-2 text-sm">
            <select className={`${inputClass} w-56`} value={t.metric} onChange={(e) => setTask(i, { metric: e.target.value as PassTaskDef["metric"] })}>
              {Object.entries(METRIC_LABELS).map(([k, v]) => (
                <option key={k} value={k}>
                  {v}
                </option>
              ))}
            </select>
            <label className="flex items-center gap-1 text-slate-600">
              цель
              <input type="number" min={1} className={`${inputClass} w-16`} value={t.target} onChange={(e) => setTask(i, { target: Math.max(1, Number(e.target.value) || 1) })} />
            </label>
            <label className="flex items-center gap-1 text-slate-600">
              бонус XP
              <input type="number" min={0} className={`${inputClass} w-16`} value={t.xp} onChange={(e) => setTask(i, { xp: Math.max(0, Number(e.target.value) || 0) })} />
            </label>
            <button className="text-xs text-red-600 hover:underline" onClick={() => onChange({ ...value, tasks: value.tasks.filter((_, j) => j !== i) })}>
              убрать
            </button>
          </div>
        ))}
        <button
          className="text-sm font-medium text-indigo-600 hover:text-indigo-700"
          onClick={() => {
            const n = value.tasks.length + 1;
            onChange({ ...value, tasks: [...value.tasks, { id: `task${Date.now() % 100000}_${n}`, metric: "word", target: 5, xp: 50 }] });
          }}
        >
          + Добавить задание
        </button>
      </div>
    </div>
  );
}

// --- Templates ----------------------------------------------------------------------

function TemplatesSection() {
  const [templates, setTemplates] = useState<PassTemplate[]>([]);
  const [editing, setEditing] = useState<{ id: number | null; name: string; definition: PassDefinition } | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function reload() {
    try {
      setTemplates(await listPassTemplates());
    } catch {
      setMessage("Не удалось загрузить шаблоны");
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function run(action: () => Promise<unknown>) {
    setMessage(null);
    try {
      await action();
      await reload();
    } catch (e) {
      setMessage(errorText(e, "Не удалось выполнить"));
    }
  }

  async function startNew() {
    try {
      setEditing({ id: null, name: "Новый шаблон", definition: await getDefaultPassDefinition() });
    } catch {
      setMessage("Не удалось загрузить заготовку");
    }
  }

  async function save() {
    if (!editing) return;
    await run(async () => {
      if (editing.id == null) await createPassTemplate(editing.name, editing.definition);
      else await updatePassTemplate(editing.id, editing.name, editing.definition);
      setEditing(null);
    });
  }

  return (
    <Section title="Шаблоны">
      {message && <p className="mb-2 text-sm text-red-600">{message}</p>}
      <div className="flex flex-col gap-2">
        {templates.map((t) => (
          <div key={t.id} className="card flex flex-wrap items-center gap-3 p-3">
            <div className="min-w-0 flex-1">
              <span className="font-medium text-slate-900">{t.name}</span>
              {t.is_default && <span className="ml-2 rounded-full bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-700">по умолчанию</span>}
              <p className="text-xs text-slate-500">
                {t.definition.levels.length} уровней, {t.definition.tasks.length} заданий
              </p>
            </div>
            <button className="text-sm font-medium text-indigo-600" onClick={() => setEditing({ id: t.id, name: t.name, definition: t.definition })}>
              Изменить
            </button>
            <button className="text-sm font-medium text-indigo-600" onClick={() => run(() => copyPassTemplate(t.id))}>
              Копировать
            </button>
            {!t.is_default && (
              <>
                <button className="text-sm font-medium text-indigo-600" onClick={() => run(() => makePassTemplateDefault(t.id))}>
                  Сделать основным
                </button>
                <button
                  className="text-sm font-medium text-red-600"
                  onClick={() => window.confirm(`Удалить шаблон «${t.name}»?`) && run(() => deletePassTemplate(t.id))}
                >
                  Удалить
                </button>
              </>
            )}
          </div>
        ))}
      </div>
      <button onClick={startNew} className="mt-3 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
        Создать шаблон
      </button>

      {editing && (
        <div className="card mt-4 flex flex-col gap-4 p-4">
          <input className={`${inputClass} max-w-md`} value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
          <DefinitionEditor value={editing.definition} onChange={(definition) => setEditing({ ...editing, definition })} />
          <div className="flex gap-3">
            <button onClick={save} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
              Сохранить шаблон
            </button>
            <button onClick={() => setEditing(null)} className="text-sm text-slate-500">
              Отмена
            </button>
          </div>
        </div>
      )}
    </Section>
  );
}

// --- Seasons ------------------------------------------------------------------------------

function SeasonsSection() {
  const [seasons, setSeasons] = useState<Season[]>([]);
  const [templates, setTemplates] = useState<PassTemplate[]>([]);
  const [pick, setPick] = useState<Record<number, number>>({});
  const [editing, setEditing] = useState<{ seasonId: number; name: string; definition: PassDefinition } | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function reload() {
    try {
      const [s, t] = await Promise.all([listSeasons(), listPassTemplates()]);
      setSeasons(s.filter((x) => x.status !== "completed"));
      setTemplates(t);
    } catch {
      setMessage("Не удалось загрузить сезоны");
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function edit(seasonId: number, name: string) {
    try {
      const sp = await getSeasonPassDef(seasonId);
      setEditing({ seasonId, name, definition: sp.definition });
    } catch (e) {
      setMessage(errorText(e, "Не удалось открыть пропуск сезона"));
    }
  }

  async function saveEditing() {
    if (!editing) return;
    try {
      await updateSeasonPassDef(editing.seasonId, editing.definition);
      setEditing(null);
      setMessage("Сохранено");
    } catch (e) {
      setMessage(errorText(e, "Не удалось сохранить"));
    }
  }

  async function apply(seasonId: number) {
    const templateId = pick[seasonId] ?? templates.find((t) => t.is_default)?.id;
    if (templateId == null) return;
    if (!window.confirm("Заменить пропуск этого сезона копией выбранного шаблона?")) return;
    try {
      await applyPassTemplate(seasonId, templateId);
      setMessage("Шаблон применён");
    } catch (e) {
      setMessage(errorText(e, "Не удалось применить"));
    }
  }

  return (
    <Section title="Сезоны">
      {message && <p className="mb-2 text-sm text-slate-500">{message}</p>}
      <div className="flex flex-col gap-2">
        {seasons.map((s) => (
          <div key={s.id} className="card flex flex-wrap items-center gap-3 p-3">
            <div className="min-w-0 flex-1">
              <span className="font-medium text-slate-900">{s.name}</span>
              <span className="ml-2 text-xs text-slate-500">{STATUS_LABELS[s.status] ?? s.status}</span>
            </div>
            <select
              className={`${inputClass} w-44`}
              value={pick[s.id] ?? templates.find((t) => t.is_default)?.id ?? ""}
              onChange={(e) => setPick({ ...pick, [s.id]: Number(e.target.value) })}
            >
              {templates.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </select>
            <button className="text-sm font-medium text-indigo-600" onClick={() => apply(s.id)}>
              Применить шаблон
            </button>
            <button className="text-sm font-medium text-indigo-600" onClick={() => edit(s.id, s.name)}>
              Изменить пропуск
            </button>
          </div>
        ))}
        {seasons.length === 0 && <p className="text-sm text-slate-500">Сезонов пока нет.</p>}
      </div>
      <button
        className="mt-3 text-sm font-medium text-indigo-600 hover:text-indigo-700"
        onClick={async () => {
          try {
            const r = await ensureMonthlySeasons();
            setMessage(r.created ? `Создано сезонов: ${r.created}` : "Нужные сезоны уже есть");
            reload();
          } catch (e) {
            setMessage(errorText(e, "Не удалось создать"));
          }
        }}
      >
        Создать недостающие месячные сезоны сейчас
      </button>

      {editing && (
        <div className="card mt-4 flex flex-col gap-4 p-4">
          <p className="text-sm font-semibold text-slate-900">Пропуск сезона «{editing.name}»</p>
          <p className="text-xs text-slate-400">
            Это копия только этого сезона. Уже полученные награды остаются; если убрать или поменять уровни, у людей
            они пересчитаются по новым правилам.
          </p>
          <DefinitionEditor value={editing.definition} onChange={(definition) => setEditing({ ...editing, definition })} />
          <div className="flex gap-3">
            <button onClick={saveEditing} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
              Сохранить
            </button>
            <button onClick={() => setEditing(null)} className="text-sm text-slate-500">
              Отмена
            </button>
          </div>
        </div>
      )}
    </Section>
  );
}

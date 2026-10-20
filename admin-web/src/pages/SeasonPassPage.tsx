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
  listTeams,
  type AdminTeam,
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
  type PassTeamGoalDef,
  type PassTemplate,
} from "../api/endpoints";
import type { Season } from "../types";

const inputClass = "field px-2 py-1.5 text-sm";

const REWARD_LABELS: Record<string, string> = {
  rating_points: "Очки рейтинга",
  premium_days: "Дни Premium",
  streak_freeze: "Заморозка серии",
  badge: "Значок",
  title: "Титул",
};
const BADGE_LOOKS: Record<string, string> = {
  crown: "Корона",
  champion: "Кубок",
  medal: "Медаль",
  flame: "Огонь",
  star: "Звезда",
  diamond: "Бриллиант",
  rocket: "Ракета",
  shield: "Щит",
  bolt: "Молния",
  heart: "Сердце",
  leaf: "Лист",
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
      <TeamsSection />
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
    { key: "xp_daily_goal", label: "За цель дня" },
    { key: "xp_comeback", label: "За возвращение (после 3+ дней)" },
    { key: "freeze_cap", label: "Больше заморозок серии у человека не бывает" },
    { key: "team_size", label: "Больше людей в одной команде не бывает" },
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
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            checked={s.reminders_enabled}
            onChange={(e) => setS({ ...s, reminders_enabled: e.target.checked })}
          />
          Напоминать про пропуск: награда ждёт, сезон заканчивается, цель команды близко
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
  const isCosmetic = value?.type === "badge" || value?.type === "title";
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-1">
        <select
          className={`${inputClass} w-36`}
          value={value?.type ?? ""}
          onChange={(e) => {
            const type = e.target.value as PassReward["type"] | "";
            if (!type) return onChange(null);
            if (type === "badge") return onChange({ type, amount: 1, key: "crown", text: "" });
            if (type === "title") return onChange({ type, amount: 1, text: "" });
            onChange({ type, amount: value && !isCosmetic ? value.amount : 1 });
          }}
        >
          <option value="">— нет —</option>
          {Object.entries(REWARD_LABELS).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </select>
        {value && !isCosmetic && (
          <input
            type="number"
            min={1}
            className={`${inputClass} w-16`}
            value={value.amount}
            onChange={(e) => onChange({ ...value, amount: Math.max(1, Number(e.target.value) || 1) })}
          />
        )}
        {value?.type === "badge" && (
          <select className={`${inputClass} w-28`} value={value.key ?? "crown"} onChange={(e) => onChange({ ...value, key: e.target.value })}>
            {Object.entries(BADGE_LOOKS).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        )}
      </div>
      {value && isCosmetic && (
        <div className="flex flex-col gap-1">
          <input
            className={`${inputClass} w-64`}
            placeholder="Название (по-русски)"
            value={value.text ?? ""}
            onChange={(e) => onChange({ ...value, text: e.target.value })}
          />
          <div className="flex gap-1">
            <input
              className={`${inputClass} w-32`}
              placeholder="Тоҷикӣ"
              value={value.text_tg ?? ""}
              onChange={(e) => onChange({ ...value, text_tg: e.target.value })}
            />
            <input
              className={`${inputClass} w-32`}
              placeholder="Oʻzbekcha"
              value={value.text_uz ?? ""}
              onChange={(e) => onChange({ ...value, text_uz: e.target.value })}
            />
          </div>
        </div>
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

      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">
          Командные цели недели (цель = число на человека × число людей в команде)
        </p>
        {(value.team_goals ?? []).map((g, i) => (
          <TeamGoalRow
            key={i}
            goal={g}
            onChange={(ng) => onChange({ ...value, team_goals: (value.team_goals ?? []).map((x, j) => (j === i ? ng : x)) })}
            onRemove={() => onChange({ ...value, team_goals: (value.team_goals ?? []).filter((_, j) => j !== i) })}
          />
        ))}
        <button
          className="text-sm font-medium text-indigo-600 hover:text-indigo-700"
          onClick={() =>
            onChange({
              ...value,
              team_goals: [
                ...(value.team_goals ?? []),
                { id: `tg${Date.now() % 100000}`, metric: "word", target_per_member: 5, xp: 60, reward: null },
              ],
            })
          }
        >
          + Добавить командную цель недели
        </button>
      </div>

      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Командная цель сезона</p>
        {value.team_season_goal ? (
          <TeamGoalRow
            goal={value.team_season_goal}
            onChange={(ng) => onChange({ ...value, team_season_goal: ng })}
            onRemove={() => onChange({ ...value, team_season_goal: null })}
          />
        ) : (
          <button
            className="text-sm font-medium text-indigo-600 hover:text-indigo-700"
            onClick={() =>
              onChange({
                ...value,
                team_season_goal: { id: "season", metric: "word", target_per_member: 40, xp: 300, reward: null },
              })
            }
          >
            + Добавить цель сезона
          </button>
        )}
      </div>
    </div>
  );
}

function TeamGoalRow({
  goal,
  onChange,
  onRemove,
}: {
  goal: PassTeamGoalDef;
  onChange: (g: PassTeamGoalDef) => void;
  onRemove: () => void;
}) {
  return (
    <div className="mb-3 flex flex-wrap items-start gap-2 rounded-lg border border-slate-100 p-2 text-sm">
      <select className={`${inputClass} w-56`} value={goal.metric} onChange={(e) => onChange({ ...goal, metric: e.target.value as PassTeamGoalDef["metric"] })}>
        {Object.entries(METRIC_LABELS).map(([k, v]) => (
          <option key={k} value={k}>
            {v}
          </option>
        ))}
      </select>
      <label className="flex items-center gap-1 text-slate-600">
        на человека
        <input type="number" min={1} className={`${inputClass} w-16`} value={goal.target_per_member} onChange={(e) => onChange({ ...goal, target_per_member: Math.max(1, Number(e.target.value) || 1) })} />
      </label>
      <label className="flex items-center gap-1 text-slate-600">
        XP каждому
        <input type="number" min={0} className={`${inputClass} w-16`} value={goal.xp} onChange={(e) => onChange({ ...goal, xp: Math.max(0, Number(e.target.value) || 0) })} />
      </label>
      <div className="flex items-center gap-1 text-slate-600">
        награда
        <RewardEditor value={goal.reward ?? null} onChange={(r) => onChange({ ...goal, reward: r })} />
      </div>
      <button className="text-xs text-red-600 hover:underline" onClick={onRemove}>
        убрать
      </button>
    </div>
  );
}

// --- Teams (read only) ----------------------------------------------------------

function TeamsSection() {
  const [teams, setTeams] = useState<AdminTeam[] | null>(null);

  useEffect(() => {
    listTeams()
      .then(setTeams)
      .catch(() => setTeams([]));
  }, []);

  return (
    <Section title="Команды">
      {teams === null ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : teams.length === 0 ? (
        <p className="text-sm text-slate-500">Команд пока нет.</p>
      ) : (
        <div className="flex flex-col gap-2">
          {teams.map((t) => (
            <div key={t.id} className="card p-3">
              <span className="font-medium text-slate-900">{t.name}</span>
              <span className="ml-2 text-xs text-slate-500">{t.is_open ? "открыта" : "по приглашению"}</span>
              <p className="text-xs text-slate-500">{t.members.join(", ")}</p>
            </div>
          ))}
        </div>
      )}
    </Section>
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

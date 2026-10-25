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
  type PassEconomy,
  getPassEconomy,
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
  rating_points: "Звёзды рейтинга",
  premium_days: "Дни Premium",
  streak_freeze: "Заморозка серии",
  diamonds: "Бриллианты (подарок)",
  chest: "Сундук",
  booster: "Удвоитель ×2",
  badge: "Значок",
  title: "Титул",
  frame: "Рамка аватара",
};
const CHEST_NAMES: Record<string, string> = { wood: "Деревянный", silver: "Серебряный", purple: "Фиолетовый", gold: "Золотой" };
const FRAME_LOOKS: Record<string, string> = {
  gold: "Золото",
  aurora: "Северное сияние",
  fire: "Огонь",
  ocean: "Океан",
  emerald: "Изумруд",
  royal: "Королевская",
  rose: "Роза",
  ice: "Лёд",
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

/** «Пропуск сезона»: how much energy each action gives, the level ladders (templates,
 * any number, one is the default) and the copy each season carries. */
export function SeasonPassPage() {
  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">Пропуск сезона</h1>
      <p className="mb-6 text-sm text-slate-500">
        За занятия человек получает энергию и открывает уровни: на каждом свои награды, бесплатная и для Premium.
        Каждую неделю есть задания на бонусную энергию. Сезоны идут по календарным месяцам и создаются сами; у каждого
        своя копия шаблона, поэтому правка шаблона не меняет идущий сезон.
      </p>
      <PassStripSection />
      <EconomySection />
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

// --- Season energy -----------------------------------------------------------

function SettingsSection() {
  const [s, setS] = useState<PassSettings | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    getPassSettings()
      .then(setS)
      .catch(() => setMessage("Не удалось загрузить"));
  }, []);

  if (!s) return <Section title="Энергия сезона">{message && <p className="text-sm text-red-600">{message}</p>}</Section>;

  const fields: { key: keyof PassSettings; label: string }[] = [
    { key: "xp_word", label: "За изученное слово" },
    { key: "xp_lesson", label: "За пройденный урок" },
    { key: "xp_review", label: "За слово в «Повторить сегодня»" },
    { key: "xp_quest", label: "За выполненное задание квеста" },
    { key: "xp_streak", label: "За день серии" },
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
    <Section title="Энергия сезона">
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
            checked={s.duels_enabled}
            onChange={(e) => setS({ ...s, duels_enabled: e.target.checked })}
          />
          Дуэли друзей на неделю
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
  const isCosmetic = value?.type === "badge" || value?.type === "title" || value?.type === "frame";
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
            if (type === "frame") return onChange({ type, amount: 1, key: "gold", text: "" });
            if (type === "title") return onChange({ type, amount: 1, text: "" });
            if (type === "chest") return onChange({ type, amount: 1, key: "wood" });
            if (type === "booster") return onChange({ type, amount: 30 });
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
        {value?.type === "booster" && (
          <select className={`${inputClass} w-28`} value={value.amount} onChange={(e) => onChange({ ...value, amount: Number(e.target.value) })}>
            <option value={30}>30 минут</option>
            <option value={60}>1 час</option>
            <option value={1440}>24 часа</option>
          </select>
        )}
        {value && !isCosmetic && value.type !== "chest" && value.type !== "booster" && (
          <input
            type="number"
            min={1}
            className={`${inputClass} w-16`}
            value={value.amount}
            onChange={(e) => onChange({ ...value, amount: Math.max(1, Number(e.target.value) || 1) })}
          />
        )}
        {value?.type === "chest" && (
          <>
            <img src={`${import.meta.env.BASE_URL}chests/${value.key ?? "wood"}_closed.png`} alt="" style={{ width: 28, height: 28, objectFit: "contain" }} />
            <select className={`${inputClass} w-32`} value={value.key ?? "wood"} onChange={(e) => onChange({ ...value, key: e.target.value })}>
              {Object.entries(CHEST_NAMES).map(([k, v]) => (
                <option key={k} value={k}>{v}</option>
              ))}
            </select>
          </>
        )}
        {(value?.type === "badge" || value?.type === "frame") && (
          <select
            className={`${inputClass} w-28`}
            value={value.key ?? (value.type === "frame" ? "gold" : "crown")}
            onChange={(e) => onChange({ ...value, key: e.target.value })}
          >
            {Object.entries(value.type === "frame" ? FRAME_LOOKS : BADGE_LOOKS).map(([k, v]) => (
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
                <th className="px-1 py-1 font-medium">Энергия на уровень</th>
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
        Энергия каждому
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

const SOURCE_LABEL: Record<string, string> = {
  word: "Слова",
  lesson: "Уроки",
  review: "Повторения",
  quest: "Квесты",
  streak: "День серии",
  daily_goal: "Цель дня",
  comeback: "Возвращение",
};
const CLAIM_LABEL: Record<string, string> = {
  free: "Бесплатные награды",
  premium: "Premium-награды",
  task: "Недельные задания",
  team: "Командные цели",
};

function EconomySection() {
  const [data, setData] = useState<PassEconomy | null | undefined>(undefined);

  useEffect(() => {
    getPassEconomy()
      .then(setData)
      .catch(() => setData(null));
  }, []);

  const maxPeople = Math.max(1, ...(data?.level_distribution.map((l) => l.people) ?? [1]));
  const maxXp = Math.max(1, ...(data?.xp_by_source.map((x) => x.xp) ?? [1]));
  return (
    <Section title="Экономика пропуска">
      {data === undefined ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : data === null ? (
        <p className="text-sm text-slate-500">Сейчас нет активного сезона.</p>
      ) : (
        <div className="flex flex-col gap-4">
          <p className="text-sm text-slate-500">
            {data.season_name}: {data.players} игроков, {data.total_xp} энергии всего, в среднем {data.avg_xp} энергии на человека
            ({data.avg_xp_per_day} в день). Команд: {data.teams}, людей в них: {data.team_members}.
          </p>
          <div>
            <h3 className="mb-1 text-sm font-semibold text-slate-700">Откуда берётся энергия</h3>
            {data.xp_by_source.map((x) => (
              <div key={x.source} className="mb-1 flex items-center gap-2 text-xs text-slate-600">
                <span className="w-28">{SOURCE_LABEL[x.source] ?? x.source}</span>
                <div className="h-3 flex-1 rounded bg-slate-100">
                  <div className="h-3 rounded bg-indigo-500" style={{ width: `${(x.xp / maxXp) * 100}%` }} />
                </div>
                <span className="w-24 text-right">⚡ {x.xp} · {x.events}</span>
              </div>
            ))}
          </div>
          <div>
            <h3 className="mb-1 text-sm font-semibold text-slate-700">Люди по уровням</h3>
            {data.level_distribution.map((l) => (
              <div key={l.level} className="mb-0.5 flex items-center gap-2 text-xs text-slate-600">
                <span className="w-28">{l.level === 0 ? "Без уровня" : `Уровень ${l.level}`}</span>
                <div className="h-2.5 flex-1 rounded bg-slate-100">
                  <div className="h-2.5 rounded bg-emerald-500" style={{ width: `${(l.people / maxPeople) * 100}%` }} />
                </div>
                <span className="w-10 text-right">{l.people}</span>
              </div>
            ))}
          </div>
          <div className="flex flex-wrap gap-2">
            {Object.entries(CLAIM_LABEL).map(([k, label]) => (
              <span key={k} className="card px-3 py-1.5 text-xs text-slate-700">
                {label}: <b>{data.claims_by_kind[k] ?? 0}</b>
              </span>
            ))}
          </div>
        </div>
      )}
    </Section>
  );
}

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

  /** Saves the template and copies it into the season that is running now (players see it at once). */
  async function saveAndApply() {
    if (!editing) return;
    const running = (await listSeasons()).find((s) => s.status === "active");
    if (!running) {
      setMessage("Сейчас нет идущего сезона: шаблон сохранён только как шаблон.");
      await save();
      return;
    }
    if (!window.confirm(`Заменить пропуск идущего сезона «${running.name}» этим шаблоном? Уже полученные игроками награды остаются.`)) return;
    await run(async () => {
      const id = editing.id == null ? (await createPassTemplate(editing.name, editing.definition)).id : (await updatePassTemplate(editing.id, editing.name, editing.definition)).id;
      await applyPassTemplate(running.id, id);
      setEditing(null);
      setMessage(`Шаблон сохранён и применён к сезону «${running.name}»`);
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
            <button onClick={saveAndApply} className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700">
              Сохранить и применить к идущему сезону
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


// --- The running pass, drawn as in the app ---------------------------------------------------

const BADGE_COLORS: Record<string, [string, string]> = {
  crown: ["#FFD54F", "#FF8F00"], champion: ["#FFD54F", "#FF8F00"], medal: ["#90CAF9", "#3F7CFF"], flame: ["#FFA06B", "#E5391F"],
  star: ["#FFE066", "#FFA000"], diamond: ["#7FDBFF", "#7C4DFF"], rocket: ["#FF8AB8", "#8E3CFF"], shield: ["#6EE7B7", "#0E9F6E"], bolt: ["#FFF176", "#FFA000"],
};
const FRAME_COLORS: Record<string, [string, string]> = {
  gold: ["#FFD54F", "#FF9800"], aurora: ["#6EE7B7", "#60A5FA"], fire: ["#FF7043", "#FFB74D"], ocean: ["#38BDF8", "#2563EB"],
  emerald: ["#34D399", "#059669"], royal: ["#8B5CF6", "#FFD54F"], rose: ["#F472B6", "#FB7185"], ice: ["#BAE6FD", "#7DD3FC"],
};
const IMG = `${import.meta.env.BASE_URL}`;

/** How one reward looks in the app: gradient, picture, amount and name (the same as the app's RewardCard). */
function passLook(r: PassReward): { colors: [string, string]; img: string | null; glyph: string; amount: string; label: string } {
  switch (r.type) {
    case "premium_days": return { colors: ["#FFD54F", "#FF9800"], img: null, glyph: "👑", amount: `+${r.amount}`, label: "Дни Premium" };
    case "streak_freeze": return { colors: ["#7FDBFF", "#3A7BFF"], img: `${IMG}preview/freeze.png`, glyph: "", amount: `+${r.amount}`, label: "Заморозка серии" };
    case "diamonds": return { colors: ["#87EFFF", "#3A7BFF"], img: `${IMG}preview/gem.png`, glyph: "", amount: `+${r.amount}`, label: "Бриллианты" };
    case "chest": return { colors: ["#FFB86B", "#B4541F"], img: `${IMG}chests/${r.key ?? "wood"}_closed.png`, glyph: "", amount: "", label: "Сундук" };
    case "booster": return { colors: ["#B07CFF", "#5B2EE0"], img: `${IMG}preview/booster.png`, glyph: "", amount: r.amount >= 60 && r.amount % 60 === 0 ? `${r.amount / 60}ч` : `${r.amount}м`, label: "Удвоитель" };
    case "badge": return { colors: BADGE_COLORS[r.key ?? "crown"] ?? ["#FFD54F", "#FF8F00"], img: null, glyph: "🏅", amount: "", label: r.text || "Значок" };
    case "frame": return { colors: FRAME_COLORS[r.key ?? "gold"] ?? ["#FFD54F", "#FF9800"], img: null, glyph: "◎", amount: "", label: r.text || "Рамка" };
    case "title": return { colors: ["#6EE7B7", "#0E9F6E"], img: null, glyph: "🎖", amount: "", label: r.text || "Титул" };
    default: return { colors: ["#A48BFF", "#5862DD"], img: `${IMG}preview/points.png`, glyph: "", amount: `+${r.amount}`, label: "Звёзды рейтинга" };
  }
}

function PassCard({ reward, premium, onClick }: { reward: PassReward | null; premium: boolean; onClick: () => void }) {
  if (!reward) {
    return (
      <button onClick={onClick} className="flex w-full items-center justify-center rounded-[18px] border-2 border-dashed border-slate-300 text-xs text-slate-400 hover:border-indigo-400 hover:text-indigo-500" style={{ minHeight: 112 }}>
        + награда
      </button>
    );
  }
  const l = passLook(reward);
  return (
    <button
      onClick={onClick}
      title="Нажмите, чтобы изменить награду"
      className="relative block w-full overflow-hidden text-center transition hover:brightness-110"
      style={{ minHeight: 112, padding: "10px 8px", borderRadius: 18, background: `linear-gradient(135deg, ${l.colors[0]}, ${l.colors[1]})`, boxShadow: "0 3px 8px rgba(0,0,0,0.12)", outline: premium ? "2px solid rgba(255,213,79,0.8)" : undefined }}
    >
      <div className="flex flex-col items-center justify-center">
        {l.img ? (
          <img src={l.img} alt="" draggable={false} style={{ width: 46, height: 46, objectFit: "contain", maxWidth: "none" }} />
        ) : (
          <span className="flex h-[38px] w-[38px] items-center justify-center rounded-full text-xl text-white" style={{ background: "rgba(255,255,255,0.25)" }}>{l.glyph}</span>
        )}
        {l.amount && <div style={{ fontSize: 21, lineHeight: 1.1, fontWeight: 900, color: "#fff", marginTop: 4 }}>{l.amount}</div>}
        <div style={{ fontSize: 11.5, fontWeight: 600, color: "rgba(255,255,255,0.95)", marginTop: l.amount ? 0 : 4 }}>{l.label}</div>
      </div>
    </button>
  );
}

function PassStripSection() {
  const [season, setSeason] = useState<{ id: number; name: string } | null>(null);
  const [def, setDef] = useState<PassDefinition | null>(null);
  const [edit, setEdit] = useState<{ level: number; track: "free" | "premium" } | null>(null);
  const [draft, setDraft] = useState<PassReward | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    try {
      const running = (await listSeasons()).find((s) => s.status === "active");
      if (!running) { setSeason(null); setDef(null); return; }
      setSeason({ id: running.id, name: running.name });
      setDef((await getSeasonPassDef(running.id)).definition);
    } catch {
      setMessage("Не удалось загрузить пропуск сезона");
    }
  }
  useEffect(() => { void load(); }, []);

  async function save() {
    if (!season || !def || !edit) return;
    const next: PassDefinition = { ...def, levels: def.levels.map((l) => (l.level === edit.level ? { ...l, [edit.track]: draft } : l)) };
    try {
      const saved = await updateSeasonPassDef(season.id, next);
      setDef(saved.definition);
      setEdit(null);
      setMessage("Награда сохранена, игроки увидят её при следующей загрузке пропуска");
    } catch (e) {
      setMessage(errorText(e, "Не удалось сохранить"));
    }
  }

  if (!season || !def) {
    return <Section title="Текущий пропуск">{message ? <p className="text-sm text-red-600">{message}</p> : <p className="text-sm text-slate-500">Сейчас нет идущего сезона.</p>}</Section>;
  }
  return (
    <Section title={`Пропуск сезона «${season.name}» как в приложении`}>
      {message && <p className="mb-2 text-sm text-slate-500">{message}</p>}
      <p className="mb-2 text-xs text-slate-500">Листайте вбок. Сверху бесплатная награда, снизу Premium. Нажмите на награду, чтобы изменить её (сохраняется в этот сезон).</p>
      <div className="overflow-x-auto rounded-2xl p-3" style={{ background: "linear-gradient(135deg,#6A4CFF22,#2F7CF622)" }}>
        <div className="flex gap-2" style={{ minWidth: "max-content" }}>
          {def.levels.map((l) => (
            <div key={l.level} style={{ width: 118 }}>
              <div className="mb-1 text-center text-[10px] font-bold uppercase text-slate-500">Бесплатно</div>
              <PassCard reward={l.free} premium={false} onClick={() => { setEdit({ level: l.level, track: "free" }); setDraft(l.free); }} />
              <div className="relative my-2 flex items-center justify-center" style={{ height: 36 }}>
                <div className="absolute left-0 right-0 top-1/2" style={{ height: 5, borderRadius: 3, background: "#7C6BFF", transform: "translateY(-50%)" }} />
                <div className="relative flex items-center justify-center text-sm font-black text-white" style={{ width: 36, height: 36, borderRadius: 99, background: "linear-gradient(135deg,#9B8CFF,#5862DD)", boxShadow: "0 0 10px rgba(124,107,255,0.45)", border: "2px solid #fff" }}>{l.level}</div>
              </div>
              <PassCard reward={l.premium} premium onClick={() => { setEdit({ level: l.level, track: "premium" }); setDraft(l.premium); }} />
              <div className="mt-1 text-center text-[10px] font-bold uppercase" style={{ color: "#c98a00" }}>Premium</div>
              <div className="text-center text-[10px] text-slate-400">{l.xp} XP</div>
            </div>
          ))}
        </div>
      </div>
      {edit && (
        <div className="card mt-3 flex flex-col gap-3 p-4">
          <div className="text-sm font-medium text-slate-700">Уровень {edit.level}, {edit.track === "free" ? "бесплатная награда" : "награда Premium"}</div>
          <RewardEditor value={draft} onChange={setDraft} />
          <div className="flex gap-3">
            <button onClick={save} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">Сохранить награду</button>
            <button onClick={() => setEdit(null)} className="text-sm text-slate-500">Отмена</button>
          </div>
        </div>
      )}
    </Section>
  );
}

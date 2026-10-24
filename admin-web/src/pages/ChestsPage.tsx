import axios from "axios";
import { useEffect, useState } from "react";
import {
  getChestOverview,
  getRewardRules,
  saveChestSettings,
  saveChestType,
  saveRewardRules,
  sendChest,
  type ChestOverview,
  type ChestSettings,
  type ChestType,
  type EventReward,
  type GoalTier,
  type RewardRules,
} from "../api/endpoints";

const field = "field min-w-0 rounded-lg px-2 py-1.5 text-sm";
const primary = "bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 rounded-lg px-3 py-2 text-sm";
const BASE = `${import.meta.env.BASE_URL}chests/`;
const SOURCES: Record<string, string> = {
  daily: "Сундук дня", pass: "Пропуск сезона", duel: "Дуэли", goal: "Цель дня",
  streak: "Серия дней", comeback: "Возвращение", admin: "Отправлено вручную",
};
const PRIZES: Record<string, string> = { diamonds: "Бриллианты", freeze: "Заморозки", merge: "Объединители", points: "Очки рейтинга" };
const EVENTS: [string, string][] = [
  ["duel_win", "Дуэль: победа"], ["duel_draw", "Дуэль: ничья"], ["duel_lose", "Дуэль: поражение"],
  ["streak_7", "Серия 7 дней"], ["streak_30", "Серия 30 дней"], ["streak_100", "Серия 100 дней"],
  ["comeback", "Возвращение после перерыва"],
];

function errorMessage(e: unknown) {
  return axios.isAxiosError(e) ? (e.response?.data?.detail ?? e.message) : String(e);
}

export function ChestsPage() {
  const [data, setData] = useState<ChestOverview | null>(null);
  const [rules, setRules] = useState<RewardRules | null>(null);
  const [error, setError] = useState("");
  const reload = async () => {
    try {
      const [o, r] = await Promise.all([getChestOverview(), getRewardRules()]);
      setData(o); setRules(r); setError("");
    } catch (e) { setError(errorMessage(e)); }
  };
  useEffect(() => { void reload(); }, []);
  if (!data || !rules) return <main className="mx-auto max-w-5xl">{error ? <div className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</div> : <p className="text-sm text-slate-500">Загрузка…</p>}</main>;
  return (
    <main className="mx-auto max-w-5xl space-y-8">
      <header>
        <h1 className="text-2xl font-bold">Сундуки</h1>
        <p className="mt-1 text-sm text-slate-500">
          Четыре сундука, сундук дня, награды за события и учёт выдачи. Из сундука выпадает один приз, количество случайно от 1 до потолка.
        </p>
      </header>
      {error && <div className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</div>}
      <TypesSection types={data.types} onError={setError} onSaved={reload} />
      <DailySection types={data.types} settings={data.settings} onError={setError} onSaved={reload} />
      <SendSection types={data.types} />
      <RulesSection types={data.types} rules={rules} onError={setError} onSaved={reload} />
      <StatsSection data={data} />
    </main>
  );
}

function TypesSection({ types, onError, onSaved }: { types: ChestType[]; onError: (m: string) => void; onSaved: () => Promise<void> }) {
  const [items, setItems] = useState(types);
  useEffect(() => setItems(types), [types]);
  const set = (i: number, patch: Partial<ChestType>) => setItems(items.map((c, n) => (n === i ? { ...c, ...patch } : c)));
  const num = (v: string) => Math.max(0, Number(v) || 0);
  const save = async (c: ChestType) => { try { await saveChestType(c); await onSaved(); } catch (e) { onError(errorMessage(e)); } };
  return (
    <section className="card p-4">
      <h2 className="mb-1 text-lg font-semibold">Четыре сундука</h2>
      <p className="mb-4 text-sm text-slate-500">Потолок 0 — такого приза в этом сундуке нет. Должен остаться хотя бы один приз.</p>
      <div className="grid gap-4 md:grid-cols-2">
        {items.map((c, i) => (
          <div key={c.key} className="rounded-xl border border-slate-200 p-3" style={{ borderTop: `4px solid ${c.color}` }}>
            <div className="mb-3 flex items-center gap-3">
              <img src={`${BASE}${c.key}_closed.png`} alt="" style={{ width: 72, height: 72, objectFit: "contain" }} />
              <img src={`${BASE}${c.key}_open.png`} alt="" style={{ width: 72, height: 72, objectFit: "contain" }} />
              <div className="min-w-0 flex-1 space-y-1">
                <input className={`${field} w-full`} value={c.name} aria-label="Название" onChange={(e) => set(i, { name: e.target.value })} />
                <label className="flex items-center gap-2 text-xs text-slate-500">Цвет
                  <input type="color" value={c.color} onChange={(e) => set(i, { color: e.target.value })} />
                </label>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs text-slate-600">
              <label>Бриллианты до<input className={`${field} w-full`} type="number" min={0} value={c.max_diamonds} onChange={(e) => set(i, { max_diamonds: num(e.target.value) })} /></label>
              <label>Заморозки до<input className={`${field} w-full`} type="number" min={0} value={c.max_freezes} onChange={(e) => set(i, { max_freezes: num(e.target.value) })} /></label>
              <label>Объединители до<input className={`${field} w-full`} type="number" min={0} value={c.max_merges} onChange={(e) => set(i, { max_merges: num(e.target.value) })} /></label>
              <label>Очки рейтинга до<input className={`${field} w-full`} type="number" min={0} value={c.max_points} onChange={(e) => set(i, { max_points: num(e.target.value) })} /></label>
            </div>
            <button className={`${primary} mt-3`} onClick={() => void save(c)}>Сохранить</button>
          </div>
        ))}
      </div>
    </section>
  );
}

function ChestPicker({ types, value, onChange }: { types: ChestType[]; value: string; onChange: (k: string) => void }) {
  return (
    <div className="flex flex-wrap gap-2">
      {types.map((c) => (
        <button key={c.key} type="button" onClick={() => onChange(c.key)} title={c.name}
          className={`flex items-center gap-1.5 rounded-xl border-2 px-2 py-1 text-sm ${value === c.key ? "border-indigo-600 bg-indigo-50" : "border-slate-200"}`}>
          <img src={`${BASE}${c.key}_closed.png`} alt="" style={{ width: 36, height: 36, objectFit: "contain" }} />
          {c.name}
        </button>
      ))}
    </div>
  );
}

function DailySection({ types, settings, onError, onSaved }: { types: ChestType[]; settings: ChestSettings; onError: (m: string) => void; onSaved: () => Promise<void> }) {
  const [s, setS] = useState(settings);
  useEffect(() => setS(settings), [settings]);
  const save = async (double_hours?: number | null) => { try { await saveChestSettings({ ...s, double_hours }); await onSaved(); } catch (e) { onError(errorMessage(e)); } };
  const n = (v: string, min: number) => Math.max(min, Number(v) || min);
  return (
    <section className="card space-y-3 p-4">
      <h2 className="text-lg font-semibold">Сундук дня</h2>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={s.daily_enabled} onChange={(e) => setS({ ...s, daily_enabled: e.target.checked })} /> Сундук дня включён</label>
      <div><div className="mb-1 text-sm text-slate-500">Какой сундук выдаётся каждый день:</div><ChestPicker types={types} value={s.daily_chest_key} onChange={(k) => setS({ ...s, daily_chest_key: k })} /></div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={s.daily_requires_activity} onChange={(e) => setS({ ...s, daily_requires_activity: e.target.checked })} /> Выдавать только после первого занятия за день</label>
      <label className="block text-sm text-slate-600">За что дают (этот текст видит игрок на карточке)
        <textarea className={`${field} mt-1 w-full`} rows={2} value={s.daily_conditions} onChange={(e) => setS({ ...s, daily_conditions: e.target.value })} />
      </label>
      <div className="grid gap-3 text-xs text-slate-600 md:grid-cols-3">
        <label>В копилке не больше сундуков<input className={`${field} w-full`} type="number" min={1} value={s.inventory_max} onChange={(e) => setS({ ...s, inventory_max: n(e.target.value, 1) })} /></label>
        <label>Сундуков в сутки на человека (кроме ручных)<input className={`${field} w-full`} type="number" min={1} value={s.daily_cap} onChange={(e) => setS({ ...s, daily_cap: n(e.target.value, 1) })} /></label>
        <label>«Повезёт»: после скольких слабых подряд (0 — выкл.)<input className={`${field} w-full`} type="number" min={0} value={s.pity_after} onChange={(e) => setS({ ...s, pity_after: n(e.target.value, 0) })} /></label>
      </div>
      <p className="text-xs text-slate-500">Лимиты копилки и суток действуют на сундук дня; заработанные награды (пропуск, дуэли, цель, серия) не теряются.</p>
      <div className="flex flex-wrap items-center gap-2"><button className={primary} onClick={() => void save()}>Сохранить</button></div>
      <div className="rounded-xl bg-amber-50 p-3 text-sm">
        <div className="font-medium">Двойные награды из сундуков: {s.double_until ? `включены до ${new Date(s.double_until).toLocaleString()}` : "выключены"}</div>
        <div className="mt-2 flex flex-wrap gap-2">
          <button className={primary} onClick={() => void save(24)}>На 24 часа</button>
          <button className={primary} onClick={() => void save(72)}>На 3 дня</button>
          <button className={primary} onClick={() => void save(168)}>На неделю</button>
          <button className="rounded-lg bg-slate-100 px-3 py-2 text-sm text-slate-700 hover:bg-slate-200" onClick={() => void save(0)}>Выключить</button>
        </div>
      </div>
    </section>
  );
}

function SendSection({ types }: { types: ChestType[] }) {
  const [user, setUser] = useState("");
  const [key, setKey] = useState("wood");
  const [count, setCount] = useState(1);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");
  const send = async () => {
    if (!user.trim()) return;
    setMsg(""); setErr("");
    try { const r = await sendChest(user.trim(), key, count); setMsg(`${r.login}: отправлено, в копилке теперь ${r.bank}`); } catch (e) { setErr(errorMessage(e)); }
  };
  return (
    <section className="card space-y-3 p-4">
      <h2 className="text-lg font-semibold">Отправить сундук пользователю</h2>
      <p className="text-sm text-slate-500">Можно отправлять повторно и по несколько штук, лимиты не мешают. Пользователь получит уведомление, а сундук появится на главном экране.</p>
      <div className="flex flex-wrap items-end gap-2">
        <input className={`${field} w-56`} placeholder="Логин или ID" value={user} onChange={(e) => setUser(e.target.value)} />
        <input className={`${field} w-20`} type="number" min={1} max={10} value={count} onChange={(e) => setCount(Math.min(10, Math.max(1, Number(e.target.value) || 1)))} />
        <button className={primary} onClick={() => void send()}>Отправить</button>
      </div>
      <ChestPicker types={types} value={key} onChange={setKey} />
      {msg && <div className="text-sm text-emerald-700">{msg}</div>}
      {err && <div className="text-sm text-red-700">{err}</div>}
    </section>
  );
}

export function RewardListEditor({ types, value, onChange }: { types: ChestType[]; value: EventReward[]; onChange: (v: EventReward[]) => void }) {
  const set = (i: number, patch: Partial<EventReward>) => onChange(value.map((r, n) => (n === i ? { ...r, ...patch } : r)));
  return (
    <div className="space-y-1">
      {value.map((r, i) => (
        <div key={i} className="flex flex-wrap items-center gap-1">
          <select className={`${field} w-40`} value={r.type} onChange={(e) => {
            const type = e.target.value as EventReward["type"];
            set(i, type === "chest" ? { type, amount: 1, key: "wood" } : { type, amount: Math.max(1, r.amount), key: undefined });
          }}>
            <option value="xp">XP пропуска</option>
            <option value="chest">Сундук</option>
            <option value="diamonds">Бриллианты</option>
            <option value="rating_points">Очки рейтинга</option>
          </select>
          {r.type === "chest" && (
            <>
              <img src={`${BASE}${r.key ?? "wood"}_closed.png`} alt="" style={{ width: 28, height: 28, objectFit: "contain" }} />
              <select className={`${field} w-44`} value={r.key ?? "wood"} onChange={(e) => set(i, { key: e.target.value })}>
                {types.map((c) => <option key={c.key} value={c.key}>{c.name}</option>)}
              </select>
            </>
          )}
          <input className={`${field} w-20`} type="number" min={1} value={r.amount} onChange={(e) => set(i, { amount: Math.max(1, Number(e.target.value) || 1) })} title={r.type === "chest" ? "Сколько сундуков" : "Количество"} />
          <button className="rounded-lg bg-slate-100 px-2 py-1 text-sm text-slate-600 hover:bg-slate-200" onClick={() => onChange(value.filter((_, n) => n !== i))}>×</button>
        </div>
      ))}
      {value.length < 6 && (
        <button className="text-sm text-indigo-600 hover:underline" onClick={() => onChange([...value, { type: "xp", amount: 10 }])}>+ добавить награду</button>
      )}
      {value.length === 0 && <div className="text-xs text-slate-400">Награды нет</div>}
    </div>
  );
}

function RulesSection({ types, rules, onError, onSaved }: { types: ChestType[]; rules: RewardRules; onError: (m: string) => void; onSaved: () => Promise<void> }) {
  const [r, setR] = useState(rules);
  useEffect(() => setR(rules), [rules]);
  const [done, setDone] = useState(false);
  const tiers: GoalTier[] = r.daily_goal;
  const setTier = (i: number, patch: Partial<GoalTier>) => setR({ ...r, daily_goal: tiers.map((t, n) => (n === i ? { ...t, ...patch } : t)) });
  const save = async () => { try { await saveRewardRules(r); await onSaved(); setDone(true); setTimeout(() => setDone(false), 2500); } catch (e) { onError(errorMessage(e)); } };
  return (
    <section className="card space-y-4 p-4">
      <h2 className="text-lg font-semibold">Награды за события</h2>
      <p className="text-sm text-slate-500">Каждая награда — XP пропуска, сундук, бриллианты или очки рейтинга. Награды уровней пропуска настраиваются в шаблоне пропуска (тип «Сундук»).</p>
      <div className="grid gap-4 md:grid-cols-2">
        {EVENTS.map(([key, label]) => (
          <div key={key} className="rounded-xl border border-slate-200 p-3">
            <div className="mb-2 text-sm font-medium">{label}</div>
            <RewardListEditor types={types} value={(r[key] as EventReward[]) ?? []} onChange={(v) => setR({ ...r, [key]: v })} />
          </div>
        ))}
      </div>
      <div className="rounded-xl border border-slate-200 p-3">
        <div className="mb-1 text-sm font-medium">Цель дня: варианты слов и награда за каждый</div>
        <p className="mb-2 text-xs text-slate-500">Каждый вариант платит один раз в сутки (по времени Душанбе). От 1 до 6 вариантов.</p>
        <div className="space-y-3">
          {tiers.map((t, i) => (
            <div key={i} className="flex flex-wrap items-start gap-3 border-b border-slate-100 pb-3">
              <label className="text-xs text-slate-600">Слов<input className={`${field} w-20`} type="number" min={1} value={t.words} onChange={(e) => setTier(i, { words: Math.max(1, Number(e.target.value) || 1) })} /></label>
              <div className="flex-1"><RewardListEditor types={types} value={t.rewards} onChange={(v) => setTier(i, { rewards: v })} /></div>
              {tiers.length > 1 && <button className="rounded-lg bg-slate-100 px-2 py-1 text-sm text-slate-600 hover:bg-slate-200" onClick={() => setR({ ...r, daily_goal: tiers.filter((_, n) => n !== i) })}>Удалить</button>}
            </div>
          ))}
        </div>
        {tiers.length < 6 && <button className="mt-2 text-sm text-indigo-600 hover:underline" onClick={() => setR({ ...r, daily_goal: [...tiers, { words: (tiers[tiers.length - 1]?.words ?? 0) + 5, rewards: [{ type: "xp", amount: 10 }] }] })}>+ добавить вариант</button>}
      </div>
      <div className="flex items-center gap-3"><button className={primary} onClick={() => void save()}>Сохранить награды</button>{done && <span className="text-sm text-emerald-700">Сохранено</span>}</div>
    </section>
  );
}

function StatsSection({ data }: { data: ChestOverview }) {
  const { stats, types } = data;
  const name = (k: string) => types.find((t) => t.key === k)?.name ?? k;
  const total = stats.granted.reduce((s, g) => s + g.count, 0);
  return (
    <section className="card space-y-3 p-4">
      <h2 className="text-lg font-semibold">Учёт выдачи за {stats.days} дней</h2>
      <p className="text-sm text-slate-500">Выдано сундуков всего: {total}</p>
      <div className="grid gap-4 md:grid-cols-2">
        <table className="w-full text-sm">
          <thead><tr className="text-left text-slate-500"><th>Откуда</th><th>Сундук</th><th className="text-right">Штук</th></tr></thead>
          <tbody>{stats.granted.map((g, i) => <tr key={i} className="border-t border-slate-100"><td>{SOURCES[g.source] ?? g.source}</td><td>{name(g.chest_key)}</td><td className="text-right">{g.count}</td></tr>)}</tbody>
        </table>
        <table className="w-full text-sm">
          <thead><tr className="text-left text-slate-500"><th>Приз</th><th className="text-right">Открыто</th><th className="text-right">Роздано всего</th></tr></thead>
          <tbody>{stats.prizes.map((p) => <tr key={p.kind} className="border-t border-slate-100"><td>{PRIZES[p.kind] ?? p.kind}</td><td className="text-right">{p.opened}</td><td className="text-right">{p.total}</td></tr>)}</tbody>
        </table>
      </div>
    </section>
  );
}

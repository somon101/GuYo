import { useEffect, useState } from "react";
import { getRewardRules, type EventReward } from "../api/endpoints";

// A preview only: how the weekly duel card looks to a player, with the real
// rewards from the "Сундуки" page. Nothing is sent to the server.

const BASE = `${import.meta.env.BASE_URL}`;
const DEFAULTS: Record<string, EventReward[]> = {
  duel_win: [{ type: "xp", amount: 50 }, { type: "chest", key: "wood", amount: 1 }],
  duel_draw: [{ type: "xp", amount: 10 }],
  duel_lose: [],
};
type Stage = "none" | "pending" | "active" | "done";
type Outcome = "win" | "draw" | "lose";

const CHEST_NAMES: Record<string, string> = { wood: "Деревянный сундук", silver: "Серебряный сундук", purple: "Фиолетовый сундук", gold: "Золотой сундук" };

function Reward({ r, big = false }: { r: EventReward; big?: boolean }) {
  const s = big ? 54 : 32;
  const box = "inline-flex flex-col items-center justify-center rounded-2xl px-3 py-2 text-center";
  const bg = { background: "rgba(255,255,255,0.12)", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.2)" };
  const num = { fontWeight: 900, fontSize: big ? 18 : 13, color: "#fff" } as const;
  if (r.type === "chest")
    return <span className={box} style={bg}><img src={`${BASE}chests/${r.key ?? "wood"}_closed.png`} alt="" style={{ width: s + 10, height: s + 10, objectFit: "contain" }} /><span style={num}>{r.amount > 1 ? `×${r.amount}` : CHEST_NAMES[r.key ?? "wood"]?.split(" ")[0]}</span></span>;
  if (r.type === "diamonds")
    return <span className={box} style={bg}><img src={`${BASE}preview/gem.png`} alt="" style={{ width: s, height: s, objectFit: "contain" }} /><span style={num}>+{r.amount}</span></span>;
  if (r.type === "rating_points")
    return <span className={box} style={bg}><img src={`${BASE}preview/points.png`} alt="" style={{ width: s, height: s, objectFit: "contain" }} /><span style={num}>+{r.amount}</span></span>;
  return <span className={box} style={bg}><span style={{ fontSize: s * 0.9, lineHeight: 1 }}>⚡</span><span style={num}>{r.amount} XP</span></span>;
}

function Rewards({ list, big }: { list: EventReward[]; big?: boolean }) {
  if (!list.length) return <span style={{ color: "rgba(255,255,255,0.55)", fontSize: 13 }}>без награды</span>;
  return <span className="flex flex-wrap justify-center gap-2">{list.map((r, i) => <Reward key={i} r={r} big={big} />)}</span>;
}

function Avatar({ name, color }: { name: string; color: string }) {
  return <span className="flex items-center justify-center rounded-full text-xl font-black text-white" style={{ width: 56, height: 56, background: color, boxShadow: "0 0 0 3px rgba(255,255,255,0.35)" }}>{name[0].toUpperCase()}</span>;
}

const green = {
  background: "linear-gradient(180deg,#9dff72 0%,#3fd43a 48%,#1ea82c 100%)",
  boxShadow: "0 4px 0 #0f6b1d, 0 8px 12px rgba(0,0,0,0.35), inset 0 2px 0 rgba(255,255,255,0.7)",
  border: "2px solid #0f6b1d", color: "#fff", textShadow: "0 2px 0 #0f6b1d", letterSpacing: 0.6,
} as const;

export function DuelPreviewPage() {
  const [rules, setRules] = useState(DEFAULTS);
  const [stage, setStage] = useState<Stage>("active");
  const [outcome, setOutcome] = useState<Outcome>("win");
  useEffect(() => {
    getRewardRules().then((r) => {
      const next = { ...DEFAULTS };
      for (const k of Object.keys(DEFAULTS)) if (Array.isArray((r as Record<string, unknown>)[k])) next[k] = (r as unknown as Record<string, EventReward[]>)[k];
      setRules(next);
    }).catch(() => undefined);
  }, []);

  const mine = outcome === "win" ? 308 : outcome === "draw" ? 250 : 204;
  const theirs = outcome === "win" ? 204 : outcome === "draw" ? 250 : 308;
  const key = outcome === "win" ? "duel_win" : outcome === "draw" ? "duel_draw" : "duel_lose";
  const shell = "mx-auto w-full max-w-sm rounded-3xl p-4 text-white";
  const bg = { background: "linear-gradient(135deg,#3d2b8f,#1e1560)", boxShadow: "0 18px 40px rgba(30,20,90,0.35)" };
  const chip = (s: Stage, label: string) => (
    <button key={s} type="button" onClick={() => setStage(s)} className={`rounded-lg px-3 py-1.5 text-sm ${stage === s ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>{label}</button>
  );

  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр дуэли</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. Награды берутся из страницы «Сундуки» → «Награды за события». Сначала смотрим здесь, потом переносим в приложение.
        </p>
      </header>

      <section className="card space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500">Состояние:</span>
          {chip("none", "Нет дуэли")}{chip("pending", "Ждёт ответа")}{chip("active", "Идёт")}{chip("done", "Закончилась")}
        </div>
        {stage === "done" && (
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-slate-500">Итог для меня:</span>
            {(["win", "draw", "lose"] as Outcome[]).map((o) => (
              <button key={o} type="button" onClick={() => setOutcome(o)} className={`rounded-lg px-3 py-1.5 text-sm ${outcome === o ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>
                {o === "win" ? "Победа" : o === "draw" ? "Ничья" : "Поражение"}
              </button>
            ))}
          </div>
        )}
      </section>

      <section className="py-2">
        {stage === "none" && (
          <div className={shell} style={bg}>
            <div className="mb-1 text-lg font-black">⚔️ Дуэль недели</div>
            <p className="mb-3 text-sm text-white/80">Вызовите друга: кто за неделю наберёт больше энергии, тот победил.</p>
            <div className="mb-3 space-y-2 rounded-2xl bg-black/20 p-3">
              <div className="text-xs font-bold uppercase tracking-wide text-white/60">Что можно выиграть</div>
              <div className="flex items-center justify-between gap-2"><span className="text-sm font-bold">🏆 Победа</span><Rewards list={rules.duel_win} /></div>
              <div className="flex items-center justify-between gap-2"><span className="text-sm font-bold">🤝 Ничья</span><Rewards list={rules.duel_draw} /></div>
            </div>
            <button className="w-full rounded-xl px-4 py-3 text-sm font-black uppercase" style={green}>Вызвать друга</button>
          </div>
        )}

        {(stage === "pending" || stage === "active") && (
          <div className={shell} style={bg}>
            <div className="mb-3 flex items-center justify-between">
              <div className="text-lg font-black">⚔️ Дуэль недели</div>
              <div className="rounded-full bg-black/25 px-3 py-1 text-xs font-bold">{stage === "pending" ? "Ждём ответа" : "Осталось 3 дня"}</div>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex flex-col items-center gap-1"><Avatar name="somon" color="#5862dd" /><span className="text-sm font-bold">somon</span></div>
              <div className="text-center">
                <div className="text-3xl font-black">{stage === "pending" ? "—" : `${308} : ${204}`}</div>
                <div className="text-xs text-white/70">энергия за неделю</div>
              </div>
              <div className="flex flex-col items-center gap-1"><Avatar name="vaygo" color="#c2185b" /><span className="text-sm font-bold">vaygo</span></div>
            </div>
            {stage === "active" && (
              <div className="mt-3 h-3 overflow-hidden rounded-full bg-black/30"><div style={{ width: "60%", height: "100%", background: "linear-gradient(90deg,#ffe56b,#ffab1a)" }} /></div>
            )}
            <div className="mt-4 rounded-2xl p-3" style={{ background: "linear-gradient(180deg,rgba(255,213,79,0.22),rgba(255,171,26,0.1))", boxShadow: "inset 0 0 0 1px rgba(255,213,79,0.5)" }}>
              <div className="mb-2 text-center text-xs font-black uppercase tracking-wide" style={{ color: "#ffd54f" }}>🏆 Победитель получит</div>
              <Rewards list={rules.duel_win} big />
              {rules.duel_draw.length > 0 && <div className="mt-2 flex items-center justify-center gap-2 text-xs text-white/70">Ничья: <Rewards list={rules.duel_draw} /></div>}
            </div>
          </div>
        )}

        {stage === "done" && (
          <div className={shell} style={bg}>
            <div className="mb-1 text-center text-2xl font-black" style={{ color: outcome === "win" ? "#ffd54f" : "#fff" }}>
              {outcome === "win" ? "🏆 Победа!" : outcome === "draw" ? "🤝 Ничья" : "Дуэль окончена"}
            </div>
            <div className="mb-3 flex items-center justify-between">
              <div className="flex flex-col items-center gap-1"><span style={{ filter: outcome === "lose" ? "grayscale(0.6)" : undefined }}><Avatar name="somon" color="#5862dd" /></span><span className="text-sm font-bold">somon</span></div>
              <div className="text-center"><div className="text-3xl font-black">{mine} : {theirs}</div><div className="text-xs text-white/70">итоговая энергия</div></div>
              <div className="flex flex-col items-center gap-1"><span style={{ filter: outcome === "win" ? "grayscale(0.6)" : undefined }}><Avatar name="vaygo" color="#c2185b" /></span><span className="text-sm font-bold">vaygo</span></div>
            </div>
            <div className="rounded-2xl bg-black/20 p-3">
              <div className="mb-2 text-center text-xs font-black uppercase tracking-wide text-white/70">Ваша награда</div>
              <Rewards list={rules[key]} big />
              {outcome === "lose" && <p className="mt-2 text-center text-xs text-white/70">В этот раз без награды. Отыграйтесь в следующей дуэли!</p>}
            </div>
            <button className="mt-4 w-full rounded-xl px-4 py-3 text-sm font-black uppercase" style={green}>Новая дуэль</button>
            <button className="mt-2 w-full rounded-xl bg-white/10 px-4 py-2 text-sm font-bold text-white/80">Закрыть</button>
          </div>
        )}
      </section>
    </main>
  );
}

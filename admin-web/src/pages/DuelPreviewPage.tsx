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


const Bolt = ({ size }: { size: number }) => <img src={`${import.meta.env.BASE_URL}preview/energy.png`} alt="" draggable={false} style={{ width: size, height: size, objectFit: "contain" }} />;

export function Reward({ r, big = false, tone = "gold" }: { r: EventReward; big?: boolean; tone?: "gold" | "silver" }) {
  const side = big ? 52 : 44;
  const icon = side - 12;
  const frame = tone === "gold" ? "rgba(255,213,79,0.85)" : "rgba(200,210,235,0.7)";
  const slot = {
    width: side, height: side, borderRadius: 14, position: "relative", flexShrink: 0, display: "inline-flex", alignItems: "center", justifyContent: "center",
    background: "radial-gradient(circle at 50% 35%, rgba(255,255,255,0.18), rgba(10,6,40,0.55))",
    boxShadow: `inset 0 0 0 2px ${frame}, 0 3px 6px rgba(0,0,0,0.35)`,
  } as const;
  const plate = (text: string) => (
    <span style={{ position: "absolute", right: -5, bottom: -5, minWidth: 18, padding: "1px 5px", borderRadius: 99, background: "#1b1247", boxShadow: `0 0 0 1.5px ${frame}`, color: "#fff", fontWeight: 900, fontSize: 11, lineHeight: "14px", textAlign: "center" }}>{text}</span>
  );
  const img = (src: string) => <img src={src} alt="" draggable={false} style={{ width: icon, height: icon, objectFit: "contain" }} />;
  if (r.type === "chest") return <span style={slot}>{img(`${BASE}chests/${r.key ?? "wood"}_closed.png`)}{r.amount > 1 && plate(`${r.amount}`)}</span>;
  if (r.type === "diamonds") return <span style={slot}>{img(`${BASE}preview/gem.png`)}{plate(`${r.amount}`)}</span>;
  if (r.type === "rating_points") return <span style={slot}>{img(`${BASE}preview/points.png`)}{plate(`${r.amount}`)}</span>;
  return <span style={slot}><Bolt size={icon - 4} />{plate(`${r.amount}`)}</span>;
}

export function Rewards({ list, big, tone }: { list: EventReward[]; big?: boolean; tone?: "gold" | "silver" }) {
  if (!list.length)
    return <span style={{ width: big ? 52 : 44, height: big ? 52 : 44, borderRadius: 14, display: "inline-flex", alignItems: "center", justifyContent: "center", flexShrink: 0, color: "rgba(255,255,255,0.4)", fontSize: 22, boxShadow: "inset 0 0 0 2px rgba(255,255,255,0.18)", opacity: 0.7 }}>✕</span>;
  return <span className="flex flex-nowrap items-center gap-2 pr-1" style={{ whiteSpace: "nowrap" }}>{list.map((r, i) => <Reward key={i} r={r} big={big} tone={tone} />)}</span>;
}

/** One line that scrolls sideways when it does not fit, so the card never grows taller. */
function Row({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2 overflow-x-auto py-1.5 pr-2" style={{ scrollbarWidth: "none", WebkitOverflowScrolling: "touch" }}>
      {children}
    </div>
  );
}

function Avatar({ name, color }: { name: string; color: string }) {
  return <span className="flex items-center justify-center rounded-full text-base font-black text-white" style={{ width: 40, height: 40, background: color, boxShadow: "0 0 0 2px rgba(255,255,255,0.35)" }}>{name[0].toUpperCase()}</span>;
}

export const green = {
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
  const shell = "mx-auto w-full max-w-xs rounded-2xl p-3 text-white";
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
            <div className="mb-1 text-base font-black">⚔️ Дуэль недели</div>
            <p className="mb-2 text-xs text-white/80">Вызовите друга: кто за неделю наберёт больше энергии, тот победил.</p>
            <div className="mb-2 rounded-xl bg-black/20 px-2 py-1.5">
              <Row>
                <span className="shrink-0 text-2xl" title="Победа">🏆</span>
                <Rewards list={rules.duel_win} tone="gold" />
                <span className="shrink-0 text-white/30">|</span>
                <span className="shrink-0 text-2xl" title="Ничья">🤝</span>
                <Rewards list={rules.duel_draw} tone="silver" />
              </Row>
            </div>
            <button className="w-full rounded-xl px-4 py-2 text-sm font-black uppercase" style={green}>Вызвать друга</button>
          </div>
        )}

        {(stage === "pending" || stage === "active") && (
          <div className={shell} style={bg}>
            <div className="mb-2 flex items-center justify-between">
              <div className="text-base font-black">⚔️ Дуэль недели</div>
              <div className="rounded-full bg-black/25 px-2 py-0.5 text-[11px] font-bold">{stage === "pending" ? "Ждём ответа" : "Осталось 3 дня"}</div>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex flex-col items-center gap-1"><Avatar name="somon" color="#5862dd" /><span className="text-sm font-bold">somon</span></div>
              <div className="text-center">
                <div className="text-2xl font-black">{stage === "pending" ? "—" : `${308} : ${204}`}</div>
                <div className="text-xs text-white/70">энергия за неделю</div>
              </div>
              <div className="flex flex-col items-center gap-1"><Avatar name="vaygo" color="#c2185b" /><span className="text-sm font-bold">vaygo</span></div>
            </div>
            {stage === "active" && (
              <div className="mt-2 h-2 overflow-hidden rounded-full bg-black/30"><div style={{ width: "60%", height: "100%", background: "linear-gradient(90deg,#ffe56b,#ffab1a)" }} /></div>
            )}
            <div className="mt-2 rounded-xl px-2 py-1.5" style={{ background: "linear-gradient(180deg,rgba(255,213,79,0.22),rgba(255,171,26,0.1))", boxShadow: "inset 0 0 0 1px rgba(255,213,79,0.5)" }}>
              <Row>
                <span className="shrink-0 text-2xl" title="Победа">🏆</span>
                <Rewards list={rules.duel_win} big tone="gold" />
                {rules.duel_draw.length > 0 && <>
                  <span className="shrink-0 text-white/30">|</span>
                  <span className="shrink-0 text-2xl" title="Ничья">🤝</span>
                  <Rewards list={rules.duel_draw} big tone="silver" />
                </>}
              </Row>
            </div>
          </div>
        )}

        {stage === "done" && (
          <div className={shell} style={bg}>
            <div className="mb-1 text-center text-xl font-black" style={{ color: outcome === "win" ? "#ffd54f" : "#fff" }}>
              {outcome === "win" ? "🏆 Победа!" : outcome === "draw" ? "🤝 Ничья" : "Дуэль окончена"}
            </div>
            <div className="mb-2 flex items-center justify-between">
              <div className="flex flex-col items-center gap-1"><span style={{ filter: outcome === "lose" ? "grayscale(0.6)" : undefined }}><Avatar name="somon" color="#5862dd" /></span><span className="text-sm font-bold">somon</span></div>
              <div className="text-center"><div className="text-2xl font-black">{mine} : {theirs}</div><div className="text-xs text-white/70">итоговая энергия</div></div>
              <div className="flex flex-col items-center gap-1"><span style={{ filter: outcome === "win" ? "grayscale(0.6)" : undefined }}><Avatar name="vaygo" color="#c2185b" /></span><span className="text-sm font-bold">vaygo</span></div>
            </div>
            <div className="rounded-xl bg-black/20 px-2 py-0.5">
              <Row>
                <span className="shrink-0 text-2xl">{outcome === "win" ? "🏆" : outcome === "draw" ? "🤝" : "🎯"}</span>
                <Rewards list={rules[key]} big tone={outcome === "win" ? "gold" : "silver"} />
              </Row>
              
            </div>
            <button className="mt-3 w-full rounded-xl px-4 py-2 text-sm font-black uppercase" style={green}>Новая дуэль</button>
            <button className="mt-1.5 w-full rounded-xl bg-white/10 px-4 py-1.5 text-xs font-bold text-white/80">Закрыть</button>
          </div>
        )}
      </section>
    </main>
  );
}

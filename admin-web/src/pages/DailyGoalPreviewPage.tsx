import { useEffect, useState } from "react";
import { getRewardRules, type GoalTier } from "../api/endpoints";
import { Rewards, green } from "./DuelPreviewPage";

// A preview only: how the daily goal shows its reward and how the person takes it.
// Nothing is sent to the server; the tiers come from «Сундуки» → «Цель дня».

const DEFAULT_TIERS: GoalTier[] = [
  { words: 5, rewards: [{ type: "xp", amount: 10 }] },
  { words: 10, rewards: [{ type: "xp", amount: 15 }, { type: "chest", key: "wood", amount: 1 }] },
  { words: 20, rewards: [{ type: "xp", amount: 25 }, { type: "chest", key: "silver", amount: 1 }] },
];
type Stage = "going" | "ready" | "sheet" | "notice" | "taken";

const css = `
@keyframes dg-pulse { 0%,100% { transform: scale(1); box-shadow: 0 0 0 0 rgba(255,213,79,0.7); } 50% { transform: scale(1.12); box-shadow: 0 0 0 8px rgba(255,213,79,0); } }
@keyframes dg-rays { from { transform: translate(-50%,-50%) rotate(0); } to { transform: translate(-50%,-50%) rotate(360deg); } }
@keyframes dg-gift { 0% { transform: translate(-50%,-50%) scale(0.2) rotate(-20deg); opacity: 0; } 35% { transform: translate(-50%,-50%) scale(1.25) rotate(8deg); opacity: 1; } 55% { transform: translate(-50%,-50%) scale(1) rotate(-3deg); } 70% { transform: translate(-50%,-50%) scale(1.05) rotate(2deg); } 100% { transform: translate(-50%,-80%) scale(0.7); opacity: 0; } }
@keyframes dg-pop { 0% { transform: translateY(18px) scale(0.3); opacity: 0; } 70% { transform: translateY(-4px) scale(1.15); opacity: 1; } 100% { transform: translateY(0) scale(1); opacity: 1; } }
@keyframes dg-flash { 0% { opacity: 0.9; transform: translate(-50%,-50%) scale(0.3); } 100% { opacity: 0; transform: translate(-50%,-50%) scale(2.6); } }
@keyframes dg-spark { 0% { opacity: 1; transform: translate(0,0) scale(0.5); } 100% { opacity: 0; transform: translate(var(--dx), var(--dy)) scale(1.1); } }
`;

export function DailyGoalPreviewPage() {
  const [tiers, setTiers] = useState<GoalTier[]>(DEFAULT_TIERS);
  const [stage, setStage] = useState<Stage>("going");
  const [chosen, setChosen] = useState(10);
  const [effect, setEffect] = useState(0); // restarts the reward effect
  const [showEffect, setShowEffect] = useState(false);
  useEffect(() => {
    getRewardRules().then((r) => { if (Array.isArray(r.daily_goal) && r.daily_goal.length) setTiers(r.daily_goal as GoalTier[]); }).catch(() => undefined);
  }, []);
  const tier = tiers.find((t) => t.words === chosen) ?? tiers[0];
  const done = stage !== "going";

  const claim = () => { setShowEffect(true); setEffect((e) => e + 1); window.setTimeout(() => { setShowEffect(false); setStage("taken"); }, 3200); };
  const shell = "mx-auto w-full max-w-sm";
  const card = (extra: string) => `relative rounded-2xl p-3 ${extra}`;
  const chip = (s: Stage, label: string) => (
    <button key={s} type="button" onClick={() => { setShowEffect(false); setStage(s); }} className={`rounded-lg px-3 py-1.5 text-sm ${stage === s ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>{label}</button>
  );
  const sparks = Array.from({ length: 18 }, (_, i) => { const a = (i / 18) * Math.PI * 2; const d = 110 + (i % 3) * 30; return { dx: Math.cos(a) * d, dy: Math.sin(a) * d }; });

  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр цели дня</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. Награда за цель больше не выдаётся сама: когда цель выполнена, на карточке метка «награда ждёт», а забрать её можно кнопкой «Получить».
          Если не забрали до конца суток, награда приходит в уведомления с той же кнопкой.
        </p>
      </header>

      <section className="card space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500">Состояние:</span>
          {chip("going", "Идёт")}{chip("ready", "Выполнена, награда ждёт")}{chip("sheet", "Выбор цели")}{chip("notice", "Уведомление на следующий день")}{chip("taken", "Награда получена")}
        </div>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500">Моя цель:</span>
          {tiers.map((t) => (
            <button key={t.words} type="button" onClick={() => setChosen(t.words)} className={`rounded-lg px-3 py-1.5 text-sm ${chosen === t.words ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>{t.words} слов</button>
          ))}
        </div>
      </section>

      <section className="relative overflow-hidden rounded-3xl p-5" style={{ background: "#0d0f1c", minHeight: 420 }}>
        {stage !== "notice" && (
          <div className={shell}>
            <div className={card("")} style={{ background: "#12151f", boxShadow: `inset 0 0 0 1.5px ${done && stage !== "taken" ? "#ffd54f" : done ? "#2ecc71" : "rgba(124,132,240,0.45)"}` }}>
              {/* the "reward is waiting" mark on the card's corner */}
              {stage !== "going" && stage !== "taken" && (
                <span style={{ position: "absolute", top: -10, right: 12, width: 30, height: 30, borderRadius: 99, display: "flex", alignItems: "center", justifyContent: "center", background: "linear-gradient(180deg,#ffe56b,#ffab1a)", fontSize: 17, animation: "dg-pulse 1.6s ease-in-out infinite", boxShadow: "0 3px 0 #b36a00" }}>🎁</span>
              )}
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="text-lg font-black text-white/90">Цель дня</div>
                  <div className="text-xs text-white/60">
                    {stage === "going" ? `3 из ${tier.words} слов` : stage === "taken" ? "Награда получена. Новую цель выберете завтра" : "Выполнена! Заберите награду"}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-2xl font-black" style={{ color: done ? "#2ecc71" : "#7c84f0" }}>{done ? "100%" : `${Math.round((3 / tier.words) * 100)}%`}</span>
                  <span className="flex h-10 w-10 items-center justify-center rounded-full text-lg text-white" style={{ background: done ? "#1f9d62" : "#5862dd" }}>{done ? "✓" : "›"}</span>
                </div>
              </div>
              {stage === "ready" && (
                <div className="mt-2 flex items-center gap-2">
                  <div className="min-w-0 flex-1 overflow-x-auto pb-2 pr-2" style={{ scrollbarWidth: "none" }}><Rewards list={tier.rewards} tone="gold" /></div>
                  <button className="shrink-0 rounded-xl px-4 py-2 text-sm font-black uppercase" style={green} onClick={claim}>Получить</button>
                </div>
              )}
            </div>
          </div>
        )}

        {stage === "sheet" && (
          <div className={`${shell} mt-4 rounded-2xl p-4`} style={{ background: "#1a1d2c", boxShadow: "0 -8px 30px rgba(0,0,0,0.4)" }}>
            <div className="mb-3 text-center text-lg font-black text-white">Сколько слов в день?</div>
            <div className="space-y-2">
              {tiers.map((t) => {
                const mine = t.words === chosen;
                return (
                  <div key={t.words} className="flex items-center gap-2 rounded-xl px-3 py-2" style={{ background: mine ? "rgba(255,213,79,0.12)" : "rgba(255,255,255,0.05)", boxShadow: mine ? "inset 0 0 0 1.5px rgba(255,213,79,0.6)" : undefined }}>
                    <div className="w-16 shrink-0 font-bold text-white">{t.words} слов</div>
                    <div className="min-w-0 flex-1 overflow-x-auto pb-2 pr-2" style={{ scrollbarWidth: "none" }}><Rewards list={t.rewards} tone={mine ? "gold" : "silver"} /></div>
                    {mine ? <button className="shrink-0 rounded-xl px-3 py-1.5 text-xs font-black uppercase" style={green} onClick={claim}>Получить</button> : <span className="w-7 shrink-0 text-center text-white/30">○</span>}
                  </div>
                );
              })}
            </div>
            <p className="mt-2 text-center text-[11px] text-white/50">Выполненная цель закрыта до завтра: другую выбрать нельзя.</p>
          </div>
        )}

        {stage === "notice" && (
          <div className={shell}>
            <div className="mb-2 text-xs font-bold uppercase tracking-wide text-white/50">Уведомления</div>
            <div className="rounded-2xl p-3" style={{ background: "#151a2b", boxShadow: "inset 0 0 0 1px rgba(255,213,79,0.4)" }}>
              <div className="flex items-start gap-3">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-xl" style={{ background: "linear-gradient(180deg,#ffe56b,#ffab1a)" }}>🎁</span>
                <div className="min-w-0 flex-1">
                  <div className="font-black text-white">Награда за цель дня ждёт вас</div>
                  <div className="text-xs text-white/60">Вчера вы выполнили цель: {tier.words} слов. Заберите подарок!</div>
                  <div className="mt-2 overflow-x-auto pb-2 pr-2" style={{ scrollbarWidth: "none" }}><Rewards list={tier.rewards} tone="gold" /></div>
                  <button className="mt-2 w-full rounded-xl px-4 py-2 text-sm font-black uppercase" style={green} onClick={claim}>Получить</button>
                </div>
              </div>
            </div>
          </div>
        )}

        {showEffect && (
          <div key={effect} className="absolute inset-0 overflow-hidden" style={{ background: "radial-gradient(circle at 50% 50%, rgba(20,16,58,0.9), rgba(8,6,28,0.97))" }}>
            <div className="absolute left-1/2 top-1/2" style={{ width: 520, height: 520, borderRadius: "50%", background: "repeating-conic-gradient(from 0deg, rgba(255,226,140,0.5) 0deg 9deg, rgba(255,226,140,0) 9deg 22deg)", WebkitMaskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)", maskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)", animation: "dg-rays 14s linear infinite" }} />
            <div className="absolute left-1/2 top-1/2 text-center" style={{ fontSize: 110, lineHeight: 1, animation: "dg-gift 1.3s ease-in-out both", filter: "drop-shadow(0 10px 20px rgba(0,0,0,0.5))" }}>🎁</div>
            <div className="absolute left-1/2 top-1/2" style={{ width: 360, height: 360, borderRadius: "50%", background: "radial-gradient(closest-side,#fff,rgba(255,240,180,0.7) 45%,rgba(255,240,180,0))", animation: "dg-flash .9s ease-out 1s both", opacity: 0 }} />
            {sparks.map((s, i) => <span key={i} className="absolute rounded-full" style={{ left: "50%", top: "50%", width: 8, height: 8, background: "#fff4c2", boxShadow: "0 0 10px 3px rgba(255,214,102,0.9)", ["--dx" as string]: `${s.dx}px`, ["--dy" as string]: `${s.dy}px`, animation: `dg-spark 1.1s ease-out ${1 + (i % 4) * 0.05}s both`, opacity: 0 }} />)}
            <div className="absolute left-0 right-0 text-center" style={{ top: "30%", color: "#ffd54f", fontWeight: 900, letterSpacing: 2, animation: "dg-pop .6s ease-out 1.1s both", opacity: 0 }}>ЦЕЛЬ ДНЯ ВЫПОЛНЕНА!</div>
            <div className="absolute left-0 right-0 flex justify-center" style={{ top: "46%", animation: "dg-pop .7s ease-out 1.3s both", opacity: 0, transform: "scale(1.5)", transformOrigin: "top center" }}>
              <Rewards list={tier.rewards} big tone="gold" />
            </div>
            <div className="absolute left-0 right-0 text-center text-sm text-white/70" style={{ bottom: 24, animation: "dg-pop .5s ease-out 2s both", opacity: 0 }}>Награда зачислена</div>
          </div>
        )}
      </section>
    </main>
  );
}

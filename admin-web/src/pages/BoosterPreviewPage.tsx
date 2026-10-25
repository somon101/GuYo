import { useEffect, useRef, useState } from "react";
import { green } from "./DuelPreviewPage";

// A preview only: the "x2" ticket as an item the person keeps and switches on when they want.
// Nothing is sent anywhere. Real durations and where it is given are set in the admin later.

const BASE = `${import.meta.env.BASE_URL}`;
const VARIANTS = [
  { minutes: 30, short: "30м", label: "30 минут" },
  { minutes: 60, short: "1ч", label: "1 час" },
  { minutes: 1440, short: "24ч", label: "24 часа" },
];

const css = `
@keyframes bp-rays { from { transform: translate(-50%,-50%) rotate(0); } to { transform: translate(-50%,-50%) rotate(360deg); } }
@keyframes bp-icon { 0% { transform: translate(-50%,-50%) scale(0.2) rotate(-20deg); opacity: 0; } 45% { transform: translate(-50%,-50%) scale(1.3) rotate(8deg); opacity: 1; } 70% { transform: translate(-50%,-50%) scale(1) rotate(-3deg); } 100% { transform: translate(-50%,-50%) scale(1.05) rotate(0); opacity: 1; } }
@keyframes bp-pop { 0% { transform: translateY(16px) scale(0.4); opacity: 0; } 70% { transform: translateY(-3px) scale(1.1); opacity: 1; } 100% { transform: translateY(0) scale(1); opacity: 1; } }
@keyframes bp-flash { 0% { opacity: 0.9; transform: translate(-50%,-50%) scale(0.3); } 100% { opacity: 0; transform: translate(-50%,-50%) scale(2.6); } }
@keyframes bp-glow { 0%,100% { box-shadow: 0 0 0 0 rgba(255,213,79,0.55); } 50% { box-shadow: 0 0 14px 4px rgba(255,213,79,0.45); } }
@keyframes bp-plus { 0% { opacity: 0; transform: translateY(8px); } 25% { opacity: 1; } 100% { opacity: 0; transform: translateY(-16px); } }
`;

function fmt(sec: number): string {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  const two = (n: number) => String(n).padStart(2, "0");
  return h ? `${h}:${two(m)}:${two(s)}` : `${two(m)}:${two(s)}`;
}

/** The ticket in a reward slot: the picture, with the duration on a plate at the corner. */
function BoosterSlot({ short, size = 52 }: { short: string; size?: number }) {
  return (
    <span style={{ position: "relative", width: size, height: size, borderRadius: 14, display: "inline-flex", alignItems: "center", justifyContent: "center", flexShrink: 0, background: "radial-gradient(circle at 50% 35%, rgba(255,255,255,0.18), rgba(10,6,40,0.55))", boxShadow: "inset 0 0 0 2px rgba(255,213,79,0.85), 0 3px 6px rgba(0,0,0,0.35)" }}>
      <img src={`${BASE}preview/booster.png`} alt="" draggable={false} style={{ width: size - 6, height: size - 6, objectFit: "contain" }} />
      <span style={{ position: "absolute", right: -5, bottom: -5, minWidth: 22, padding: "1px 5px", borderRadius: 99, background: "#1b1247", boxShadow: "0 0 0 1.5px rgba(255,213,79,0.85)", color: "#fff", fontWeight: 900, fontSize: 11, lineHeight: "14px", textAlign: "center" }}>{short}</span>
    </span>
  );
}

export function BoosterPreviewPage() {
  const [counts, setCounts] = useState<Record<number, number>>({ 30: 2, 60: 1, 1440: 1 });
  const [left, setLeft] = useState(0); // seconds of the double reward still running
  const [effect, setEffect] = useState<{ minutes: number; key: number } | null>(null);
  const [bonus, setBonus] = useState(0);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    if (left <= 0) { if (timer.current) window.clearInterval(timer.current); timer.current = null; return; }
    if (!timer.current) timer.current = window.setInterval(() => setLeft((v) => Math.max(0, v - 1)), 1000);
  }, [left]);
  useEffect(() => () => { if (timer.current) window.clearInterval(timer.current); }, []);

  const activate = (minutes: number) => {
    if ((counts[minutes] ?? 0) < 1) return;
    setCounts({ ...counts, [minutes]: counts[minutes] - 1 });
    setLeft((v) => v + minutes * 60); // time adds up when one is already running
    setBonus((b) => b + 1);
    setEffect({ minutes, key: Date.now() });
    window.setTimeout(() => setEffect(null), 2600);
  };
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  const shell = "mx-auto w-full max-w-sm rounded-2xl p-3 text-white";
  const bg = { background: "linear-gradient(135deg,#3d2b8f,#1e1560)", boxShadow: "0 18px 40px rgba(30,20,90,0.35)" };

  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр удвоителя наград</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. Билет «x2» лежит у игрока в инвентаре (30 минут, 1 час, 24 часа). Игрок включает его сам; пока идёт время, награды удваиваются.
          Второй билет, включённый во время действия первого, прибавляет своё время.
        </p>
      </header>

      <section className="relative overflow-hidden rounded-3xl p-5" style={{ background: "#0d0f1c", minHeight: 520 }}>
        <div className={shell} style={bg}>
          <div className="mb-2 flex items-center justify-between">
            <div className="text-base font-black">Мои бонусы · {total}</div>
            {left > 0 && (
              <div key={bonus} className="flex items-center gap-1.5 rounded-full px-2.5 py-1" style={{ background: "rgba(0,0,0,0.3)", animation: "bp-glow 1.8s ease-in-out infinite", boxShadow: "inset 0 0 0 1.5px rgba(255,213,79,0.8)" }}>
                <img src={`${BASE}preview/booster.png`} alt="" style={{ width: 22, height: 22, objectFit: "contain" }} />
                <span className="text-sm font-black tabular-nums" style={{ color: "#ffd54f" }}>{fmt(left)}</span>
              </div>
            )}
          </div>
          {left === 0 && <p className="mb-2 text-xs text-white/60">Включите билет, чтобы все награды удваивались, пока идёт время.</p>}
          <div className="space-y-2">
            {VARIANTS.map((v) => {
              const n = counts[v.minutes] ?? 0;
              return (
                <div key={v.minutes} className="flex items-center gap-3 rounded-2xl bg-white/10 p-2" style={{ opacity: n ? 1 : 0.5 }}>
                  <span style={{ position: "relative", width: 56, height: 56, flexShrink: 0 }}>
                    <img src={`${BASE}preview/booster.png`} alt="" draggable={false} style={{ width: 56, height: 56, objectFit: "contain" }} />
                    <span style={{ position: "absolute", left: "80%", top: "76%", transform: "translate(-50%,-50%)", minWidth: 22, padding: "3px 6px", borderRadius: 99, background: "#1b1247", boxShadow: "0 0 0 2px #ffc928, 0 2px 4px rgba(0,0,0,0.5)", fontWeight: 900, fontSize: 13, lineHeight: 1, textAlign: "center" }}>{n}</span>
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-black">{v.label}</div>
                    <div className="text-xs text-white/60">награды ×2</div>
                  </div>
                  <button disabled={!n} onClick={() => activate(v.minutes)} className="shrink-0 rounded-xl px-3 py-2 text-xs font-black uppercase disabled:opacity-40" style={green}>
                    Включить
                  </button>
                </div>
              );
            })}
          </div>
          {left > 0 && <p className="mt-2 text-center text-[11px] text-white/60">Идёт удвоение. Ещё один билет прибавит время.</p>}
        </div>

        <div className={`${shell} mt-4`} style={{ background: "#12151f" }}>
          <div className="mb-2 text-xs font-bold uppercase tracking-wide text-white/50">Как билет выглядит в наградах</div>
          <div className="flex flex-wrap items-center gap-3 pb-1">
            <BoosterSlot short="30м" /><BoosterSlot short="1ч" /><BoosterSlot short="24ч" />
          </div>
          <p className="mt-2 text-[11px] text-white/50">Награда пропуска, приз из сундука, награда за цель дня, дуэль и серию: везде тот же слот.</p>
        </div>

        {effect && (
          <div key={effect.key} className="absolute inset-0 overflow-hidden" style={{ background: "radial-gradient(circle at 50% 50%, rgba(20,16,58,0.92), rgba(8,6,28,0.97))" }}>
            <div className="absolute left-1/2 top-1/2" style={{ width: 520, height: 520, borderRadius: "50%", background: "repeating-conic-gradient(from 0deg, rgba(255,226,140,0.5) 0deg 9deg, rgba(255,226,140,0) 9deg 22deg)", WebkitMaskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)", maskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)", animation: "bp-rays 14s linear infinite" }} />
            <img src={`${BASE}preview/booster.png`} alt="" className="absolute left-1/2 top-1/2" style={{ width: 190, height: 190, maxWidth: "none", objectFit: "contain", animation: "bp-icon 1s cubic-bezier(.2,.9,.3,1.1) both", filter: "drop-shadow(0 10px 22px rgba(0,0,0,0.5))" }} />
            <div className="absolute left-1/2 top-1/2" style={{ width: 380, height: 380, borderRadius: "50%", background: "radial-gradient(closest-side,#fff,rgba(255,240,180,0.7) 45%,rgba(255,240,180,0))", animation: "bp-flash .9s ease-out .35s both", opacity: 0 }} />
            <div className="absolute left-0 right-0 text-center" style={{ top: "16%", color: "#ffd54f", fontWeight: 900, letterSpacing: 2, fontSize: 18, animation: "bp-pop .6s ease-out .5s both", opacity: 0 }}>НАГРАДЫ ×2</div>
            <div className="absolute left-0 right-0 text-center" style={{ bottom: "13%", animation: "bp-pop .6s ease-out .8s both", opacity: 0 }}>
              <div style={{ color: "#fff", fontWeight: 900, fontSize: 22 }}>Включено на {VARIANTS.find((v) => v.minutes === effect.minutes)?.label}</div>
              {left > effect.minutes * 60 && <div style={{ color: "#a7f3d0", fontSize: 13, marginTop: 2 }}>Время прибавилось к уже идущему</div>}
            </div>
          </div>
        )}
      </section>

      <section className="card flex flex-wrap items-center gap-2 p-4 text-sm">
        <button type="button" className="rounded-lg border border-slate-300 px-3 py-1.5 text-slate-700" onClick={() => setCounts({ 30: 2, 60: 1, 1440: 1 })}>Вернуть билеты</button>
        <button type="button" className="rounded-lg border border-slate-300 px-3 py-1.5 text-slate-700" onClick={() => { setLeft(0); setBonus(0); }}>Остановить удвоение</button>
        <span className="text-xs text-slate-500">Обратный отсчёт идёт по-настоящему: можно подождать и убедиться.</span>
      </section>
    </main>
  );
}

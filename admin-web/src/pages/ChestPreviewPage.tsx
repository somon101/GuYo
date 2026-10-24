import { useEffect, useMemo, useRef, useState } from "react";

// A preview only: nothing here talks to the server or the app. It shows how a
// chest picture (public/preview/chest_closed.png + chest_open.png) comes alive:
// it floats, shakes when pressed, bursts open with light and throws out rewards.

type Tier = "small" | "medium" | "large";
type Phase = "idle" | "shaking" | "open";

const TIERS: Record<Tier, { label: string; amount: number; items: { icon: string; count: number }[] }> = {
  small: { label: "Малая", amount: 10, items: [{ icon: "💎", count: 3 }] },
  medium: {
    label: "Средняя",
    amount: 50,
    items: [
      { icon: "💎", count: 6 },
      { icon: "🪙", count: 4 },
      { icon: "❄️", count: 1 },
    ],
  },
  large: {
    label: "Большая",
    amount: 150,
    items: [
      { icon: "💎", count: 9 },
      { icon: "🪙", count: 7 },
      { icon: "❄️", count: 2 },
      { icon: "🔥", count: 1 },
    ],
  },
};

const SHAKE_MS = 750;
const BASE = `${import.meta.env.BASE_URL}preview/`;

const css = `
@keyframes cp-float { 0%,100% { transform: translateY(0) rotate(-0.6deg) scale(1); } 50% { transform: translateY(-9px) rotate(0.6deg) scale(1.015); } }
@keyframes cp-shake {
  0% { transform: translate(0,0) rotate(0) scale(1); }
  12% { transform: translate(-6px,2px) rotate(-5deg) scale(1.02); }
  26% { transform: translate(7px,-2px) rotate(5deg) scale(1.04); }
  40% { transform: translate(-8px,2px) rotate(-6deg) scale(1.06); }
  54% { transform: translate(8px,-2px) rotate(6deg) scale(1.07); }
  70% { transform: translate(-6px,1px) rotate(-4deg) scale(1.08); }
  85% { transform: translate(4px,0) rotate(3deg) scale(1.09); }
  100% { transform: translate(0,0) rotate(0) scale(1.1); }
}
@keyframes cp-pop { 0% { transform: scale(1.1); } 35% { transform: scale(0.94); } 65% { transform: scale(1.07); } 100% { transform: scale(1); } }
@keyframes cp-flash { 0% { opacity: 0.95; transform: scale(0.4); } 100% { opacity: 0; transform: scale(2.4); } }
@keyframes cp-rays { from { transform: translate(-50%,-50%) rotate(0deg); } to { transform: translate(-50%,-50%) rotate(360deg); } }
@keyframes cp-rays-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes cp-spark { 0% { opacity: 1; transform: translate(0,0) scale(0.4); } 100% { opacity: 0; transform: translate(var(--dx), var(--dy)) scale(1.2); } }
@keyframes cp-loot {
  0% { opacity: 0; transform: translate(0,0) scale(0.2); }
  15% { opacity: 1; }
  60% { transform: translate(var(--dx), var(--up)) scale(1.15); }
  100% { opacity: 1; transform: translate(var(--dx), var(--dy)) scale(1); }
}
@keyframes cp-bob { 0%,100% { margin-top: 0; } 50% { margin-top: -6px; } }
@keyframes cp-label { 0% { opacity: 0; transform: translateY(14px) scale(0.7); } 100% { opacity: 1; transform: translateY(0) scale(1); } }
@keyframes cp-glow { 0%,100% { opacity: 0.35; } 50% { opacity: 0.6; } }
`;

export function ChestPreviewPage() {
  const [tier, setTier] = useState<Tier>("medium");
  const [phase, setPhase] = useState<Phase>("idle");
  const [run, setRun] = useState(0); // restarts the CSS animations on every opening
  const timer = useRef<number | null>(null);

  useEffect(() => () => { if (timer.current) window.clearTimeout(timer.current); }, []);

  const loot = useMemo(() => {
    const out: { icon: string; dx: number; dy: number; up: number; delay: number; size: number }[] = [];
    const list = TIERS[tier].items.flatMap((it) => Array.from({ length: it.count }, () => it.icon));
    list.forEach((icon, i) => {
      const angle = ((i + 0.5) / list.length) * Math.PI - Math.PI; // a fan above the chest
      const spread = 120 + (i % 3) * 22;
      out.push({
        icon,
        dx: Math.cos(angle) * spread * 1.15,
        dy: -Math.abs(Math.sin(angle)) * spread * 0.7 - 70,
        up: -Math.abs(Math.sin(angle)) * spread * 0.7 - 150,
        delay: 0.05 * i,
        size: icon === "💎" ? 38 : 32,
      });
    });
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tier, run]);

  const sparks = useMemo(
    () =>
      Array.from({ length: 16 }, (_, i) => {
        const a = (i / 16) * Math.PI * 2 + Math.random() * 0.4;
        const d = 110 + Math.random() * 90;
        return { dx: Math.cos(a) * d, dy: Math.sin(a) * d - 40, delay: Math.random() * 0.12, s: 6 + Math.random() * 8 };
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [run],
  );

  const open = () => {
    if (phase !== "idle") return;
    setRun((n) => n + 1);
    setPhase("shaking");
    timer.current = window.setTimeout(() => setPhase("open"), SHAKE_MS);
  };
  const reset = () => {
    if (timer.current) window.clearTimeout(timer.current);
    setPhase("idle");
  };

  const t = TIERS[tier];
  const isOpen = phase === "open";

  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр сундука</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ: как картинка сундука оживает. Нажмите на сундук или кнопку «Открыть». Ни приложение, ни сервер, ни
          награды этим не затрагиваются.
        </p>
      </header>

      <section
        className="relative mx-auto overflow-hidden rounded-3xl"
        style={{
          height: 560,
          background: "radial-gradient(ellipse at 50% 70%, #5b3fd0 0%, #2a1f6b 55%, #150f3a 100%)",
          boxShadow: "0 18px 50px rgba(30,20,90,0.35)",
        }}
      >
        {/* soft light under the chest */}
        <div
          className="absolute left-1/2 rounded-full"
          style={{ top: 360, width: 360, height: 90, transform: "translateX(-50%)", background: "radial-gradient(closest-side, rgba(255,214,120,0.5), rgba(255,214,120,0))", animation: isOpen ? "cp-glow 1.6s ease-in-out infinite" : undefined, opacity: isOpen ? 1 : 0.25 }}
        />

        {/* rotating rays behind the opened chest */}
        {isOpen && (
          <div
            key={`rays-${run}`}
            className="absolute"
            style={{
              left: "50%", top: 255, width: 760, height: 760, borderRadius: "50%",
              background: "repeating-conic-gradient(from 0deg, rgba(255,226,140,0.55) 0deg 9deg, rgba(255,226,140,0) 9deg 22deg)",
              WebkitMaskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)",
              maskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)",
              animation: "cp-rays 16s linear infinite, cp-rays-in 0.6s ease-out both",
              pointerEvents: "none",
            }}
          />
        )}

        {/* the chest */}
        <div className="absolute left-1/2" style={{ top: 70, width: 340, transform: "translateX(-50%)" }}>
          <div
            onClick={open}
            role="button"
            aria-label="Открыть сундук"
            className="relative"
            style={{
              cursor: phase === "idle" ? "pointer" : "default",
              animation:
                phase === "idle" ? "cp-float 3.2s ease-in-out infinite" : phase === "shaking" ? `cp-shake ${SHAKE_MS}ms ease-in-out both` : "cp-pop 0.55s ease-out both",
            }}
          >
            <img src={`${BASE}chest_closed.png`} alt="" draggable={false} style={{ width: "100%", display: isOpen ? "none" : "block", userSelect: "none", filter: phase === "shaking" ? "brightness(1.15)" : undefined }} />
            <img key={`open-${run}`} src={`${BASE}chest_open.png`} alt="" draggable={false} style={{ width: "100%", display: isOpen ? "block" : "none", userSelect: "none" }} />
          </div>

          {isOpen && (
            <>
              {/* burst flash */}
              <div
                key={`flash-${run}`}
                className="absolute rounded-full"
                style={{ left: "50%", top: "34%", width: 300, height: 300, marginLeft: -150, marginTop: -150, background: "radial-gradient(closest-side, #fff, rgba(255,240,180,0.7) 45%, rgba(255,240,180,0))", animation: "cp-flash 0.7s ease-out both", pointerEvents: "none" }}
              />
              {/* sparks */}
              {sparks.map((s, i) => (
                <span
                  key={`sp-${run}-${i}`}
                  className="absolute"
                  style={{
                    left: "52%", top: "34%", width: s.s, height: s.s, background: "#fff4c2", borderRadius: "50%", boxShadow: "0 0 10px 3px rgba(255,214,102,0.9)",
                    ["--dx" as string]: `${s.dx}px`, ["--dy" as string]: `${s.dy}px`,
                    animation: `cp-spark 0.9s ease-out ${s.delay}s both`, pointerEvents: "none",
                  }}
                />
              ))}
              {/* the loot */}
              {loot.map((l, i) => (
                <span
                  key={`loot-${run}-${i}`}
                  className="absolute select-none"
                  style={{
                    left: "52%", top: "30%", fontSize: l.size, lineHeight: 1, marginLeft: -l.size / 2,
                    filter: "drop-shadow(0 4px 6px rgba(0,0,0,0.35))",
                    ["--dx" as string]: `${l.dx}px`, ["--dy" as string]: `${l.dy}px`, ["--up" as string]: `${l.up}px`,
                    animation: `cp-loot 1s cubic-bezier(.2,.8,.3,1) ${0.25 + l.delay}s both, cp-bob 2.2s ease-in-out ${1.4 + l.delay}s infinite`,
                    pointerEvents: "none",
                  }}
                >
                  {l.icon}
                </span>
              ))}
            </>
          )}
        </div>

        {isOpen && (
          <div
            key={`label-${run}`}
            className="absolute left-1/2 text-center"
            style={{ top: 462, transform: "translateX(-50%)", animation: "cp-label 0.5s ease-out 1.1s both" }}
          >
            <div style={{ fontSize: 34, fontWeight: 900, color: "#fff", textShadow: "0 3px 10px rgba(0,0,0,0.4)" }}>+{t.amount} 💎</div>
            <div style={{ fontSize: 14, color: "rgba(255,255,255,0.8)" }}>
              {t.items.map((it) => `${it.icon} ×${it.count}`).join("   ")}
            </div>
          </div>
        )}

        {phase === "idle" && (
          <div className="absolute left-1/2 text-sm" style={{ bottom: 22, transform: "translateX(-50%)", color: "rgba(255,255,255,0.75)" }}>
            Нажмите на сундук
          </div>
        )}
      </section>

      <section className="card flex flex-wrap items-center gap-3 p-4">
        <div className="flex items-center gap-2 text-sm">
          <span className="text-slate-500">Награда:</span>
          {(Object.keys(TIERS) as Tier[]).map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => { reset(); setTier(k); }}
              className={`rounded-lg px-3 py-1.5 text-sm ${tier === k ? "bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50" : "border border-slate-300 text-slate-700"}`}
            >
              {TIERS[k].label}
            </button>
          ))}
        </div>
        <div className="ml-auto flex gap-2">
          <button type="button" className="bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 rounded-lg px-4 py-2 text-sm" disabled={phase !== "idle"} onClick={open}>
            Открыть
          </button>
          <button type="button" className="rounded-lg border border-slate-300 px-4 py-2 text-sm text-slate-700" disabled={phase === "idle"} onClick={reset}>
            Закрыть снова
          </button>
        </div>
        <p className="w-full text-xs text-slate-500">
          Внутри (условно, для показа): {t.items.map((it) => `${it.icon} ×${it.count}`).join(", ")}, всего +{t.amount} 💎. Реальное содержимое и количество зададим позже.
        </p>
      </section>
    </main>
  );
}

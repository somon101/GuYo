import { useEffect, useMemo, useRef, useState } from "react";

// A preview only: nothing here talks to the server or the app. It shows how a
// chest picture (public/preview/chest_closed.png + chest_open.png) comes alive:
// it floats, shakes when pressed, bursts open with light and throws out rewards.

type Size = "small" | "medium" | "large";
type Phase = "idle" | "shaking" | "open";
type PrizeId = "diamond" | "freeze" | "merge";
type Pick = PrizeId | "random";

// How many diamonds a chest of each size holds (only used when the prize is diamonds).
const SIZES: Record<Size, { label: string; diamonds: number }> = {
  small: { label: "Малая", diamonds: 10 },
  medium: { label: "Средняя", diamonds: 50 },
  large: { label: "Большая", diamonds: 150 },
};

// What can fall out of the chest. Exactly ONE of these per opening.
const PRIZES: Record<PrizeId, { name: string; img: string; amount: (size: Size) => number; unit: string }> = {
  diamond: { name: "Бриллианты", img: "gem.png", amount: (s) => SIZES[s].diamonds, unit: "" },
  freeze: { name: "Заморозка серии", img: "freeze.png", amount: () => 1, unit: "" },
  merge: { name: "Объединитель серии", img: "merge.png", amount: () => 1, unit: "" },
};
const PRIZE_IDS = Object.keys(PRIZES) as PrizeId[];

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
@keyframes cp-prize {
  0% { opacity: 0; transform: translate(-50%,-50%) translateY(0) scale(0.15) rotate(-25deg); }
  18% { opacity: 1; }
  55% { transform: translate(-50%,-50%) translateY(-135px) scale(1.35) rotate(10deg); }
  75% { transform: translate(-50%,-50%) translateY(-112px) scale(1.12) rotate(-5deg); }
  100% { opacity: 1; transform: translate(-50%,-50%) translateY(-120px) scale(1.2) rotate(0deg); }
}
@keyframes cp-bob { 0%,100% { margin-top: 0; } 50% { margin-top: -9px; } }
@keyframes cp-halo { 0%,100% { opacity: 0.55; transform: scale(1); } 50% { opacity: 0.95; transform: scale(1.12); } }
@keyframes cp-label { 0% { opacity: 0; transform: translateY(14px) scale(0.7); } 100% { opacity: 1; transform: translateY(0) scale(1); } }
@keyframes cp-glow { 0%,100% { opacity: 0.35; } 50% { opacity: 0.6; } }
`;

export function ChestPreviewPage() {
  const [size, setSize] = useState<Size>("medium");
  const [pick, setPick] = useState<Pick>("random");
  const [phase, setPhase] = useState<Phase>("idle");
  const [prize, setPrize] = useState<PrizeId>("diamond");
  const [run, setRun] = useState(0); // restarts the CSS animations on every opening
  const last = useRef<PrizeId | null>(null);
  const timer = useRef<number | null>(null);

  useEffect(() => () => { if (timer.current) window.clearTimeout(timer.current); }, []);

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

  // One prize per opening, picked at random (never the same twice in a row when it is random).
  const roll = (): PrizeId => {
    if (pick !== "random") return pick;
    const pool = PRIZE_IDS.filter((id) => id !== last.current);
    return pool[Math.floor(Math.random() * pool.length)];
  };

  const open = () => {
    if (phase !== "idle") return;
    const next = roll();
    last.current = next;
    setPrize(next);
    setRun((n) => n + 1);
    setPhase("shaking");
    timer.current = window.setTimeout(() => setPhase("open"), SHAKE_MS);
  };
  const reset = () => {
    if (timer.current) window.clearTimeout(timer.current);
    setPhase("idle");
  };

  const p = PRIZES[prize];
  const amount = p.amount(size);
  const isOpen = phase === "open";

  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр сундука</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ: как картинка сундука оживает. Нажмите на сундук или кнопку «Открыть»: из него выпадает один случайный
          приз. Ни приложение, ни сервер, ни награды этим не затрагиваются.
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
        <div
          className="absolute left-1/2 rounded-full"
          style={{ top: 360, width: 360, height: 90, transform: "translateX(-50%)", background: "radial-gradient(closest-side, rgba(255,214,120,0.5), rgba(255,214,120,0))", animation: isOpen ? "cp-glow 1.6s ease-in-out infinite" : undefined, opacity: isOpen ? 1 : 0.25 }}
        />

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

        <div className="absolute left-1/2" style={{ top: 90, width: 320, transform: "translateX(-50%)" }}>
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
              <div
                key={`flash-${run}`}
                className="absolute rounded-full"
                style={{ left: "50%", top: "34%", width: 300, height: 300, marginLeft: -150, marginTop: -150, background: "radial-gradient(closest-side, #fff, rgba(255,240,180,0.7) 45%, rgba(255,240,180,0))", animation: "cp-flash 0.7s ease-out both", pointerEvents: "none" }}
              />
              {sparks.map((sp, i) => (
                <span
                  key={`sp-${run}-${i}`}
                  className="absolute"
                  style={{
                    left: "52%", top: "34%", width: sp.s, height: sp.s, background: "#fff4c2", borderRadius: "50%", boxShadow: "0 0 10px 3px rgba(255,214,102,0.9)",
                    ["--dx" as string]: `${sp.dx}px`, ["--dy" as string]: `${sp.dy}px`,
                    animation: `cp-spark 0.9s ease-out ${sp.delay}s both`, pointerEvents: "none",
                  }}
                />
              ))}

              {/* the one prize: rises out of the chest, glows and floats */}
              <div key={`prize-${run}`} className="absolute" style={{ left: "52%", top: "36%", width: 0, height: 0, pointerEvents: "none" }}>
                <div
                  className="absolute rounded-full"
                  style={{ left: -125, top: -245, width: 250, height: 250, background: "radial-gradient(closest-side, rgba(255,246,200,0.95), rgba(255,226,140,0.45) 55%, rgba(255,226,140,0))", animation: "cp-halo 1.8s ease-in-out 1.2s infinite both", opacity: 0 }}
                />
                <div style={{ animation: "cp-bob 2.2s ease-in-out 1.5s infinite" }}>
                  <img
                    src={`${BASE}${p.img}`}
                    alt={p.name}
                    draggable={false}
                    className="absolute select-none"
                    style={{ left: 0, top: 0, width: 150, height: 150, maxWidth: "none", objectFit: "contain", filter: "drop-shadow(0 8px 14px rgba(0,0,0,0.45))", animation: "cp-prize 1.25s cubic-bezier(.2,.8,.3,1) 0.2s both" }}
                  />
                </div>
              </div>
            </>
          )}
        </div>

        {isOpen && (
          <div
            key={`label-${run}`}
            className="absolute left-1/2 text-center"
            style={{ top: 470, transform: "translateX(-50%)", animation: "cp-label 0.5s ease-out 1.2s both" }}
          >
            <div style={{ fontSize: 34, fontWeight: 900, color: "#fff", textShadow: "0 3px 10px rgba(0,0,0,0.4)", display: "flex", alignItems: "center", justifyContent: "center", gap: 10 }}>
              {prize === "diamond" ? `+${amount}` : `×${amount}`}
            </div>
            <div style={{ fontSize: 15, color: "rgba(255,255,255,0.85)" }}>{p.name}</div>
          </div>
        )}

        {phase === "idle" && (
          <div className="absolute left-1/2 text-sm" style={{ bottom: 22, transform: "translateX(-50%)", color: "rgba(255,255,255,0.75)" }}>
            Нажмите на сундук
          </div>
        )}
      </section>

      <section className="card space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500">Приз:</span>
          {(["random", ...PRIZE_IDS] as Pick[]).map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => { reset(); setPick(k); }}
              className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm ${pick === k ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}
            >
              {k !== "random" && <img src={`${BASE}${PRIZES[k].img}`} alt="" style={{ width: 18, height: 18, objectFit: "contain" }} />}
              {k === "random" ? "Случайный" : PRIZES[k].name}
            </button>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500">Размер (для бриллиантов):</span>
          {(Object.keys(SIZES) as Size[]).map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => { reset(); setSize(k); }}
              className={`rounded-lg px-3 py-1.5 text-sm ${size === k ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}
            >
              {SIZES[k].label}: {SIZES[k].diamonds}
            </button>
          ))}
          <div className="ml-auto flex gap-2">
            <button type="button" className="rounded-lg bg-indigo-600 px-4 py-2 text-sm text-white hover:bg-indigo-700 disabled:opacity-50" disabled={phase !== "idle"} onClick={open}>
              Открыть
            </button>
            <button type="button" className="rounded-lg border border-slate-300 px-4 py-2 text-sm text-slate-700 disabled:opacity-50" disabled={phase === "idle"} onClick={reset}>
              Закрыть снова
            </button>
          </div>
        </div>
        <p className="text-xs text-slate-500">
          Из сундука всегда выпадает один приз. При «Случайном» каждый раз другой, не повторяется два раза подряд. Реальные призы и шансы зададим позже.
        </p>
      </section>
    </main>
  );
}

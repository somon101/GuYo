import { useEffect, useMemo, useRef, useState } from "react";
import { getChestOverview, type ChestType } from "../api/endpoints";

// A preview only: nothing here talks to the server or the app. It shows how a
// chest picture (public/preview/chest_closed.png + chest_open.png) comes alive:
// it floats, shakes when pressed, bursts open with light and throws out rewards.

type Phase = "idle" | "bursting" | "open";
type PrizeId = "diamond" | "freeze" | "merge" | "points";
type Pick = PrizeId | "random";

// What can fall out of a chest. Exactly ONE of these per opening; the ceiling of each comes from the chest's real settings.
const PRIZES: Record<PrizeId, { name: string; img: string | null; cap: (c: ChestType) => number }> = {
  diamond: { name: "Бриллианты", img: "gem.png", cap: (c) => c.max_diamonds },
  freeze: { name: "Заморозки серии", img: "freeze.png", cap: (c) => c.max_freezes },
  merge: { name: "Объединители серии", img: "merge.png", cap: (c) => c.max_merges },
  points: { name: "Очки рейтинга", img: null, cap: (c) => c.max_points },
};
const PRIZE_IDS = Object.keys(PRIZES) as PrizeId[];
const FALLBACK: ChestType[] = [
  { key: "wood", name: "Деревянный сундук", color: "#a0693b", max_diamonds: 10, max_freezes: 1, max_merges: 1, max_points: 20 },
  { key: "silver", name: "Серебряный сундук", color: "#5aa9e6", max_diamonds: 30, max_freezes: 2, max_merges: 2, max_points: 60 },
  { key: "purple", name: "Фиолетовый сундук", color: "#9b5de5", max_diamonds: 100, max_freezes: 3, max_merges: 3, max_points: 150 },
  { key: "gold", name: "Золотой сундук", color: "#f5b700", max_diamonds: 300, max_freezes: 5, max_merges: 5, max_points: 400 },
];
const CHEST_BASE = `${import.meta.env.BASE_URL}chests/`;

const TAPS_TO_OPEN = 3;
const BURST_MS = 520;
const BASE = `${import.meta.env.BASE_URL}preview/`;

const css = `
@keyframes cp-float { 0%,100% { transform: translateY(0) rotate(-0.6deg) scale(1); } 50% { transform: translateY(-9px) rotate(0.6deg) scale(1.015); } }
@keyframes cp-tap1 { 0% { transform: scale(1); } 20% { transform: translate(-4px,2px) rotate(-3deg) scale(1.04); } 45% { transform: translate(4px,0) rotate(3deg) scale(1.05); } 70% { transform: translate(-2px,0) rotate(-1.5deg) scale(1.03); } 100% { transform: scale(1.02); } }
@keyframes cp-tap2 { 0% { transform: scale(1.02); } 15% { transform: translate(-8px,3px) rotate(-6deg) scale(1.08); } 35% { transform: translate(8px,-2px) rotate(6deg) scale(1.1); } 55% { transform: translate(-6px,2px) rotate(-4deg) scale(1.09); } 80% { transform: translate(4px,0) rotate(2deg) scale(1.07); } 100% { transform: scale(1.05); } }
@keyframes cp-burst {
  0% { transform: scale(1.05); }
  10% { transform: translate(-12px,4px) rotate(-8deg) scale(1.14); }
  22% { transform: translate(12px,-4px) rotate(8deg) scale(1.18); }
  36% { transform: translate(-12px,4px) rotate(-9deg) scale(1.2); }
  50% { transform: translate(12px,-3px) rotate(9deg) scale(1.22); }
  66% { transform: translate(-8px,2px) rotate(-5deg) scale(1.26); }
  82% { transform: translate(4px,0) rotate(3deg) scale(1.3); }
  100% { transform: translate(0,0) rotate(0) scale(1.34); }
}
@keyframes cp-pop { 0% { transform: scale(1.34); } 30% { transform: scale(0.92); } 60% { transform: scale(1.06); } 100% { transform: scale(1); } }
@keyframes cp-exit { 0% { opacity: 1; transform: translateY(0) scale(1); } 100% { opacity: 0; transform: translateY(170px) scale(0.7); } }
@keyframes cp-flash { 0% { opacity: 0.95; transform: scale(0.4); } 100% { opacity: 0; transform: scale(2.6); } }
@keyframes cp-rays { from { transform: translate(-50%,-50%) rotate(0deg); } to { transform: translate(-50%,-50%) rotate(360deg); } }
@keyframes cp-rays-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes cp-spark { 0% { opacity: 1; transform: translate(0,0) scale(0.4); } 100% { opacity: 0; transform: translate(var(--dx), var(--dy)) scale(1.2); } }
@keyframes cp-prize {
  0% { opacity: 0; transform: translate(-50%,-50%) translateY(-10px) scale(0.12) rotate(-30deg); }
  15% { opacity: 1; }
  45% { transform: translate(-50%,-50%) translateY(-135px) scale(1.25) rotate(12deg); }
  75% { transform: translate(-50%,-50%) translateY(14px) scale(1.65) rotate(-4deg); }
  100% { opacity: 1; transform: translate(-50%,-50%) translateY(0) scale(1.55) rotate(0deg); }
}
@keyframes cp-bob { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-10px); } }
@keyframes cp-halo { 0%,100% { opacity: 0.6; transform: translate(-50%,-50%) scale(1); } 50% { opacity: 1; transform: translate(-50%,-50%) scale(1.14); } }
@keyframes cp-shine { 0% { transform: translateX(-130%) skewX(-20deg); } 55%,100% { transform: translateX(230%) skewX(-20deg); } }
@keyframes cp-twinkle { 0%,100% { opacity: 0; transform: scale(0.3) rotate(0deg); } 50% { opacity: 1; transform: scale(1) rotate(45deg); } }
@keyframes cp-label { 0% { opacity: 0; transform: translateY(14px) scale(0.7); } 100% { opacity: 1; transform: translateY(0) scale(1); } }
@keyframes cp-glow { 0%,100% { opacity: 0.35; } 50% { opacity: 0.6; } }
@keyframes cp-dot { 0% { transform: scale(1); } 40% { transform: scale(1.6); } 100% { transform: scale(1); } }
`;

const TWINKLES = [
  { x: -150, y: -80, d: 0, s: 22 }, { x: 150, y: -95, d: 0.4, s: 28 }, { x: -175, y: 40, d: 0.8, s: 18 },
  { x: 170, y: 55, d: 0.2, s: 20 }, { x: -70, y: -150, d: 0.6, s: 16 }, { x: 80, y: 150, d: 1.0, s: 24 },
  { x: -105, y: 135, d: 0.3, s: 16 }, { x: 110, y: -150, d: 0.9, s: 18 },
];

export function ChestPreviewPage() {
  const [types, setTypes] = useState<ChestType[]>(FALLBACK);
  const [chestKey, setChestKey] = useState("wood");
  const [amount, setAmount] = useState(1);
  const [pick, setPick] = useState<Pick>("random");
  const [phase, setPhase] = useState<Phase>("idle");
  const [taps, setTaps] = useState(0);
  const [tapRun, setTapRun] = useState(0); // restarts the shake of a single tap
  const [prize, setPrize] = useState<PrizeId>("diamond");
  const [run, setRun] = useState(0); // restarts the CSS animations on every opening
  const last = useRef<PrizeId | null>(null);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    getChestOverview().then((o) => setTypes(o.types)).catch(() => undefined);
  }, []);
  const chest = types.find((c) => c.key === chestKey) ?? types[0];

  useEffect(() => () => { if (timer.current) window.clearTimeout(timer.current); }, []);

  const sparks = useMemo(
    () =>
      Array.from({ length: 22 }, (_, i) => {
        const a = (i / 22) * Math.PI * 2 + Math.random() * 0.4;
        const d = 130 + Math.random() * 120;
        return { dx: Math.cos(a) * d, dy: Math.sin(a) * d - 40, delay: Math.random() * 0.12, s: 6 + Math.random() * 9 };
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [run],
  );

  // One prize per opening, picked at random (never the same twice in a row when it is random).
  const roll = (): PrizeId => {
    const possible = PRIZE_IDS.filter((id) => PRIZES[id].cap(chest) > 0);
    if (pick !== "random" && possible.includes(pick)) return pick;
    const pool = possible.filter((id) => id !== last.current);
    const from = pool.length ? pool : possible;
    return from[Math.floor(Math.random() * from.length)];
  };

  // Every press shakes the chest harder; the third one bursts it open.
  const tap = () => {
    if (phase !== "idle") return;
    const n = taps + 1;
    setTaps(n);
    setTapRun((r) => r + 1);
    if (n >= TAPS_TO_OPEN) {
      const next = roll();
      last.current = next;
      setPrize(next);
      setAmount(1 + Math.floor(Math.random() * Math.max(1, PRIZES[next].cap(chest))));
      setRun((r) => r + 1);
      setPhase("bursting");
      timer.current = window.setTimeout(() => setPhase("open"), BURST_MS);
    }
  };
  const reset = () => {
    if (timer.current) window.clearTimeout(timer.current);
    setPhase("idle");
    setTaps(0);
  };

  const p = PRIZES[prize];
  const isOpen = phase === "open";

  const chestAnimation =
    phase === "open"
      ? "cp-pop 0.5s ease-out both, cp-exit 0.95s ease-in 1.0s both"
      : phase === "bursting"
        ? `cp-burst ${BURST_MS}ms ease-in-out both`
        : taps === 0
          ? "cp-float 3.2s ease-in-out infinite"
          : undefined;

  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр сундука</h1>
        <p className="mt-1 text-sm text-slate-500">
          Показ на настоящих настройках сундуков (потолки задаются на странице «Сундуки»); награды игрокам не выдаются. Нажмите на сундук три раза: с каждым нажатием он трясётся сильнее, на третьем раскрывается, сам уходит
          со сцены, а выпавший приз остаётся в центре и сияет. 
        </p>
      </header>

      <section
        className="relative mx-auto overflow-hidden rounded-3xl"
        style={{
          height: 560,
          background: "radial-gradient(ellipse at 50% 60%, #5b3fd0 0%, #2a1f6b 55%, #150f3a 100%)",
          boxShadow: "0 18px 50px rgba(30,20,90,0.35)",
        }}
      >
        <div
          className="absolute left-1/2 rounded-full"
          style={{ top: 360, width: 360, height: 90, transform: "translateX(-50%)", background: "radial-gradient(closest-side, rgba(255,214,120,0.5), rgba(255,214,120,0))", animation: phase !== "idle" ? "cp-glow 1.6s ease-in-out infinite" : undefined, opacity: phase !== "idle" ? 1 : 0.2 + taps * 0.12 }}
        />

        {/* light rays behind the scene, centred where the prize ends up */}
        {isOpen && (
          <div
            key={`rays-${run}`}
            className="absolute"
            style={{
              left: "50%", top: 250, width: 820, height: 820, borderRadius: "50%",
              background: "repeating-conic-gradient(from 0deg, rgba(255,226,140,0.6) 0deg 9deg, rgba(255,226,140,0) 9deg 22deg)",
              WebkitMaskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)",
              maskImage: "radial-gradient(closest-side, #000 15%, transparent 72%)",
              animation: "cp-rays 18s linear infinite, cp-rays-in 0.9s ease-out 0.4s both",
              pointerEvents: "none",
            }}
          />
        )}

        {/* the chest */}
        <div className="absolute left-1/2" style={{ top: 90, width: 320, transform: "translateX(-50%)" }}>
          <div key={`tap-${tapRun}-${phase}`} style={{ animation: phase === "idle" && taps > 0 ? `cp-tap${Math.min(taps, 2)} 0.5s ease-out both` : chestAnimation }}>
            <div
              onClick={tap}
              role="button"
              aria-label="Нажать на сундук"
              className="relative"
              style={{ cursor: phase === "idle" ? "pointer" : "default", filter: phase === "idle" ? `brightness(${1 + taps * 0.12})` : phase === "bursting" ? "brightness(1.35)" : undefined }}
            >
              <img src={`${CHEST_BASE}${chestKey}_closed.png`} alt="" draggable={false} style={{ width: "100%", display: isOpen ? "none" : "block", userSelect: "none" }} />
              <img key={`open-${run}`} src={`${CHEST_BASE}${chestKey}_open.png`} alt="" draggable={false} style={{ width: "100%", display: isOpen ? "block" : "none", userSelect: "none" }} />
            </div>
          </div>

          {(phase === "bursting" || isOpen) && (
            <div
              key={`flash-${run}`}
              className="absolute rounded-full"
              style={{ left: "50%", top: "34%", width: 320, height: 320, marginLeft: -160, marginTop: -160, background: "radial-gradient(closest-side, #fff, rgba(255,240,180,0.75) 45%, rgba(255,240,180,0))", animation: `cp-flash 0.8s ease-out ${phase === "bursting" ? BURST_MS - 120 : 0}ms both`, pointerEvents: "none", opacity: 0 }}
            />
          )}
          {isOpen &&
            sparks.map((sp, i) => (
              <span
                key={`sp-${run}-${i}`}
                className="absolute"
                style={{
                  left: "52%", top: "34%", width: sp.s, height: sp.s, background: "#fff4c2", borderRadius: "50%", boxShadow: "0 0 10px 3px rgba(255,214,102,0.9)",
                  ["--dx" as string]: `${sp.dx}px`, ["--dy" as string]: `${sp.dy}px`,
                  animation: `cp-spark 1s ease-out ${sp.delay}s both`, pointerEvents: "none",
                }}
              />
            ))}
        </div>

        {/* the prize: flies out of the chest and settles in the middle of the stage */}
        {isOpen && (
          <div key={`prize-${run}`} className="absolute" style={{ left: "50%", top: 250, width: 0, height: 0, pointerEvents: "none" }}>
            <div
              className="absolute rounded-full"
              style={{ left: 0, top: 0, width: 330, height: 330, background: "radial-gradient(closest-side, rgba(255,248,205,0.95), rgba(255,226,140,0.5) 55%, rgba(255,226,140,0))", animation: "cp-halo 2s ease-in-out 1.1s infinite both", opacity: 0 }}
            />
            {TWINKLES.map((t, i) => (
              <span
                key={i}
                className="absolute select-none"
                style={{ left: t.x - t.s / 2, top: t.y - t.s / 2, width: t.s, height: t.s, color: "#fff7c9", fontSize: t.s, lineHeight: 1, textShadow: "0 0 10px rgba(255,220,120,0.95)", animation: `cp-twinkle 1.8s ease-in-out ${1.2 + t.d}s infinite both`, opacity: 0 }}
              >
                ✦
              </span>
            ))}
            <div style={{ animation: "cp-bob 2.4s ease-in-out 1.6s infinite" }}>
              <div className="absolute" style={{ left: 0, top: 0, width: 170, height: 170, animation: "cp-prize 1.5s cubic-bezier(.2,.8,.3,1) 0.45s both", opacity: 0 }}>
                {p.img === null ? (
                  <div className="select-none" style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 130, lineHeight: 1, color: "#ffc53d", filter: "drop-shadow(0 10px 18px rgba(0,0,0,0.5)) drop-shadow(0 0 22px rgba(255,236,160,0.65))" }}>★</div>
                ) : (
                <img
                  src={`${BASE}${p.img}`}
                  alt={p.name}
                  draggable={false}
                  className="select-none"
                  style={{ width: "100%", height: "100%", maxWidth: "none", objectFit: "contain", filter: "drop-shadow(0 10px 18px rgba(0,0,0,0.5)) drop-shadow(0 0 22px rgba(255,236,160,0.65))" }}
                />
                )}
                {/* a glint that sweeps across the prize */}
                {p.img !== null && <div style={{ position: "absolute", inset: 0, overflow: "hidden", borderRadius: 24, WebkitMaskImage: `url(${BASE}${p.img})`, maskImage: `url(${BASE}${p.img})`, WebkitMaskSize: "contain", maskSize: "contain", WebkitMaskRepeat: "no-repeat", maskRepeat: "no-repeat", WebkitMaskPosition: "center", maskPosition: "center" }}>
                  <div style={{ position: "absolute", top: 0, bottom: 0, width: "38%", background: "linear-gradient(90deg, rgba(255,255,255,0), rgba(255,255,255,0.85), rgba(255,255,255,0))", animation: "cp-shine 2.6s ease-in-out 2.0s infinite" }} />
                </div>}
              </div>
            </div>
          </div>
        )}

        {isOpen && (
          <div
            key={`label-${run}`}
            className="absolute left-1/2 text-center"
            style={{ top: 440, transform: "translateX(-50%)", animation: "cp-label 0.5s ease-out 1.9s both" }}
          >
            <div style={{ fontSize: 38, fontWeight: 900, color: "#fff", textShadow: "0 3px 12px rgba(0,0,0,0.45)" }}>
              +{amount}
            </div>
            <div style={{ fontSize: 16, color: "rgba(255,255,255,0.9)" }}>{p.name}</div>
          </div>
        )}

        {phase === "idle" && (
          <div className="absolute left-1/2 flex flex-col items-center gap-2" style={{ bottom: 22, transform: "translateX(-50%)" }}>
            <div className="flex gap-2">
              {Array.from({ length: TAPS_TO_OPEN }, (_, i) => (
                <span
                  key={i}
                  style={{ width: 12, height: 12, borderRadius: "50%", background: i < taps ? "#ffd54f" : "rgba(255,255,255,0.25)", boxShadow: i < taps ? "0 0 10px rgba(255,213,79,0.9)" : undefined, animation: i === taps - 1 ? "cp-dot 0.4s ease-out" : undefined }}
                />
              ))}
            </div>
            <div className="text-sm" style={{ color: "rgba(255,255,255,0.8)" }}>
              {taps === 0 ? "Нажмите на сундук 3 раза" : `Ещё ${TAPS_TO_OPEN - taps}…`}
            </div>
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
              {k !== "random" && PRIZES[k].img && <img src={`${BASE}${PRIZES[k].img}`} alt="" style={{ width: 18, height: 18, objectFit: "contain" }} />}
              {k === "random" ? "Случайный" : PRIZES[k].name}
            </button>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500">Сундук:</span>
          {types.map((c) => (
            <button
              key={c.key}
              type="button"
              onClick={() => { reset(); setChestKey(c.key); }}
              className={`flex items-center gap-1.5 rounded-lg px-2 py-1 text-sm ${chestKey === c.key ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}
            >
              <img src={`${CHEST_BASE}${c.key}_closed.png`} alt="" style={{ width: 28, height: 28, objectFit: "contain" }} />
              {c.name}
            </button>
          ))}
        </div>
        <p className="text-xs text-slate-500">
          В этом сундуке: бриллианты 1–{chest.max_diamonds}, заморозки 1–{chest.max_freezes}, объединители 1–{chest.max_merges}, очки рейтинга 1–{chest.max_points} (0 = такого приза нет).
        </p>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <div className="ml-auto flex gap-2">
            <button type="button" className="rounded-lg bg-indigo-600 px-4 py-2 text-sm text-white hover:bg-indigo-700 disabled:opacity-50" disabled={phase !== "idle"} onClick={tap}>
              Нажать ({Math.min(taps + 1, TAPS_TO_OPEN)}/{TAPS_TO_OPEN})
            </button>
            <button type="button" className="rounded-lg border border-slate-300 px-4 py-2 text-sm text-slate-700 disabled:opacity-50" disabled={phase === "idle" && taps === 0} onClick={reset}>
              Закрыть снова
            </button>
          </div>
        </div>
        <p className="text-xs text-slate-500">
          Из сундука всегда выпадает один приз. При «Случайном» каждый раз другой, не повторяется два раза подряд. Количество выпадает случайно от 1 до потолка выбранного сундука.
        </p>
      </section>
    </main>
  );
}

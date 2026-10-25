import { useEffect, useMemo, useRef, useState } from "react";

// A preview only (nothing is sent anywhere): how an earned achievement is opened.
// It mirrors the app's geode: four glass panels hold the badge, four taps crack
// them (each tap with its own sound and buzz), the last one bursts the shell.

const BASE = `${import.meta.env.BASE_URL}preview/`;
const TAPS = 4;
const C = { x: 100, y: 100 };
const R = 45;

type Crack = { level: number; pts: [number, number][]; base: number; edge: number };
type Panel = { cx: number; cy: number; cracks: Crack[] };
const P = (level: number, pts: [number, number][], base: number, edge: number): Crack => ({ level, pts, base, edge });
const PANELS: Panel[] = [
  { cx: 100, cy: 68, cracks: [
    P(1, [[90, 50], [96, 58], [92, 66]], 1.8, 3), P(2, [[82, 40], [90, 50], [96, 58], [100, 70], [96, 82]], 1.8, 3),
    P(2, [[96, 58], [110, 54], [120, 58]], 1.5, 2.5), P(3, [[92, 66], [84, 74], [74, 78]], 1.5, 2.5),
    P(3, [[100, 70], [112, 78], [118, 90]], 1.5, 2.5), P(3, [[74, 78], [68, 88]], 1.2, 2)] },
  { cx: 132, cy: 100, cracks: [
    P(1, [[118, 90], [126, 96], [122, 106]], 1.8, 3), P(2, [[110, 82], [118, 90], [126, 96], [140, 98]], 1.8, 3),
    P(2, [[126, 96], [130, 112], [126, 124]], 1.5, 2.5), P(3, [[122, 106], [112, 114], [108, 126]], 1.5, 2.5),
    P(3, [[140, 98], [152, 104], [158, 114]], 1.5, 2.5), P(3, [[130, 112], [142, 118]], 1.2, 2)] },
  { cx: 100, cy: 132, cracks: [
    P(1, [[96, 118], [100, 126], [94, 136]], 1.8, 3), P(2, [[100, 114], [100, 126], [94, 136], [88, 150]], 1.8, 3),
    P(2, [[100, 126], [114, 130], [122, 140]], 1.5, 2.5), P(3, [[94, 136], [82, 142], [76, 154]], 1.5, 2.5),
    P(3, [[88, 150], [96, 158]], 1.5, 2.5), P(3, [[122, 140], [134, 144]], 1.2, 2)] },
  { cx: 68, cy: 100, cracks: [
    P(1, [[56, 90], [62, 96], [58, 106]], 1.8, 3), P(2, [[48, 80], [56, 90], [62, 96], [74, 100]], 1.8, 3),
    P(2, [[62, 96], [58, 112], [52, 122]], 1.5, 2.5), P(3, [[58, 106], [44, 112], [38, 122]], 1.5, 2.5),
    P(3, [[74, 100], [82, 92]], 1.5, 2.5), P(3, [[48, 80], [42, 70]], 1.2, 2)] },
];

const css = `
@keyframes ap-float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-6px); } }
@keyframes ap-hit { 0% { transform: scale(1) rotate(0); } 18% { transform: scale(0.94) rotate(-2.5deg); } 40% { transform: scale(1.04) rotate(2deg); } 70% { transform: scale(0.99) rotate(-1deg); } 100% { transform: scale(1) rotate(0); } }
@keyframes ap-flash { 0% { opacity: 0.95; transform: scale(0.3); } 100% { opacity: 0; transform: scale(2.6); } }
@keyframes ap-badge { 0% { opacity: 0; transform: scale(0.2) rotate(-25deg); } 60% { opacity: 1; transform: scale(1.18) rotate(6deg); } 100% { opacity: 1; transform: scale(1) rotate(0); } }
@keyframes ap-spark { 0% { opacity: 1; transform: translate(0,0) scale(0.5); } 100% { opacity: 0; transform: translate(var(--dx), var(--dy)) scale(1.1); } }
@keyframes ap-label { 0% { opacity: 0; transform: translateY(12px); } 100% { opacity: 1; transform: translateY(0); } }
`;

function Crack({ c }: { c: Crack }) {
  const d = c.pts.map(([x, y], i) => `${i ? "L" : "M"}${x} ${y}`).join(" ");
  return (
    <g strokeLinecap="round" strokeLinejoin="round" fill="none">
      <path d={d} stroke="#0a0a14" strokeWidth={c.base} />
      <path d={d} stroke="rgba(255,220,140,0.85)" strokeWidth={c.base * 0.45} />
    </g>
  );
}

export function AchievementPreviewPage() {
  const [taps, setTaps] = useState(0);
  const [run, setRun] = useState(0);
  const broken = taps >= TAPS;
  const click = useRef<HTMLAudioElement | null>(null);
  const reveal = useRef<HTMLAudioElement | null>(null);

  const buzz = (p: number | number[]) => { try { navigator.vibrate?.(p); } catch { /* not supported */ } };
  const stopAll = () => { click.current?.pause(); reveal.current?.pause(); buzz(0); };
  useEffect(() => stopAll, []);

  const sparks = useMemo(
    () => Array.from({ length: 24 }, (_, i) => {
      const a = (i / 24) * Math.PI * 2 + Math.random() * 0.3;
      const d = 120 + Math.random() * 110;
      return { dx: Math.cos(a) * d, dy: Math.sin(a) * d, s: 5 + Math.random() * 8, delay: Math.random() * 0.1 };
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [run],
  );

  const tap = () => {
    if (broken) return;
    const n = taps + 1;
    setTaps(n);
    if (n >= TAPS) {
      // the last tap bursts the shell: the chest-opening sound and the long rumble
      click.current?.pause();
      if (!reveal.current) reveal.current = new Audio(`${BASE}chest-open.mp3`);
      reveal.current.currentTime = 0;
      void reveal.current.play().catch(() => undefined);
      buzz([0, 90, 50, 90, 50, 200]);
      setRun((r) => r + 1);
    } else {
      // every other tap: the wall-hit sound, cutting the previous one
      if (!click.current) click.current = new Audio(`${BASE}achievement-tap.mp3`);
      click.current.currentTime = 0;
      void click.current.play().catch(() => undefined);
      buzz(35);
    }
  };
  const reset = () => { stopAll(); setTaps(0); };

  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр достижения</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. Нажмите на каменный шар четыре раза: каждое нажатие со своим звуком удара и вибрацией (на телефоне), трещины растут,
          на последнем шар раскалывается со звуком открытия сундука, и достижение появляется в центре.
        </p>
      </header>

      <section className="relative mx-auto overflow-hidden rounded-3xl" style={{ height: 520, background: "radial-gradient(ellipse at 50% 55%, #3b2c86 0%, #1e1560 55%, #0d0a2e 100%)", boxShadow: "0 18px 50px rgba(30,20,90,0.35)" }}>
        <div className="absolute left-1/2 top-1/2" style={{ width: 360, height: 360, transform: "translate(-50%,-56%)" }}>
          {/* the glow inside grows with every crack */}
          <div className="absolute inset-0 rounded-full" style={{ background: "radial-gradient(closest-side, rgba(255,226,140,0.9), rgba(255,200,90,0))", opacity: broken ? 0 : taps * 0.22, transition: "opacity .3s" }} />

          {broken && (
            <div key={`badge-${run}`} className="absolute left-1/2 top-1/2" style={{ marginLeft: -80, marginTop: -80, width: 160, height: 160, animation: "ap-badge .9s cubic-bezier(.2,.9,.3,1.1) .25s both", opacity: 0 }}>
              <svg viewBox="0 0 160 160" width="160" height="160">
                <defs>
                  <radialGradient id="ap-ring" cx="40%" cy="30%"><stop offset="0" stopColor="#fff3a0" /><stop offset="0.6" stopColor="#ffc928" /><stop offset="1" stopColor="#d98100" /></radialGradient>
                  <radialGradient id="ap-in" cx="50%" cy="35%"><stop offset="0" stopColor="#8a6bff" /><stop offset="1" stopColor="#3b2aa8" /></radialGradient>
                </defs>
                <circle cx="80" cy="80" r="74" fill="url(#ap-ring)" stroke="#a55f00" strokeWidth="3" />
                <circle cx="80" cy="80" r="58" fill="url(#ap-in)" stroke="#ffe27a" strokeWidth="3" />
                <image href={`${BASE}points.png`} x="40" y="38" width="80" height="80" />
                <path d="M30 40 Q60 8 100 14" stroke="rgba(255,255,255,0.7)" strokeWidth="5" fill="none" strokeLinecap="round" />
              </svg>
            </div>
          )}

          <div key={`geode-${taps}`} className="absolute inset-0" style={{ animation: broken ? undefined : taps === 0 ? "ap-float 3.2s ease-in-out infinite" : "ap-hit .45s ease-out both" }}>
            <svg viewBox="0 0 200 200" width="360" height="360" role="button" aria-label="Нажать на шар" onClick={tap} style={{ cursor: broken ? "default" : "pointer", overflow: "visible" }}>
              <defs>
                <radialGradient id="ap-stone" cx="38%" cy="30%" r="80%">
                  <stop offset="0" stopColor="#6a6a76" /><stop offset="0.55" stopColor="#4a4a56" /><stop offset="1" stopColor="#1a1a24" />
                </radialGradient>
              </defs>
              {PANELS.map((p, i) => {
                const dx = p.cx - C.x, dy = p.cy - C.y;
                const len = Math.hypot(dx, dy) || 1;
                const fly = broken ? 140 : 0;
                return (
                  <g key={i} style={{ transform: `translate(${(dx / len) * fly}px, ${(dy / len) * fly}px) rotate(${broken ? (i % 2 ? 40 : -40) : 0}deg)`, transformOrigin: `${p.cx}px ${p.cy}px`, opacity: broken ? 0 : 1, transition: "transform .8s cubic-bezier(.2,.7,.3,1), opacity .7s ease-in .15s" }}>
                    <circle cx={p.cx} cy={p.cy} r={R} fill="url(#ap-stone)" stroke="#151621" strokeWidth="2.2" />
                    <circle cx={p.cx - 10} cy={p.cy - 12} r={R * 0.55} fill="rgba(255,255,255,0.07)" />
                    {p.cracks.filter((c) => c.level <= taps).map((c, k) => <Crack key={k} c={c} />)}
                  </g>
                );
              })}
            </svg>
          </div>

          {broken && (
            <div key={`flash-${run}`} className="absolute rounded-full" style={{ left: "50%", top: "50%", width: 360, height: 360, marginLeft: -180, marginTop: -180, background: "radial-gradient(closest-side, #fff, rgba(255,240,180,0.7) 45%, rgba(255,240,180,0))", animation: "ap-flash .8s ease-out both", pointerEvents: "none" }} />
          )}
          {broken && sparks.map((s, i) => (
            <span key={`${run}-${i}`} className="absolute rounded-full" style={{ left: "50%", top: "50%", width: s.s, height: s.s, background: "#fff4c2", boxShadow: "0 0 10px 3px rgba(255,214,102,0.9)", ["--dx" as string]: `${s.dx}px`, ["--dy" as string]: `${s.dy}px`, animation: `ap-spark 1s ease-out ${s.delay}s both`, pointerEvents: "none" }} />
          ))}
        </div>

        {broken ? (
          <div key={`label-${run}`} className="absolute left-0 right-0 text-center" style={{ bottom: 36, animation: "ap-label .5s ease-out 1.1s both", opacity: 0 }}>
            <div style={{ fontSize: 13, letterSpacing: 2, color: "#ffd54f", fontWeight: 800 }}>ДОСТИЖЕНИЕ ПОЛУЧЕНО</div>
            <div style={{ fontSize: 28, fontWeight: 900, color: "#fff", textShadow: "0 3px 12px rgba(0,0,0,0.5)" }}>Знаток слов</div>
          </div>
        ) : (
          <div className="absolute left-1/2 flex flex-col items-center gap-2" style={{ bottom: 22, transform: "translateX(-50%)" }}>
            <div className="flex gap-2">
              {Array.from({ length: TAPS }, (_, i) => (
                <span key={i} style={{ width: 12, height: 12, borderRadius: "50%", background: i < taps ? "#ffd54f" : "rgba(255,255,255,0.25)", boxShadow: i < taps ? "0 0 10px rgba(255,213,79,0.9)" : undefined }} />
              ))}
            </div>
            <div className="text-sm" style={{ color: "rgba(255,255,255,0.8)" }}>{taps === 0 ? "Нажмите на шар 4 раза" : `Ещё ${TAPS - taps}…`}</div>
          </div>
        )}
      </section>

      <section className="card flex flex-wrap items-center gap-2 p-4 text-sm">
        <button type="button" className="rounded-lg bg-indigo-600 px-4 py-2 text-white hover:bg-indigo-700 disabled:opacity-50" disabled={broken} onClick={tap}>
          Нажать ({Math.min(taps + 1, TAPS)}/{TAPS})
        </button>
        <button type="button" className="rounded-lg border border-slate-300 px-4 py-2 text-slate-700 disabled:opacity-50" disabled={taps === 0} onClick={reset}>Закрыть снова</button>
        <span className="ml-2 text-xs text-slate-500">Звук удара на каждом нажатии (быстрые нажатия обрывают предыдущий), на последнем — звук открытия сундука. При выходе всё замолкает.</span>
      </section>
    </main>
  );
}

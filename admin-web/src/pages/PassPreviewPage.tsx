import { useState } from "react";

// A preview only: how «Пропуск сезона» tells that rewards wait. The yellow pill is gone;
// the small gift from the daily-goal card is the notification. Nothing goes to the server.

const BASE = `${import.meta.env.BASE_URL}`;
const css = `@keyframes pp-wobble { 0%,100% { transform: scale(1) rotate(-6deg); } 50% { transform: scale(1.15) rotate(6deg); } }`;
const hero = "linear-gradient(135deg,#5862dd,#8a4fd6)";

function Gift({ size, count }: { size: number; count: number }) {
  return (
    <span style={{ position: "relative", width: size, height: size, display: "inline-flex", animation: "pp-wobble 1.6s ease-in-out infinite" }}>
      <img src={`${BASE}preview/gift.png`} alt="" style={{ width: size, height: size, objectFit: "contain", filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.5))" }} />
      {count > 1 && <span style={{ position: "absolute", right: -4, bottom: -2, minWidth: 16, height: 16, padding: "0 4px", borderRadius: 8, background: "#e53935", color: "#fff", fontSize: 10, fontWeight: 900, display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 0 0 1.5px #12151f" }}>{count}</span>}
    </span>
  );
}

export function PassPreviewPage() {
  const [count, setCount] = useState(3);
  return (
    <main className="mx-auto max-w-3xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр пропуска: награда ждёт</h1>
        <p className="mt-1 text-sm text-slate-500">Только показ. Жёлтая плашка убрана: «награда ждёт» показывает маленький подарок, как на цели дня.</p>
      </header>
      <section className="card flex flex-wrap items-center gap-2 p-4 text-sm">
        <span className="text-slate-500">Наград к получению:</span>
        {[0, 1, 3, 12].map((n) => (
          <button key={n} type="button" onClick={() => setCount(n)} className={`rounded-lg px-3 py-1.5 ${count === n ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>{n}</button>
        ))}
      </section>
      <section className="space-y-8 rounded-3xl p-6" style={{ background: "#0d0f1c" }}>
        <div className="mx-auto w-full max-w-sm">
          <div className="mb-2 text-xs font-bold uppercase tracking-wide text-white/50">Главная</div>
          <div className="relative flex items-center gap-3 rounded-3xl p-3.5" style={{ background: hero, boxShadow: "0 6px 16px rgba(88,98,221,0.3)" }}>
            {count > 0 && <span style={{ position: "absolute", top: -16, right: 10 }}><Gift size={36} count={count} /></span>}
            <div className="flex h-16 w-16 items-center justify-center rounded-full text-xl font-black text-white" style={{ boxShadow: "inset 0 0 0 6px rgba(255,255,255,0.25)" }}>7</div>
            <div className="min-w-0 flex-1">
              <div className="text-[17px] font-black text-white">Пропуск сезона</div>
              <div className="text-xs text-white/80">Сезон 1 · ⚡ 340</div>
              <div className="mt-2 h-[7px] overflow-hidden rounded-full bg-white/20"><div className="h-full w-3/5" style={{ background: "#ffd54f" }} /></div>
            </div>
            <span className="text-2xl text-white">›</span>
          </div>
        </div>
        <div className="mx-auto w-full max-w-sm">
          <div className="mb-2 text-xs font-bold uppercase tracking-wide text-white/50">Экран пропуска, верх</div>
          <div className="rounded-3xl p-4" style={{ background: hero }}>
            <div className="mb-3 text-lg font-black text-white">Пропуск сезона</div>
            {count > 0 && (
              <div className="flex items-center gap-2 rounded-2xl px-3 py-2" style={{ background: "rgba(255,255,255,0.16)" }}>
                <Gift size={28} count={0} />
                <span className="text-sm font-bold text-white">Наград к получению: {count}</span>
              </div>
            )}
          </div>
        </div>
      </section>
    </main>
  );
}

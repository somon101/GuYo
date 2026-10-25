import { useState } from "react";
import type { ChestType } from "../api/endpoints";

// A mock of the app's "Мои сундуки" card and list, for a preview only: nothing
// is sent anywhere. The counts are made up; prizes use the chests' real ceilings.

const BASE = `${import.meta.env.BASE_URL}`;
const PRIZES = [
  { id: "diamonds", name: "Бриллианты", img: "preview/gem.png", cap: (c: ChestType) => c.max_diamonds },
  { id: "freeze", name: "Заморозки серии", img: "preview/freeze.png", cap: (c: ChestType) => c.max_freezes },
  { id: "merge", name: "Объединители серии", img: "preview/merge.png", cap: (c: ChestType) => c.max_merges },
  { id: "points", name: "Очки рейтинга", img: null, cap: (c: ChestType) => c.max_points },
] as const;
type Totals = Record<string, { opened: number; total: number }>;

export function ChestBankMock({ types, onOpenOne }: { types: ChestType[]; onOpenOne: (key: string) => void }) {
  const [counts, setCounts] = useState<Record<string, number>>({ wood: 6, silver: 3, purple: 1, gold: 0 });
  const [screen, setScreen] = useState<"card" | "list" | "result">("card");
  const [result, setResult] = useState<{ n: number; totals: Totals } | null>(null);
  const all = types.reduce((s, c) => s + (counts[c.key] ?? 0), 0);

  const set = (key: string, d: number) => setCounts({ ...counts, [key]: Math.max(0, (counts[key] ?? 0) + d) });

  // Opens up to `n` chests (oldest first, optionally only of one kind), one random prize each.
  const openMany = (n: number, key?: string) => {
    const next = { ...counts };
    const totals: Totals = {};
    let opened = 0;
    for (const c of key ? types.filter((t) => t.key === key) : types) {
      while (opened < n && (next[c.key] ?? 0) > 0) {
        next[c.key]--; opened++;
        const possible = PRIZES.filter((p) => p.cap(c) > 0);
        const p = possible[Math.floor(Math.random() * possible.length)];
        const amount = 1 + Math.floor(Math.random() * p.cap(c));
        totals[p.id] = { opened: (totals[p.id]?.opened ?? 0) + 1, total: (totals[p.id]?.total ?? 0) + amount };
      }
    }
    if (!opened) return;
    setCounts(next);
    setResult({ n: opened, totals });
    setScreen("result");
  };

  const shell = "mx-auto w-full max-w-sm rounded-3xl p-4 text-white";
  const bg = { background: "linear-gradient(135deg,#3d2b8f,#1e1560)" };
  const btn = "rounded-xl px-3 py-2 text-sm font-bold disabled:opacity-40";
  const gold = { background: "#ffc53d", color: "#3b2600" };

  return (
    <section className="card space-y-3 p-4">
      <h2 className="text-lg font-semibold">Макет: «Мои сундуки» в приложении</h2>
      <p className="text-sm text-slate-500">
        Нажмите на карточку: откроется весь список накопленного. Можно открыть сразу несколько (1, 5, 10 или все). Количество сундуков ниже
        придумано для показа, его можно менять кнопками +/−.
      </p>

      {screen === "card" && (
        <div role="button" aria-label="Мои сундуки" className={`${shell} cursor-pointer`} style={bg} onClick={() => setScreen("list")}>
          <div className="flex items-center gap-3">
            <div className="min-w-0 flex-1">
              <div className="text-lg font-black">Мои сундуки · {all}</div>
              <div className="mt-2 flex items-center">
                {types.flatMap((c) => Array.from({ length: Math.min(counts[c.key] ?? 0, 4) }, (_, i) => (
                  <img key={`${c.key}${i}`} src={`${BASE}chests/${c.key}_closed.png`} alt="" style={{ width: 40, height: 40, objectFit: "contain" }} />
                ))).slice(0, 4)}
                {all > 4 && <span className="ml-1 font-black">+{all - 4}</span>}
              </div>
            </div>
            <span className={btn} style={gold}>Открыть</span>
          </div>
        </div>
      )}

      {screen === "list" && (
        <div className={shell} style={bg}>
          <div className="mb-3 flex items-center justify-between">
            <button className="text-sm text-white/70" onClick={() => setScreen("card")}>← Назад</button>
            <div className="text-lg font-black">Мои сундуки · {all}</div>
            <span style={{ width: 48 }} />
          </div>
          <div className="space-y-2">
            {types.map((c) => {
              const n = counts[c.key] ?? 0;
              return (
                <div key={c.key} className="rounded-2xl bg-white/10 p-3" style={{ opacity: n ? 1 : 0.55 }}>
                  <div className="flex items-center gap-3">
                    <img src={`${BASE}chests/${c.key}_closed.png`} alt="" style={{ width: 56, height: 56, objectFit: "contain" }} />
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-bold">{c.name}</div>
                      <div className="text-xs text-white/70">бриллианты до {c.max_diamonds}, очки до {c.max_points}</div>
                    </div>
                    <div className="flex items-center gap-1 text-lg font-black">
                      <button className="rounded-lg bg-white/15 px-2 text-sm" onClick={() => set(c.key, -1)}>−</button>
                      <span style={{ minWidth: 28, textAlign: "center" }}>{n}</span>
                      <button className="rounded-lg bg-white/15 px-2 text-sm" onClick={() => set(c.key, 1)}>+</button>
                    </div>
                  </div>
                  {n > 0 && (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      <button className={btn} style={gold} onClick={() => onOpenOne(c.key)}>Открыть 1</button>
                      {n >= 5 && <button className={btn} style={gold} onClick={() => openMany(5, c.key)}>Открыть 5</button>}
                      {n >= 10 && <button className={btn} style={gold} onClick={() => openMany(10, c.key)}>Открыть 10</button>}
                      {n > 1 && <button className={btn} style={gold} onClick={() => openMany(n, c.key)}>Все ({n})</button>}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
          <div className="mt-3 flex flex-wrap gap-1.5">
            <span className="w-full text-xs text-white/70">Все виды сразу:</span>
            <button className={btn} style={gold} disabled={!all} onClick={() => openMany(5)}>Открыть 5</button>
            <button className={btn} style={gold} disabled={all < 10} onClick={() => openMany(10)}>Открыть 10</button>
            <button className={btn} style={gold} disabled={!all} onClick={() => openMany(all)}>Открыть все ({all})</button>
          </div>
        </div>
      )}

      {screen === "result" && result && (
        <div className={shell} style={bg}>
          <div className="mb-3 text-center text-xl font-black">Открыто сундуков: {result.n}</div>
          <div className="space-y-2">
            {PRIZES.filter((p) => result.totals[p.id]).map((p) => (
              <div key={p.id} className="flex items-center gap-3 rounded-2xl bg-white/10 p-3">
                {p.img ? <img src={`${BASE}${p.img}`} alt="" style={{ width: 44, height: 44, objectFit: "contain" }} /> : <span style={{ fontSize: 38, color: "#ffc53d", width: 44, textAlign: "center" }}>★</span>}
                <div className="flex-1">
                  <div className="text-2xl font-black">+{result.totals[p.id].total}</div>
                  <div className="text-xs text-white/70">{p.name} · из {result.totals[p.id].opened} сундук(ов)</div>
                </div>
              </div>
            ))}
          </div>
          <div className="mt-3 text-center">
            <button className={btn} style={gold} onClick={() => setScreen(all ? "list" : "card")}>Забрать</button>
          </div>
        </div>
      )}
    </section>
  );
}

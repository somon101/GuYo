import { useState } from "react";
import type { ChestType } from "../api/endpoints";

// A mock of the app's "Мои сундуки" card and list, for a preview only: nothing
// is sent anywhere. The counts are made up; prizes use the chests' real ceilings.

const BASE = `${import.meta.env.BASE_URL}`;

/** The one big "open" button: bright candy green with a thick edge, like a game's play button. */
const playButton: React.CSSProperties = {
  background: "linear-gradient(180deg,#9dff72 0%,#3fd43a 48%,#1ea82c 100%)",
  boxShadow: "0 4px 0 #0f6b1d, 0 8px 12px rgba(0,0,0,0.35), inset 0 2px 0 rgba(255,255,255,0.7), inset 0 -2px 0 rgba(0,0,0,0.12)",
  border: "2px solid #0f6b1d",
  color: "#fff",
  textShadow: "0 2px 0 #0f6b1d, 0 0 6px rgba(0,60,0,0.6)",
  letterSpacing: 0.6,
};

export function ChestBankMock({ types, onOpen }: { types: ChestType[]; onOpen: (key: string, count: number) => void }) {
  const [counts, setCounts] = useState<Record<string, number>>({ wood: 6, silver: 3, purple: 1, gold: 0 });
  const [mode, setMode] = useState<Record<string, number>>({});
  const [screen, setScreen] = useState<"card" | "list">("card");
  const all = types.reduce((s, c) => s + (counts[c.key] ?? 0), 0);

  const set = (key: string, d: number) => setCounts({ ...counts, [key]: Math.max(0, (counts[key] ?? 0) + d) });

  const shell = "mx-auto w-full max-w-sm rounded-3xl p-4 text-white";
  const bg = { background: "linear-gradient(135deg,#3d2b8f,#1e1560)" };

  return (
    <section className="card space-y-3 p-4">
      <h2 className="text-lg font-semibold">Макет: «Мои сундуки» в приложении</h2>
      <p className="text-sm text-slate-500">
        Нажмите на карточку: откроется весь список накопленного. У каждого вида одна кнопка «Открыть». Если сундуков меньше 5, они открываются по одному. От 5 появляется ×5, от 10 появляется ×10 (например при 7: сначала ×5, затем два оставшихся по одному). Анимация при этом показывается на сцене выше (из сундука вылетает столько призов, сколько сундуков открыто). Сундуки разных видов за один раз не открываются: только один вид. Количество сундуков ниже
        придумано для показа, его можно менять кнопками +/−.
      </p>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="text-slate-500">Набор для проверки:</span>
        {[["3 / 1 / 0 / 0", [3, 1, 0, 0]], ["7 / 4 / 1 / 0", [7, 4, 1, 0]], ["12 / 10 / 5 / 2", [12, 10, 5, 2]]].map(([label, v]) => (
          <button key={label as string} type="button" className="rounded-lg border border-slate-300 px-3 py-1 text-slate-700"
            onClick={() => { const arr = v as number[]; setCounts(Object.fromEntries(types.map((c, i) => [c.key, arr[i] ?? 0]))); setMode({}); }}>
            {label as string}
          </button>
        ))}
        <span className="text-xs text-slate-400">(дерево / серебро / фиолет / золото)</span>
      </div>

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
            <span className="rounded-xl px-4 py-2 text-sm font-black uppercase" style={playButton}>Открыть</span>
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
                    <div className="rounded-full px-3 py-1 text-base font-black" style={{ background: "rgba(0,0,0,0.3)", boxShadow: `inset 0 0 0 2px ${c.color}` }}>×{n}</div>
                  </div>
                  {n > 0 && (() => {
                    const mult = Math.min(mode[c.key] ?? 1, n >= 10 ? 10 : n >= 5 ? 5 : 1);
                    const m = mult >= 10 && n >= 10 ? 10 : mult >= 5 && n >= 5 ? 5 : 1;
                    const options = [1, 5, 10].filter((x) => x === 1 || n >= x);
                    return (
                      <div className="mt-2 flex items-center gap-2">
                        {options.length > 1 && (
                          <div className="flex gap-1">
                            {options.map((x) => (
                              <button key={x} onClick={() => setMode({ ...mode, [c.key]: x })}
                                className="rounded-lg px-2.5 py-1 text-sm font-black transition active:scale-95"
                                style={m === x
                                  ? { background: "linear-gradient(180deg,#ffe56b,#ffab1a)", color: "#4a2a00", boxShadow: "0 2px 0 #b36a00, inset 0 1px 0 rgba(255,255,255,0.7)" }
                                  : { background: "rgba(255,255,255,0.14)", color: "rgba(255,255,255,0.85)", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.25)" }}>
                                ×{x}
                              </button>
                            ))}
                          </div>
                        )}
                        <button className="flex-1 rounded-xl px-3 py-2 text-sm font-black uppercase transition active:translate-y-0.5" style={playButton} onClick={() => { onOpen(c.key, m); set(c.key, -m); }}>
                          Открыть{m > 1 ? ` ×${m}` : ""}
                        </button>
                      </div>
                    );
                  })()}
                </div>
              );
            })}
          </div>
        </div>
      )}

    </section>
  );
}

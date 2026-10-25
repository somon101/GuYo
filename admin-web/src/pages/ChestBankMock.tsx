import { useState } from "react";
import type { ChestType } from "../api/endpoints";

// A mock of the app's "Мои сундуки" card and list, for a preview only: nothing
// is sent anywhere. The counts are made up; prizes use the chests' real ceilings.

const BASE = `${import.meta.env.BASE_URL}`;

function mix(hex: string, to: number, k: number): string {
  const n = parseInt(hex.slice(1), 16);
  const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => Math.round(v + (to - v) * k));
  return `rgb(${ch[0]},${ch[1]},${ch[2]})`;
}

/** A glossy, pressable button in the chest's own colour. */
function chestButton(color: string): React.CSSProperties {
  return {
    background: `linear-gradient(180deg, ${mix(color, 255, 0.45)} 0%, ${color} 50%, ${mix(color, 0, 0.22)} 100%)`,
    boxShadow: `0 4px 0 ${mix(color, 0, 0.5)}, 0 9px 14px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.65), inset 0 -2px 0 rgba(0,0,0,0.12)`,
    color: "#fff",
    textShadow: "0 1px 2px rgba(0,0,0,0.5)",
    border: "1px solid rgba(255,255,255,0.35)",
    letterSpacing: 0.2,
  };
}

export function ChestBankMock({ types, onOpen }: { types: ChestType[]; onOpen: (key: string, count: number) => void }) {
  const [counts, setCounts] = useState<Record<string, number>>({ wood: 6, silver: 3, purple: 1, gold: 0 });
  const [mode, setMode] = useState<Record<string, number>>({});
  const [screen, setScreen] = useState<"card" | "list">("card");
  const all = types.reduce((s, c) => s + (counts[c.key] ?? 0), 0);

  const set = (key: string, d: number) => setCounts({ ...counts, [key]: Math.max(0, (counts[key] ?? 0) + d) });

  const shell = "mx-auto w-full max-w-sm rounded-3xl p-4 text-white";
  const bg = { background: "linear-gradient(135deg,#3d2b8f,#1e1560)" };
  const btn = "rounded-xl px-4 py-2 text-sm font-extrabold transition active:translate-y-0.5 disabled:opacity-40";

  return (
    <section className="card space-y-3 p-4">
      <h2 className="text-lg font-semibold">Макет: «Мои сундуки» в приложении</h2>
      <p className="text-sm text-slate-500">
        Нажмите на карточку: откроется весь список накопленного. У каждого вида одна кнопка «Открыть» и переключатель ×1 / ×5 / ×10: ×5 открывает сразу 5 сундуков, ×10 сразу 10; если сундуков меньше, доступен только меньший вариант (например при 7: сначала ×5, затем два оставшихся по одному). Анимация при этом показывается на сцене выше (из сундука вылетает столько призов, сколько сундуков открыто). Сундуки разных видов за один раз не открываются: только один вид. Количество сундуков ниже
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
            <span className={btn} style={chestButton(types.find((c) => (counts[c.key] ?? 0) > 0)?.color ?? "#f5b700")}>Открыть</span>
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
                  {n > 0 && (() => {
                    const mult = Math.min(mode[c.key] ?? 1, n >= 10 ? 10 : n >= 5 ? 5 : 1);
                    const m = mult >= 10 && n >= 10 ? 10 : mult >= 5 && n >= 5 ? 5 : 1;
                    return (
                      <div className="mt-3 flex items-center gap-2">
                        <div className="flex rounded-xl bg-black/25 p-1">
                          {[1, 5, 10].map((x) => (
                            <button key={x} disabled={n < x} onClick={() => setMode({ ...mode, [c.key]: x })}
                              className="rounded-lg px-3 py-1 text-sm font-black disabled:opacity-30"
                              style={m === x ? { background: "rgba(255,255,255,0.92)", color: "#2a1a6b" } : { color: "rgba(255,255,255,0.75)" }}>
                              ×{x}
                            </button>
                          ))}
                        </div>
                        <button className={`${btn} flex-1`} style={chestButton(c.color)} onClick={() => { onOpen(c.key, m); set(c.key, -m); }}>
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

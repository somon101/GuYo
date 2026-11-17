import { useMemo, useState } from "react";

// Макет раздела «Аватар»: файл «Выгрузить для GuYo» из Студии аватаров (формат avatar-items/1).
// Файл читается прямо в браузере, на сервер пока ничего не уходит. Страница показывает то, как это будет:
// каталог деталей по слотам и полу (у каждой свой ID и своё положение) и сборка аватара, где выбранная
// деталь встаёт на место сама. Редактора положения здесь нет: всё настраивается в Студии.

type Place = { x: number; y: number; w: number; r: number; pivot: string };
type Item = {
  id: string;
  slot: string;
  gender: "male" | "female" | "both";
  name: string;
  set: { id: string; name: string };
  ownPlace: boolean;
  width: number;
  height: number;
  place: Partial<Record<"male" | "female", Place>>;
  png: string;
};
type Pack = { format: string; canvas: { w: number; h: number }; slots: { id: string; name: string }[]; items: Item[] };
type Gender = "male" | "female";

const GENDER_LABEL: Record<Item["gender"], string> = { male: "мужская", female: "женская", both: "обе" };

function rectOf(it: Item, p: Place) {
  const h = (it.height * p.w) / it.width;
  const top = p.pivot === "top" ? p.y : p.pivot === "bottom" ? p.y - h : p.y - h / 2;
  return { left: p.x - p.w / 2, top, width: p.w, height: h };
}

/** Аватар: слои по порядку слотов, у каждой выбранной детали своё положение, поворот вокруг точки привязки. */
function AvatarPreview({ pack, gender, pick, scale }: { pack: Pack; gender: Gender; pick: Record<string, string>; scale: number }) {
  const { w, h } = pack.canvas;
  return (
    <div style={{ width: w * scale, height: h * scale, position: "relative", overflow: "hidden", borderRadius: 18, background: "repeating-conic-gradient(#e6e8f2 0 25%, #fff 0 50%) 0 0/24px 24px" }}>
      <div style={{ width: w, height: h, transform: `scale(${scale})`, transformOrigin: "top left", position: "absolute", left: 0, top: 0 }}>
        {pack.slots.map((s) => {
          const it = pack.items.find((x) => x.id === pick[s.id]);
          const p = it?.place[gender];
          if (!it || !p) return null;
          const r = rectOf(it, p);
          return (
            <img
              key={s.id}
              src={`data:image/png;base64,${it.png}`}
              alt={it.name}
              style={{ position: "absolute", left: r.left, top: r.top, width: r.width, height: r.height, transformOrigin: `${p.x - r.left}px ${p.y - r.top}px`, transform: `rotate(${p.r}deg)` }}
            />
          );
        })}
      </div>
    </div>
  );
}

export function AvatarItemsMockPage() {
  const [pack, setPack] = useState<Pack | null>(null);
  const [error, setError] = useState("");
  const [gender, setGender] = useState<Gender>("female");
  const [picks, setPicks] = useState<Record<Gender, Record<string, string>>>({ male: {}, female: {} });

  const load = async (file: File | undefined) => {
    if (!file) return;
    try {
      const j = JSON.parse(await file.text()) as Pack;
      if (j.format !== "avatar-items/1" || !Array.isArray(j.items)) throw new Error("format");
      setPack(j);
      setError("");
      // сразу показываем по одной детали на слот, чтобы было видно сборку
      const next: Record<Gender, Record<string, string>> = { male: {}, female: {} };
      for (const g of ["male", "female"] as Gender[]) {
        for (const s of j.slots) {
          const first = j.items.find((i) => i.slot === s.id && i.place[g]);
          if (first) next[g][s.id] = first.id;
        }
      }
      setPicks(next);
    } catch {
      setError("Это не файл из Студии аватаров. Нужен файл «Выгрузить для GuYo» (guyo-avatar-items.json).");
    }
  };

  const pick = picks[gender];
  const bySlot = useMemo(() => {
    if (!pack) return [];
    return pack.slots
      .filter((s) => pack.items.some((i) => i.slot === s.id)) // слоты, где в файле вообще нет деталей, не показываем
      .map((s) => ({ slot: s, items: pack.items.filter((i) => i.slot === s.id && i.place[gender]) }));
  }, [pack, gender]);
  const total = pack?.items.length ?? 0;
  const own = pack?.items.filter((i) => i.ownPlace).length ?? 0;

  return (
    <main className="mx-auto max-w-5xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Аватар: детали из Студии <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 align-middle text-xs font-semibold text-amber-700">макет</span></h1>
        <p className="mt-1 text-sm text-slate-500">
          Все положения настраиваются в Студии аватаров, здесь их ничего не меняют. Загрузите файл «Выгрузить для GuYo»: у каждой детали свой ID и своё положение, игрок просто выбирает деталь, а она сама встаёт на место.
        </p>
      </header>

      <section className="card space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-3">
          <label className="cursor-pointer rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">
            Загрузить файл из Студии
            <input type="file" accept="application/json,.json" className="hidden" onChange={(e) => void load(e.target.files?.[0])} />
          </label>
          {pack && <span className="text-sm text-slate-500">Деталей: {total}, со своим положением: {own}</span>}
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        {!pack && !error && <p className="text-sm text-slate-500">Файл читается в браузере и пока никуда не отправляется. После утверждения макета загрузка будет сохранять детали на сервере (повторная загрузка обновляет по ID, без дублей).</p>}
      </section>

      {pack && (
        <div className="grid gap-5 md:grid-cols-[300px_1fr]">
          <section className="card space-y-3 p-4">
            <h2 className="text-lg font-semibold">Как увидит игрок</h2>
            <div className="flex gap-2">
              {(["male", "female"] as Gender[]).map((g) => (
                <button key={g} type="button" onClick={() => setGender(g)} className={`rounded-lg px-3 py-1.5 text-sm ${gender === g ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>{g === "male" ? "Мужской" : "Женский"}</button>
              ))}
            </div>
            <AvatarPreview pack={pack} gender={gender} pick={pick} scale={268 / pack.canvas.w} />
            <p className="text-xs text-slate-500">Выбор детали справа сразу ставит её на место по её собственным координатам.</p>
          </section>

          <div className="space-y-4">
            {bySlot.map(({ slot, items }) => (
              <section key={slot.id} className="card space-y-2 p-4">
                <h2 className="text-lg font-semibold">{slot.name} <span className="text-sm font-normal text-slate-500">({items.length})</span></h2>
                {items.length === 0 && <p className="text-sm text-slate-500">Для этого персонажа деталей нет.</p>}
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                  {items.map((it) => {
                    const p = it.place[gender]!;
                    const on = pick[slot.id] === it.id;
                    return (
                      <button
                        key={it.id}
                        type="button"
                        onClick={() => setPicks({ ...picks, [gender]: { ...pick, [slot.id]: on ? "" : it.id } })}
                        className="rounded-2xl p-2 text-left"
                        style={{ background: "#12151f", outline: on ? "3px solid #6366f1" : "1px solid #2a2f45" }}
                      >
                        <div className="flex h-24 items-center justify-center">
                          <img src={`data:image/png;base64,${it.png}`} alt="" style={{ maxWidth: "100%", maxHeight: 96, objectFit: "contain" }} />
                        </div>
                        <div className="truncate text-xs font-bold text-white">{it.name}</div>
                        <div className="text-[10px] text-white/50">для: {GENDER_LABEL[it.gender]} · {it.ownPlace ? "своё положение" : "стандарт слота"}</div>
                        <div className="truncate text-[10px] text-white/40" title={it.id}>ID {it.id}</div>
                        <div className="text-[10px] text-white/60">x {Math.round(p.x)} · y {Math.round(p.y)} · ширина {Math.round(p.w)}{p.r ? ` · поворот ${p.r}°` : ""}</div>
                      </button>
                    );
                  })}
                </div>
              </section>
            ))}
          </div>
        </div>
      )}
    </main>
  );
}

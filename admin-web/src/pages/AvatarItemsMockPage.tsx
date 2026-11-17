import { useMemo, useState } from "react";

// Макет создания аватара в GuYo. Берёт файл «Выгрузить для GuYo» из Студии аватаров (формат avatar-items/1)
// и показывает, как игрок собирает аватар: пол, затем по шагам детали (причёска, лицо, одежда и т. д.), затем фон.
// Положения не правятся ни здесь, ни в приложении: каждая деталь встаёт по своему положению из Студии.
// Файл читается в браузере, на сервер пока ничего не уходит.

type Place = { x: number; y: number; w: number; r: number; pivot: string };
type Item = {
  id: string;
  slot: string;
  gender: "male" | "female" | "both";
  name: string;
  ownPlace: boolean;
  width: number;
  height: number;
  place: Partial<Record<"male" | "female", Place>>;
  png: string;
};
type Bg = { id: string; name: string; kind: "solid" | "grad" | "img"; c1?: string; c2?: string; width?: number; height?: number; place?: { x: number; y: number; s: number }; png?: string };
type Pack = {
  format: string;
  canvas: { w: number; h: number };
  frame?: { x: number; y: number; size: number; shape: string };
  slots: { id: string; name: string }[];
  items: Item[];
  backgrounds?: Bg[];
};
type Gender = "male" | "female";
type Picks = { slots: Record<string, string>; bg: string };

const GENDER_LABEL: Record<Item["gender"], string> = { male: "мужская", female: "женская", both: "обе" };
const empty = (): Picks => ({ slots: {}, bg: "" });

function rectOf(it: Item, p: Place) {
  const h = (it.height * p.w) / it.width;
  const top = p.pivot === "top" ? p.y : p.pivot === "bottom" ? p.y - h : p.y - h / 2;
  return { left: p.x - p.w / 2, top, width: p.w, height: h };
}

/** Аватар: фон и слои по порядку слотов. view «frame» это то, что сохранится как аватарка (кадр из Студии), «full» весь холст. */
function Scene({ pack, gender, picks, view, px, circle }: { pack: Pack; gender: Gender; picks: Picks; view: "frame" | "full"; px: number; circle?: boolean }) {
  const { w: W, h: H } = pack.canvas;
  const f = pack.frame ?? { x: W / 2, y: 560, size: 760, shape: "circle" };
  const area = view === "frame" ? { left: f.x - f.size / 2, top: f.y - f.size / 2, w: f.size, h: f.size } : { left: 0, top: 0, w: W, h: H };
  const k = px / area.w;
  const bg = pack.backgrounds?.find((b) => b.id === picks.bg);
  let bgNode: React.ReactNode = null;
  if (bg?.kind === "solid") bgNode = <div style={{ position: "absolute", inset: 0, background: bg.c1 }} />;
  else if (bg?.kind === "grad") bgNode = <div style={{ position: "absolute", inset: 0, background: `linear-gradient(135deg, ${bg.c1}, ${bg.c2})` }} />;
  else if (bg?.kind === "img" && bg.png && bg.width && bg.height && bg.place) {
    const kk = Math.max(area.w / bg.width, area.h / bg.height) * bg.place.s;
    const bw = bg.width * kk, bh = bg.height * kk;
    bgNode = <img alt="" src={`data:image/png;base64,${bg.png}`} style={{ position: "absolute", left: (area.w - bw) / 2 + (bg.place.x / 100) * area.w, top: (area.h - bh) / 2 + (bg.place.y / 100) * area.h, width: bw, height: bh, maxWidth: "none" }} />;
  }
  return (
    <div style={{ width: px, height: area.h * k, position: "relative", overflow: "hidden", borderRadius: circle ? "50%" : 18, background: bg ? undefined : "repeating-conic-gradient(#e6e8f2 0 25%, #fff 0 50%) 0 0/20px 20px" }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: area.w, height: area.h, transform: `scale(${k})`, transformOrigin: "top left" }}>
        {bgNode}
        <div style={{ position: "absolute", left: -area.left, top: -area.top, width: W, height: H }}>
          {pack.slots.map((s) => {
            const it = pack.items.find((x) => x.id === picks.slots[s.id]);
            const p = it?.place[gender];
            if (!it || !p) return null;
            const r = rectOf(it, p);
            return (
              <img key={s.id} alt={it.name} src={`data:image/png;base64,${it.png}`} style={{ position: "absolute", maxWidth: "none", left: r.left, top: r.top, width: r.width, height: r.height, transformOrigin: `${p.x - r.left}px ${p.y - r.top}px`, transform: `rotate(${p.r}deg)` }} />
            );
          })}
        </div>
      </div>
    </div>
  );
}

function BgSwatch({ bg, size = 44 }: { bg: Bg; size?: number }) {
  const style: React.CSSProperties = { width: size, height: size, borderRadius: 12, overflow: "hidden", position: "relative", background: bg.kind === "solid" ? bg.c1 : bg.kind === "grad" ? `linear-gradient(135deg, ${bg.c1}, ${bg.c2})` : "#e6e8f2" };
  return <div style={style}>{bg.kind === "img" && bg.png && <img alt="" src={`data:image/png;base64,${bg.png}`} style={{ width: "100%", height: "100%", objectFit: "cover" }} />}</div>;
}

export function AvatarItemsMockPage() {
  const [pack, setPack] = useState<Pack | null>(null);
  const [error, setError] = useState("");
  const [gender, setGender] = useState<Gender | null>(null);
  const [step, setStep] = useState(0); // 0 пол, 1..n слоты, n+1 фон
  const [picks, setPicks] = useState<Record<Gender, Picks>>({ male: empty(), female: empty() });
  const [done, setDone] = useState(false);

  const load = async (file: File | undefined) => {
    if (!file) return;
    try {
      const j = JSON.parse(await file.text()) as Pack;
      if (j.format !== "avatar-items/1" || !Array.isArray(j.items)) throw new Error("format");
      setPack(j);
      setError("");
      setGender(null);
      setStep(0);
      setPicks({ male: empty(), female: empty() });
      setDone(false);
    } catch {
      setError("Это не файл из Студии аватаров. Нужен файл «Выгрузить для GuYo» (guyo-avatar-items.json).");
    }
  };

  // шаги: слоты, где для выбранного пола есть детали
  const stepSlots = useMemo(() => (pack && gender ? pack.slots.filter((s) => pack.items.some((i) => i.slot === s.id && i.place[gender])) : []), [pack, gender]);
  const hasBg = (pack?.backgrounds?.length ?? 0) > 0;
  const lastStep = stepSlots.length + (hasBg ? 1 : 0);
  const cur = gender ? picks[gender] : empty();

  const choose = (g: Gender) => {
    setGender(g);
    setStep(1);
    setDone(false);
    if (!pack) return;
    // сразу ставим первую подходящую деталь в каждом слоте: игрок видит аватар и меняет по шагам
    setPicks((p) => {
      if (Object.keys(p[g].slots).length) return p;
      const slots: Record<string, string> = {};
      for (const s of pack.slots) {
        const first = pack.items.find((i) => i.slot === s.id && i.place[g]);
        if (first) slots[s.id] = first.id;
      }
      return { ...p, [g]: { slots, bg: pack.backgrounds?.[0]?.id ?? "" } };
    });
  };
  const setSlotPick = (slot: string, id: string) => gender && setPicks({ ...picks, [gender]: { ...cur, slots: { ...cur.slots, [slot]: id } } });
  const setBgPick = (id: string) => gender && setPicks({ ...picks, [gender]: { ...cur, bg: id } });

  const stepSlot = step >= 1 && step <= stepSlots.length ? stepSlots[step - 1] : null;
  const onBgStep = hasBg && step === stepSlots.length + 1;
  const title = step === 0 ? "Кто вы?" : stepSlot ? stepSlot.name : onBgStep ? "Фон" : "Готово";

  return (
    <main className="mx-auto max-w-5xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Аватар: создание игроком <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 align-middle text-xs font-semibold text-amber-700">макет</span></h1>
        <p className="mt-1 text-sm text-slate-500">
          Так игрок создаёт аватарку вместо загрузки фото: выбирает пол, потом по шагам причёску, лицо, одежду и т. д., в конце фон. Положения деталей задаются в Студии, игрок их не расставляет. Загрузите файл «Выгрузить для GuYo», чтобы посмотреть.
        </p>
      </header>

      <section className="card space-y-2 p-4">
        <div className="flex flex-wrap items-center gap-3">
          <label className="cursor-pointer rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">
            Загрузить файл из Студии
            <input type="file" accept="application/json,.json" className="hidden" onChange={(e) => void load(e.target.files?.[0])} />
          </label>
          {pack && <span className="text-sm text-slate-500">Деталей: {pack.items.length}, со своим положением: {pack.items.filter((i) => i.ownPlace).length}, фонов: {pack.backgrounds?.length ?? 0}</span>}
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        {!pack && !error && <p className="text-sm text-slate-500">Файл читается в браузере и пока никуда не отправляется. После утверждения макета загрузка будет сохранять детали на сервере (повторная загрузка обновляет по ID, без дублей).</p>}
      </section>

      {pack && (
        <div className="grid gap-5 md:grid-cols-[360px_1fr]">
          {/* экран создания, как в приложении */}
          <section className="card mx-auto w-full max-w-[360px] space-y-3 p-4" style={{ borderRadius: 28 }}>
            <div className="flex items-center justify-between">
              <button type="button" disabled={step === 0} onClick={() => { setDone(false); setStep(step - 1); }} className="rounded-lg border border-slate-300 px-3 py-1 text-sm text-slate-700 disabled:opacity-30">Назад</button>
              <h2 className="text-lg font-semibold">{title}</h2>
              <span className="w-14 text-right text-xs text-slate-400">{step === 0 ? "" : `${Math.min(step, lastStep)} из ${lastStep}`}</span>
            </div>

            {gender && step > 0 && (
              <div className="flex justify-center">
                <Scene pack={pack} gender={gender} picks={cur} view="frame" px={220} circle={pack.frame?.shape !== "round"} />
              </div>
            )}

            {step === 0 && (
              <div className="grid grid-cols-2 gap-3 py-2">
                {(["male", "female"] as Gender[]).map((g) => (
                  <button key={g} type="button" onClick={() => choose(g)} className="rounded-2xl border border-slate-300 p-4 text-base font-semibold text-slate-800 hover:border-indigo-500">{g === "male" ? "Парень" : "Девушка"}</button>
                ))}
              </div>
            )}

            {stepSlot && gender && (
              <div className="grid grid-cols-3 gap-2">
                {pack.items.filter((i) => i.slot === stepSlot.id && i.place[gender]).map((it) => {
                  const on = cur.slots[stepSlot.id] === it.id;
                  return (
                    <button key={it.id} type="button" onClick={() => setSlotPick(stepSlot.id, it.id)} className="rounded-xl p-1.5" style={{ background: "#12151f", outline: on ? "3px solid #6366f1" : "1px solid #2a2f45" }}>
                      <div className="flex h-16 items-center justify-center"><img alt="" src={`data:image/png;base64,${it.png}`} style={{ maxWidth: "100%", maxHeight: 62, objectFit: "contain" }} /></div>
                    </button>
                  );
                })}
              </div>
            )}

            {onBgStep && (
              <div className="grid grid-cols-5 gap-2">
                {pack.backgrounds!.map((b) => (
                  <button key={b.id} type="button" onClick={() => setBgPick(b.id)} className="rounded-xl p-0.5" style={{ outline: cur.bg === b.id ? "3px solid #6366f1" : "1px solid #cbd5e1" }}>
                    <BgSwatch bg={b} size={52} />
                  </button>
                ))}
              </div>
            )}

            {gender && step > 0 && (
              <button
                type="button"
                onClick={() => (step >= lastStep ? setDone(true) : setStep(step + 1))}
                className="w-full rounded-xl bg-indigo-600 py-2.5 text-sm font-bold text-white"
              >
                {step >= lastStep ? "Готово" : "Дальше"}
              </button>
            )}
            {done && <p className="text-center text-sm font-semibold text-emerald-600">Аватар сохранён (в макете ничего не отправляется)</p>}
          </section>

          {/* справа: как выглядит целиком и каталог для проверки */}
          <div className="space-y-4">
            {gender && (
              <section className="card space-y-2 p-4">
                <h2 className="text-lg font-semibold">Целиком и в профиле</h2>
                <div className="flex flex-wrap items-end gap-4">
                  <Scene pack={pack} gender={gender} picks={cur} view="full" px={180} />
                  <div className="space-y-1 text-center text-xs text-slate-500"><Scene pack={pack} gender={gender} picks={cur} view="frame" px={96} circle /><div>в списке</div></div>
                  <div className="space-y-1 text-center text-xs text-slate-500"><Scene pack={pack} gender={gender} picks={cur} view="frame" px={44} circle /><div>мелко</div></div>
                </div>
              </section>
            )}
            <section className="card space-y-3 p-4">
              <h2 className="text-lg font-semibold">Каталог (для проверки)</h2>
              <p className="text-xs text-slate-500">Только просмотр: у каждой детали свой ID и своё положение из Студии.</p>
              {pack.slots.filter((s) => pack.items.some((i) => i.slot === s.id)).map((s) => (
                <div key={s.id} className="space-y-1">
                  <h3 className="text-sm font-semibold">{s.name}</h3>
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                    {pack.items.filter((i) => i.slot === s.id).map((it) => {
                      const g = gender ?? (it.place.female ? "female" : "male");
                      const p = it.place[g] ?? it.place.male ?? it.place.female!;
                      return (
                        <div key={it.id} className="rounded-xl p-2" style={{ background: "#12151f" }}>
                          <div className="flex h-16 items-center justify-center"><img alt="" src={`data:image/png;base64,${it.png}`} style={{ maxWidth: "100%", maxHeight: 62, objectFit: "contain" }} /></div>
                          <div className="truncate text-xs font-bold text-white">{it.name}</div>
                          <div className="text-[10px] text-white/50">для: {GENDER_LABEL[it.gender]} · {it.ownPlace ? "своё положение" : "стандарт слота"}</div>
                          <div className="truncate text-[10px] text-white/40" title={it.id}>ID {it.id}</div>
                          <div className="text-[10px] text-white/60">x {Math.round(p.x)} · y {Math.round(p.y)} · ширина {Math.round(p.w)}{p.r ? ` · поворот ${p.r}°` : ""}</div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              ))}
            </section>
          </div>
        </div>
      )}
    </main>
  );
}

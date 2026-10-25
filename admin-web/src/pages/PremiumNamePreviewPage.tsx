import { BadgeMark, useCatalog } from "../components/rewardVisuals";

// A preview only: how a Premium player's name stands out, in modern app styles. At most one icon
// next to a name: the badge the person chose; a Premium person with none gets the Premium «G».

const BASE = `${import.meta.env.BASE_URL}`;
const css = `
@keyframes pn-flow { 0% { background-position: 0% 50%; } 100% { background-position: 300% 50%; } }
@keyframes pn-pearl { 0% { background-position: 0% 50%; } 100% { background-position: 200% 50%; } }
`;

type Style = "aurora" | "glass" | "pearl" | "glow" | "bar" | "ink";

/** The name, styled. `dark` picks light or dark variants of the same idea. */
function PremiumName({ text, style, dark }: { text: string; style: Style; dark: boolean }) {
  const base = { fontWeight: 800, letterSpacing: 0.1 } as const;
  switch (style) {
    case "aurora": // a slow, flowing indigo → cyan → violet gradient, like modern AI-assistant UIs
      return <span style={{ ...base, backgroundImage: dark ? "linear-gradient(90deg,#8b93ff,#4cc9f0,#c084fc,#8b93ff)" : "linear-gradient(90deg,#4338ca,#0891b2,#9333ea,#4338ca)", backgroundSize: "300% 100%", WebkitBackgroundClip: "text", color: "transparent", animation: "pn-flow 7s linear infinite" }}>{text}</span>;
    case "glass": // a frosted pill with a hairline gradient border
      return (
        <span style={{ ...base, display: "inline-block", padding: "1px 9px", borderRadius: 999, color: dark ? "#fff" : "#1b1247", background: dark ? "rgba(255,255,255,0.08)" : "rgba(88,98,221,0.08)", boxShadow: `inset 0 0 0 1px ${dark ? "rgba(255,255,255,0.28)" : "rgba(88,98,221,0.35)"}, 0 0 14px ${dark ? "rgba(139,147,255,0.35)" : "rgba(88,98,221,0.18)"}` }}>{text}</span>
      );
    case "pearl": // iridescent pearl: pink / mint / lilac drifting
      return <span style={{ ...base, backgroundImage: dark ? "linear-gradient(100deg,#ffd6f1,#c7f0ff,#e4d4ff,#ffe9d6,#ffd6f1)" : "linear-gradient(100deg,#c026a3,#0e8aa8,#7c3aed,#d9622b,#c026a3)", backgroundSize: "200% 100%", WebkitBackgroundClip: "text", color: "transparent", animation: "pn-pearl 8s linear infinite" }}>{text}</span>;
    case "glow": // plain bright name on a soft coloured glow
      return <span style={{ ...base, color: dark ? "#fff" : "#1b1247", textShadow: dark ? "0 0 12px rgba(139,147,255,0.95), 0 0 2px rgba(139,147,255,0.8)" : "0 0 10px rgba(88,98,221,0.45)" }}>{text}</span>;
    case "bar": // a thin gradient bar before the name
      return (
        <span style={{ ...base, display: "inline-flex", alignItems: "center", gap: 6, color: dark ? "#fff" : "#1b1247" }}>
          <span style={{ width: 3, alignSelf: "stretch", minHeight: "1em", borderRadius: 2, background: "linear-gradient(180deg,#8b93ff,#c084fc)" }} />{text}
        </span>
      );
    default: // ink: very light weight contrast, tinted indigo, nothing else
      return <span style={{ ...base, fontWeight: 900, color: dark ? "#b7bcff" : "#3730a3" }}>{text}</span>;
  }
}

type Person = { name: string; premium: boolean; badge: boolean };
const PEOPLE: Person[] = [
  { name: "somon", premium: true, badge: true },
  { name: "sirat", premium: true, badge: false },
  { name: "vaygo", premium: false, badge: true },
  { name: "zafar", premium: false, badge: false },
];

function NameLine({ p, style, dark, size = 15, badgeKey }: { p: Person; style: Style; dark: boolean; size?: number; badgeKey: string | null }) {
  const color = dark ? "#fff" : "#1b1247";
  return (
    <span className="inline-flex items-center gap-1.5" style={{ fontSize: size }}>
      {p.premium ? <PremiumName text={p.name} style={style} dark={dark} /> : <span style={{ fontWeight: 700, color }}>{p.name}</span>}
      {p.badge ? (badgeKey ? <BadgeMark badgeKey={badgeKey} size={size * 1.3} /> : <img src={`${BASE}preview/gem.png`} alt="" style={{ width: size * 1.3, height: size * 1.3 }} />) : p.premium ? <img src={`${BASE}preview/premium.png`} alt="" style={{ width: size * 1.2, height: size * 1.2 }} /> : null}
    </span>
  );
}

function Panel({ dark, style, badgeKey }: { dark: boolean; style: Style; badgeKey: string | null }) {
  const bg = dark ? "#12151f" : "#f4f5fa";
  return (
    <div className="space-y-1.5 rounded-2xl p-2.5" style={{ background: dark ? "#0d0f1c" : "#ffffff", boxShadow: dark ? undefined : "inset 0 0 0 1px #e5e7eb" }}>
      <div className="flex items-end justify-around rounded-xl p-2" style={{ background: bg }}>
        {PEOPLE.slice(0, 3).map((p, i) => (
          <div key={p.name} className="flex flex-col items-center gap-1">
            <span className="flex items-center justify-center rounded-full text-sm font-black text-white" style={{ width: i === 0 ? 46 : 36, height: i === 0 ? 46 : 36, background: "linear-gradient(135deg,#8b93ff,#5862dd)" }}>{p.name[0].toUpperCase()}</span>
            <NameLine p={p} style={style} dark={dark} size={i === 0 ? 13 : 11} badgeKey={badgeKey} />
          </div>
        ))}
      </div>
      {PEOPLE.map((p, i) => (
        <div key={p.name} className="flex items-center gap-2 rounded-xl px-2.5 py-1.5" style={{ background: bg }}>
          <span className="w-3 text-[10px] opacity-50" style={{ color: dark ? "#fff" : "#1b1247" }}>{i + 4}</span>
          <span className="flex h-7 w-7 items-center justify-center rounded-full text-[11px] font-black text-white" style={{ background: "linear-gradient(135deg,#f472b6,#be185d)" }}>{p.name[0].toUpperCase()}</span>
          <NameLine p={p} style={style} dark={dark} size={14} badgeKey={badgeKey} />
        </div>
      ))}
    </div>
  );
}

const VARIANTS: { id: Style; title: string; note: string }[] = [
  { id: "aurora", title: "1 · Аврора", note: "Ник плавно переливается индиго → голубой → фиолетовый. Современно, как в новых ИИ-приложениях." },
  { id: "glass", title: "2 · Стекло", note: "Ник в матовой «таблетке» с тонкой светящейся рамкой. Чисто и технологично." },
  { id: "pearl", title: "3 · Жемчуг", note: "Перламутровый переливающийся ник: розовый, мятный, сиреневый." },
  { id: "glow", title: "4 · Свечение", note: "Яркий ник с мягким цветным свечением вокруг букв." },
  { id: "bar", title: "5 · Полоса", note: "Тонкая градиентная полоса перед ником. Ник остаётся спокойным." },
  { id: "ink", title: "6 · Чернила", note: "Самый тихий: ник чуть жирнее и в индиго. Без эффектов." },
];

export function PremiumNamePreviewPage() {
  const { defs } = useCatalog();
  const badgeKey = String(defs.find((d) => d.kind === "badge")?.id ?? "") || null;
  return (
    <main className="mx-auto max-w-6xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр ника Premium</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. Premium-игрока видно по самому нику. Рядом с ником один значок: выбранный игроком; если не выбран и есть Premium, стоит «G».
          Шесть современных вариантов (без жёлтого), каждый на тёмной и светлой теме: подиум и список. Четыре примера игроков:
          Premium со значком, Premium без значка, без Premium со значком, без всего.
        </p>
      </header>
      <div className="grid gap-4 lg:grid-cols-2">
        {VARIANTS.map((v) => (
          <section key={v.id} className="card space-y-2 p-4">
            <h2 className="text-lg font-semibold">{v.title}</h2>
            <p className="text-xs text-slate-500">{v.note}</p>
            <div className="grid gap-2 sm:grid-cols-2">
              <Panel dark style={v.id} badgeKey={badgeKey} />
              <Panel dark={false} style={v.id} badgeKey={badgeKey} />
            </div>
          </section>
        ))}
      </div>
    </main>
  );
}

import { BadgeMark, useCatalog } from "../components/rewardVisuals";

// A preview only: how a Premium player's name stands out. One icon next to a name at most:
// the badge the person chose; a Premium person who chose none gets the Premium «G».

const BASE = `${import.meta.env.BASE_URL}`;
const css = `
@keyframes pn-shine { 0%,70% { background-position: 200% 0; } 100% { background-position: -100% 0; } }
`;

type Style = "A" | "B" | "C" | "D";
const GOLD_DARK = "linear-gradient(90deg,#b8860b,#f5d76e 45%,#b8860b)";
const GOLD_LIGHT = "linear-gradient(90deg,#7a5200,#c8961c 45%,#7a5200)";

function PremiumName({ text, style, dark }: { text: string; style: Style; dark: boolean }) {
  const gold = dark ? GOLD_DARK : GOLD_LIGHT;
  const common = { fontWeight: 800 } as const;
  if (style === "A") return <span style={{ ...common, background: gold, WebkitBackgroundClip: "text", color: "transparent" }}>{text}</span>;
  if (style === "B") return <span style={{ ...common, backgroundImage: `linear-gradient(110deg,transparent 40%,rgba(255,255,255,0.95) 50%,transparent 60%),${gold}`, backgroundSize: "250% 100%,100% 100%", WebkitBackgroundClip: "text", color: "transparent", animation: "pn-shine 3.5s ease-in-out infinite" }}>{text}</span>;
  if (style === "C") return <span style={{ ...common, background: dark ? "linear-gradient(90deg,#8b93ff,#f5d76e)" : "linear-gradient(90deg,#3f4fd8,#b8860b)", WebkitBackgroundClip: "text", color: "transparent" }}>{text}</span>;
  return <span style={{ ...common, color: dark ? "#fff" : "#1b1247", borderBottom: `2px solid ${dark ? "#f5d76e" : "#b8860b"}`, paddingBottom: 1 }}>{text}</span>;
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
    <div className="space-y-2 rounded-2xl p-3" style={{ background: dark ? "#0d0f1c" : "#ffffff", boxShadow: dark ? undefined : "inset 0 0 0 1px #e5e7eb" }}>
      <div className="flex items-end justify-around rounded-xl p-2" style={{ background: bg }}>
        {PEOPLE.slice(0, 3).map((p, i) => (
          <div key={p.name} className="flex flex-col items-center gap-1">
            <span className="flex items-center justify-center rounded-full text-sm font-black text-white" style={{ width: i === 0 ? 52 : 40, height: i === 0 ? 52 : 40, background: "linear-gradient(135deg,#8b93ff,#5862dd)" }}>{p.name[0].toUpperCase()}</span>
            <NameLine p={p} style={style} dark={dark} size={i === 0 ? 14 : 12} badgeKey={badgeKey} />
          </div>
        ))}
      </div>
      {PEOPLE.map((p, i) => (
        <div key={p.name} className="flex items-center gap-2 rounded-xl px-3 py-2" style={{ background: bg }}>
          <span className="w-4 text-xs opacity-50" style={{ color: dark ? "#fff" : "#1b1247" }}>{i + 4}</span>
          <span className="flex h-8 w-8 items-center justify-center rounded-full text-xs font-black text-white" style={{ background: "linear-gradient(135deg,#f472b6,#be185d)" }}>{p.name[0].toUpperCase()}</span>
          <NameLine p={p} style={style} dark={dark} badgeKey={badgeKey} />
        </div>
      ))}
    </div>
  );
}

const VARIANTS: { id: Style; title: string; note: string }[] = [
  { id: "A", title: "A · Золотой градиент", note: "Ник плавно переходит от тёмного золота к светлому. Спокойно и дорого." },
  { id: "B", title: "B · Золото с бликом", note: "То же, но раз в несколько секунд по нику проходит мягкий блик." },
  { id: "C", title: "C · Индиго → золото", note: "Градиент в цвета значка «G»." },
  { id: "D", title: "D · Линия под ником", note: "Ник обычного цвета, под ним тонкая золотая линия." },
];

export function PremiumNamePreviewPage() {
  const { defs } = useCatalog();
  const badgeKey = String(defs.find((d) => d.kind === "badge")?.id ?? "") || null;
  return (
    <main className="mx-auto max-w-5xl space-y-5">
      <style>{css}</style>
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр ника Premium</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. Premium-игрока видно по самому нику, значка «G» рядом нет. Значок у имени один: тот, который игрок выбрал в «Моих наградах»;
          если не выбрал и у него Premium, стоит «G»; если не выбрал и Premium нет, ничего. Подиум и список, на тёмной и светлой теме.
          Четыре примера игроков: Premium с выбранным значком, Premium без значка, без Premium со значком, без всего.
        </p>
      </header>
      <div className="grid gap-4 md:grid-cols-2">
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

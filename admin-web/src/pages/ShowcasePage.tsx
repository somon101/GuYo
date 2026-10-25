import { useState } from "react";
import { api } from "../api/client";
import { BadgeMark, FrameAvatar, ProfileMock, Tile, TitleRibbon, useCatalog } from "../components/rewardVisuals";

// Read-only showcase: every frame and badge, and what one chosen player wears and owns.
// Nothing is changed and the player is not told.

type Item = { id: number; kind: string; key: string; label: string; season_name: string | null };
type Showcase = {
  login: string; public_id: number; avatar_url: string | null;
  worn: { frame: string | null; badge: string | null; title: string | null; title_key: string | null };
  collection: { badges: Item[]; titles: Item[]; frames: Item[] };
  achievements: { id: number; title: string; description: string; color: string; icon_url: string | null; earned_at: string | null }[];
};

export function ShowcasePage() {
  const [query, setQuery] = useState("");
  const [data, setData] = useState<Showcase | null>(null);
  const [error, setError] = useState("");
  const [frame, setFrame] = useState<string | null>(null);
  const [badge, setBadge] = useState<string | null>(null);
  const [title, setTitle] = useState<string | null>(null);
  const [titleKey, setTitleKey] = useState<string | null>(null);
  const { defs } = useCatalog();

  const find = async () => {
    setError("");
    try {
      const { data: d } = await api.get<Showcase>("/admin/season-pass/showcase", { params: { user: query.trim() } });
      setData(d); setFrame(d.worn.frame); setBadge(d.worn.badge); setTitle(d.worn.title); setTitleKey(d.worn.title_key);
    } catch { setData(null); setError("Игрок не найден"); }
  };
  const h = (t: string) => <h2 className="mb-2 text-lg font-semibold">{t}</h2>;

  return (
    <main className="mx-auto max-w-4xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Витрина наград</h1>
        <p className="mt-1 text-sm text-slate-500">Только просмотр: ничего не меняется, игрок ничего не узнает.</p>
      </header>

      <section className="card space-y-3 p-4">
        {h("Игрок")}
        <div className="flex flex-wrap gap-2">
          <input className="field w-56 px-2 py-1.5 text-sm" placeholder="Логин или ID" value={query} onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => e.key === "Enter" && void find()} />
          <button className="rounded-lg bg-indigo-600 px-3 py-2 text-sm text-white hover:bg-indigo-700" onClick={() => void find()}>Показать</button>
          {error && <span className="self-center text-sm text-red-700">{error}</span>}
        </div>
        {data && (
          <div className="space-y-4">
            <div className="rounded-2xl p-4" style={{ background: "#0d0f1c" }}>
              <div className="mb-2 text-xs font-bold uppercase tracking-wide text-white/50">Профиль так, как его видят в приложении</div>
              <ProfileMock frame={frame} badge={badge} title={title} titleKey={titleKey} src={data.avatar_url} login={data.login} />
              <div className="mt-2 text-xs text-white/50">Нажмите на любую награду ниже, чтобы примерить её на этот профиль (это только показ).</div>
            </div>
            <div>
              <div className="mb-1 text-xs font-bold uppercase text-slate-500">Рамки игрока</div>
              <div className="flex flex-wrap gap-2 rounded-2xl p-2" style={{ background: "#0d0f1c" }}>
                {data.collection.frames.length === 0 && <span className="p-2 text-sm text-white/50">Нет рамок</span>}
                {data.collection.frames.map((f) => <Tile key={f.id} selected={frame === f.key} onClick={() => setFrame(frame === f.key ? null : f.key)} label={f.label || f.key}><FrameAvatar frameKey={f.key} size={60} src={data.avatar_url} /></Tile>)}
              </div>
            </div>
            <div>
              <div className="mb-1 text-xs font-bold uppercase text-slate-500">Значки игрока</div>
              <div className="flex flex-wrap gap-2 rounded-2xl p-2" style={{ background: "#0d0f1c" }}>
                {data.collection.badges.length === 0 && <span className="p-2 text-sm text-white/50">Нет значков</span>}
                {data.collection.badges.map((b) => <Tile key={b.id} selected={badge === b.key} onClick={() => setBadge(badge === b.key ? null : b.key)} label={b.label || b.key}><BadgeMark badgeKey={b.key} size={48} /></Tile>)}
              </div>
            </div>
            <div>
              <div className="mb-1 text-xs font-bold uppercase text-slate-500">Звания игрока</div>
              <div className="flex flex-wrap gap-2 rounded-2xl p-2" style={{ background: "#0d0f1c" }}>
                {data.collection.titles.length === 0 && <span className="p-2 text-sm text-white/50">Нет званий</span>}
                {data.collection.titles.map((t) => <Tile key={t.id} selected={title === t.label} onClick={() => { const on = title === t.label; setTitle(on ? null : t.label); setTitleKey(on ? null : t.key || null); }} label={t.season_name ?? ""}><TitleRibbon titleKey={t.key || null} text={t.label} width={150} /></Tile>)}
              </div>
            </div>
            <div>
              <div className="mb-1 text-xs font-bold uppercase text-slate-500">Достижения ({data.achievements.filter((a) => a.earned_at).length} из {data.achievements.length})</div>
              <div className="grid grid-cols-2 gap-2 rounded-2xl p-2 sm:grid-cols-3" style={{ background: "#0d0f1c" }}>
                {data.achievements.map((a) => (
                  <div key={a.id} className="flex items-center gap-2 rounded-xl p-2" style={{ background: "#12151f", opacity: a.earned_at ? 1 : 0.4, filter: a.earned_at ? undefined : "grayscale(1)" }} title={a.description}>
                    <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full" style={{ background: a.color }}>{a.icon_url ? <img src={a.icon_url} alt="" style={{ width: 28, height: 28, objectFit: "contain" }} /> : "🏅"}</span>
                    <div className="min-w-0"><div className="truncate text-xs font-bold text-white">{a.title}</div><div className="text-[10px] text-white/50">{a.earned_at ? new Date(a.earned_at).toLocaleDateString("ru-RU") : "не получено"}</div></div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </section>

      <section className="card space-y-3 p-4">
        {h("Все рамки аватара (каталог)")}
        <div className="flex flex-wrap gap-2 rounded-2xl p-2" style={{ background: "#0d0f1c" }}>
          {defs.filter((d) => d.kind === "frame").map((d) => <Tile key={d.id} selected={false} onClick={() => undefined} label={d.name}><FrameAvatar frameKey={String(d.id)} size={96} /></Tile>)}
        </div>
        {h("Все значки (каталог)")}
        <div className="flex flex-wrap gap-2 rounded-2xl p-2" style={{ background: "#0d0f1c" }}>
          {defs.filter((d) => d.kind === "badge").map((d) => <Tile key={d.id} selected={false} onClick={() => undefined} label={d.name}><BadgeMark badgeKey={String(d.id)} size={72} /></Tile>)}
        </div>
        {h("Все титулы (каталог)")}
        <div className="flex flex-wrap gap-2 rounded-2xl p-2" style={{ background: "#0d0f1c" }}>
          {defs.filter((d) => d.kind === "title").map((d) => <Tile key={d.id} selected={false} onClick={() => undefined} label={d.name}><TitleRibbon titleKey={String(d.id)} text={d.name} width={200} /></Tile>)}
        </div>
      </section>
    </main>
  );
}

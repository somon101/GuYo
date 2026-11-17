import { useCallback, useEffect, useMemo, useState } from "react";
import { API_URL, api } from "../api/client";

// Аватар игрока собирается из деталей, которые приходят из Студии аватаров. Здесь только загрузка и порядок:
// загрузить файл «Выгрузить для GuYo», увидеть наборы и детали с ID и версиями, включить или выключить деталь.
// Ничего не собирается и не расставляется: положение каждой детали задано в Студии.

type Place = { x: number; y: number; w: number; r: number; pivot: string };
type Item = { id: string; slot: string; gender: "male" | "female" | "both"; name: string; set_id: string; set_name: string; url: string | null; place: Partial<Record<"male" | "female", Place>>; own_place: boolean; active: boolean; version: number };
type Bg = { id: string; name: string; kind: string; c1: string | null; c2: string | null; url: string | null; active: boolean; version: number };
type Catalog = { version: number; slots: { id: string; name: string }[]; items: Item[]; backgrounds: Bg[] };
type Report = { version: number; added: number; updated: number; unchanged: number; backgrounds_added: number; backgrounds_updated: number; missing_in_file: number };

const GENDER: Record<Item["gender"], string> = { male: "мужская", female: "женская", both: "обе" };
const src = (u: string | null) => (u ? (u.startsWith("http") ? u : `${API_URL}${u}`) : "");

function errText(e: unknown): string {
  const d = (e as { response?: { data?: { detail?: unknown } } })?.response?.data?.detail;
  return typeof d === "string" ? d : "Не получилось";
}

export function AvatarSetsPage() {
  const [cat, setCat] = useState<Catalog | null>(null);
  const [report, setReport] = useState<Report | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setCat((await api.get<Catalog>("/admin/avatar/catalog")).data);
    } catch (e) {
      setMessage(errText(e));
    }
  }, []);
  useEffect(() => {
    let alive = true;
    api.get<Catalog>("/admin/avatar/catalog").then((r) => { if (alive) setCat(r.data); }).catch((e) => { if (alive) setMessage(errText(e)); });
    return () => { alive = false; };
  }, []);

  const upload = async (file: File | undefined) => {
    if (!file) return;
    setBusy(true);
    setMessage("");
    try {
      const form = new FormData();
      form.append("file", file);
      setReport((await api.post<Report>("/admin/avatar/import", form)).data);
      await load();
    } catch (e) {
      setMessage(errText(e));
    }
    setBusy(false);
  };
  const toggle = async (it: Item) => {
    try { await api.patch(`/admin/avatar/items/${it.id}`, { active: !it.active }); await load(); } catch (e) { setMessage(errText(e)); }
  };
  const toggleBg = async (b: Bg) => {
    try { await api.patch(`/admin/avatar/backgrounds/${b.id}`, { active: !b.active }); await load(); } catch (e) { setMessage(errText(e)); }
  };
  const remove = async (it: Item) => {
    if (!window.confirm(`Удалить деталь «${it.name}» насовсем? Вернуть её можно только новой загрузкой из Студии.`)) return;
    try { await api.delete(`/admin/avatar/items/${it.id}`); await load(); } catch (e) { setMessage(errText(e)); }
  };

  // наборы -> слоты -> детали
  const sets = useMemo(() => {
    const map = new Map<string, { name: string; items: Item[] }>();
    for (const it of cat?.items ?? []) {
      const k = it.set_id || "—";
      if (!map.has(k)) map.set(k, { name: it.set_name || "Без набора", items: [] });
      map.get(k)!.items.push(it);
    }
    return [...map.entries()];
  }, [cat]);
  const slotName = (id: string) => cat?.slots.find((s) => s.id === id)?.name ?? id;

  return (
    <main className="mx-auto max-w-5xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Аватар: наборы деталей из Студии</h1>
        <p className="mt-1 text-sm text-slate-500">
          Игроки создают аватар в приложении из этих деталей (пол, причёска, лицо, одежда, фон), своё фото загрузить нельзя. Здесь только загрузка и порядок: положение каждой детали настраивается в Студии аватаров и приходит вместе с файлом.
          Повторная загрузка обновляет детали по ID, дублей не будет. Детали, которых нет в новом файле, остаются.
        </p>
      </header>

      <section className="card space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-3">
          <label className={`cursor-pointer rounded-lg px-4 py-2 text-sm font-semibold text-white ${busy ? "bg-slate-400" : "bg-indigo-600"}`}>
            {busy ? "Загружаем…" : "Загрузить файл из Студии"}
            <input type="file" accept="application/json,.json" className="hidden" disabled={busy} onChange={(e) => { void upload(e.target.files?.[0]); e.target.value = ""; }} />
          </label>
          {cat && <span className="text-sm text-slate-500">Версия каталога: {cat.version} · деталей: {cat.items.length} · фонов: {cat.backgrounds.length}</span>}
        </div>
        {report && (
          <p className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">
            Загружено. Добавлено деталей: {report.added}, обновлено: {report.updated}, без изменений: {report.unchanged}. Фонов добавлено: {report.backgrounds_added}, обновлено: {report.backgrounds_updated}.
            {report.missing_in_file > 0 && ` Деталей на сервере, которых нет в этом файле: ${report.missing_in_file} (остались как были).`}
          </p>
        )}
        {message && <p className="text-sm text-red-600">{message}</p>}
      </section>

      {cat && cat.items.length === 0 && <p className="text-sm text-slate-500">Деталей пока нет. Загрузите файл из Студии.</p>}

      {sets.map(([id, set]) => (
        <section key={id} className="card space-y-3 p-4">
          <h2 className="text-lg font-semibold">{set.name} <span className="text-xs font-normal text-slate-400">набор {id} · деталей {set.items.length}</span></h2>
          {(cat?.slots ?? []).filter((s) => set.items.some((i) => i.slot === s.id)).map((s) => (
            <div key={s.id} className="space-y-1">
              <h3 className="text-sm font-semibold text-slate-600">{slotName(s.id)}</h3>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
                {set.items.filter((i) => i.slot === s.id).map((it) => {
                  const p = it.place.female ?? it.place.male;
                  return (
                    <div key={it.id} className="rounded-2xl p-2" style={{ background: "#12151f", opacity: it.active ? 1 : 0.45 }}>
                      <div className="flex h-24 items-center justify-center"><img alt="" src={src(it.url)} loading="lazy" style={{ maxWidth: "100%", maxHeight: 92, objectFit: "contain" }} /></div>
                      <div className="truncate text-xs font-bold text-white">{it.name}</div>
                      <div className="text-[10px] text-white/50">для: {GENDER[it.gender]} · {it.own_place ? "своё положение" : "стандарт слота"} · v{it.version}</div>
                      <div className="truncate text-[10px] text-white/40" title={it.id}>ID {it.id}</div>
                      {p && <div className="text-[10px] text-white/60">x {Math.round(p.x)} · y {Math.round(p.y)} · ширина {Math.round(p.w)}{p.r ? ` · поворот ${p.r}°` : ""}</div>}
                      <div className="mt-1.5 flex gap-1.5">
                        <button type="button" onClick={() => void toggle(it)} className={`rounded-md px-2 py-0.5 text-[11px] font-semibold ${it.active ? "bg-emerald-600 text-white" : "bg-slate-600 text-white"}`}>{it.active ? "Включена" : "Выключена"}</button>
                        <button type="button" onClick={() => void remove(it)} className="rounded-md bg-red-600/80 px-2 py-0.5 text-[11px] font-semibold text-white">Удалить</button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </section>
      ))}

      {cat && cat.backgrounds.length > 0 && (
        <section className="card space-y-2 p-4">
          <h2 className="text-lg font-semibold">Фоны</h2>
          <div className="grid grid-cols-3 gap-3 sm:grid-cols-5 md:grid-cols-6">
            {cat.backgrounds.map((b) => (
              <button key={b.id} type="button" onClick={() => void toggleBg(b)} className="text-left" title={`${b.name} · ID ${b.id} · v${b.version}`} style={{ opacity: b.active ? 1 : 0.4 }}>
                <div style={{ width: "100%", aspectRatio: "1", borderRadius: 14, overflow: "hidden", background: b.kind === "solid" ? (b.c1 ?? "#ccc") : b.kind === "grad" ? `linear-gradient(135deg, ${b.c1}, ${b.c2})` : "#e6e8f2" }}>
                  {b.kind === "img" && b.url && <img alt="" src={src(b.url)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />}
                </div>
                <div className="truncate text-[11px] text-slate-500">{b.name} · {b.active ? "включён" : "выключен"}</div>
              </button>
            ))}
          </div>
          <p className="text-xs text-slate-400">Нажатие включает или выключает фон.</p>
        </section>
      )}
    </main>
  );
}

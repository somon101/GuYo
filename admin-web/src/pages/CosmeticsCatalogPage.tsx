import { useState } from "react";
import { api } from "../api/client";
import { artUrl, useCatalog, type CosmeticDef } from "../components/rewardVisuals";

// The catalog: every season makes its own frame, badge and title here (a PNG with a
// transparent background and a name). The season pass and the showcase use these.

const KINDS: Record<CosmeticDef["kind"], { label: string; hint: string }> = {
  frame: { label: "Рамка аватара", hint: "Квадратный PNG, кольцо с пустым центром (центр прозрачный)." },
  badge: { label: "Значок", hint: "Квадратный PNG с прозрачным фоном." },
  title: { label: "Титул", hint: "Широкий PNG-лента (около 3:1) без надписи: название приложение напишет само, на языке игрока." },
};

export function CosmeticsCatalogPage() {
  const { defs, reload } = useCatalog();
  const [kind, setKind] = useState<CosmeticDef["kind"]>("frame");
  const [name, setName] = useState("");
  const [nameTg, setNameTg] = useState("");
  const [nameUz, setNameUz] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [message, setMessage] = useState("");

  const add = async () => {
    if (!file || !name.trim()) { setMessage("Нужны название и картинка PNG"); return; }
    const form = new FormData();
    form.append("kind", kind); form.append("name", name); form.append("name_tg", nameTg); form.append("name_uz", nameUz); form.append("image", file);
    try {
      await api.post("/admin/cosmetics", form);
      setName(""); setNameTg(""); setNameUz(""); setFile(null); setMessage("Добавлено");
      await reload();
    } catch (e) { setMessage(errorText(e)); }
  };
  const remove = async (d: CosmeticDef) => {
    if (!window.confirm(`Удалить «${d.name}»?`)) return;
    try { await api.delete(`/admin/cosmetics/${d.id}`); await reload(); setMessage("Удалено"); } catch (e) { setMessage(errorText(e)); }
  };
  const rename = async (d: CosmeticDef, patch: Partial<CosmeticDef>) => {
    const next = { ...d, ...patch };
    const form = new FormData();
    form.append("name", next.name); form.append("name_tg", next.name_tg ?? ""); form.append("name_uz", next.name_uz ?? "");
    try { await api.put(`/admin/cosmetics/${d.id}`, form); await reload(); setMessage("Сохранено"); } catch (e) { setMessage(errorText(e)); }
  };
  const field = "field px-2 py-1.5 text-sm";

  return (
    <main className="mx-auto max-w-4xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Каталог наград</h1>
        <p className="mt-1 text-sm text-slate-500">Рамки, значки и титулы текущего и будущих сезонов. Загрузили картинку, назвали, потом выбрали в награде пропуска.</p>
      </header>
      <section className="card space-y-3 p-4">
        <h2 className="text-lg font-semibold">Добавить</h2>
        <div className="flex flex-wrap gap-2">
          {(Object.keys(KINDS) as CosmeticDef["kind"][]).map((k) => (
            <button key={k} type="button" onClick={() => setKind(k)} className={`rounded-lg px-3 py-1.5 text-sm ${kind === k ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>{KINDS[k].label}</button>
          ))}
        </div>
        <p className="text-xs text-slate-500">{KINDS[kind].hint}</p>
        <div className="flex flex-wrap gap-2">
          <input className={`${field} w-56`} placeholder="Название (по-русски)" value={name} onChange={(e) => setName(e.target.value)} />
          <input className={`${field} w-40`} placeholder="Тоҷикӣ" value={nameTg} onChange={(e) => setNameTg(e.target.value)} />
          <input className={`${field} w-40`} placeholder="Oʻzbekcha" value={nameUz} onChange={(e) => setNameUz(e.target.value)} />
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <input type="file" accept="image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          <button className="rounded-lg bg-indigo-600 px-3 py-2 text-sm text-white hover:bg-indigo-700" onClick={() => void add()}>Добавить</button>
          {message && <span className="text-sm text-slate-500">{message}</span>}
        </div>
      </section>
      {(Object.keys(KINDS) as CosmeticDef["kind"][]).map((k) => (
        <section key={k} className="card space-y-2 p-4">
          <h2 className="text-lg font-semibold">{KINDS[k].label}</h2>
          <div className="grid gap-3 sm:grid-cols-2">
            {defs.filter((d) => d.kind === k).map((d) => (
              <div key={d.id} className="flex items-center gap-3 rounded-2xl p-3" style={{ background: "#12151f" }}>
                <img src={artUrl(d.id)} alt="" style={{ width: k === "title" ? 120 : 72, height: 72, objectFit: "contain" }} />
                <div className="min-w-0 flex-1 space-y-1">
                  <input className={`${field} w-full`} defaultValue={d.name} onBlur={(e) => e.target.value !== d.name && void rename(d, { name: e.target.value })} />
                  <input className={`${field} w-full`} placeholder="Тоҷикӣ" defaultValue={d.name_tg ?? ""} onBlur={(e) => e.target.value !== (d.name_tg ?? "") && void rename(d, { name_tg: e.target.value })} />
                  <input className={`${field} w-full`} placeholder="Oʻzbekcha" defaultValue={d.name_uz ?? ""} onBlur={(e) => e.target.value !== (d.name_uz ?? "") && void rename(d, { name_uz: e.target.value })} />
                </div>
                <button className="text-xs text-red-400 hover:underline" onClick={() => void remove(d)}>удалить</button>
              </div>
            ))}
            {defs.every((d) => d.kind !== k) && <p className="text-sm text-slate-500">Пока пусто.</p>}
          </div>
        </section>
      ))}
    </main>
  );
}

function errorText(e: unknown): string {
  const detail = (e as { response?: { data?: { detail?: unknown } } })?.response?.data?.detail;
  return typeof detail === "string" ? detail : "Не удалось";
}

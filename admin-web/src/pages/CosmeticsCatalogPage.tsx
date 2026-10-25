import { useState } from "react";
import { api } from "../api/client";
import { CosmeticCreateForm } from "../components/CosmeticCreateForm";
import { artUrl, useCatalog, type CosmeticDef } from "../components/rewardVisuals";

// The catalog: every season makes its own frame, badge and title here (a PNG with a
// transparent background and a name in each open language). The season pass and the showcase use these.

const KINDS: Record<CosmeticDef["kind"], string> = { frame: "Рамка аватара", badge: "Значок", title: "Титул" };

export function CosmeticsCatalogPage() {
  const { defs, reload } = useCatalog();
  const [kind, setKind] = useState<CosmeticDef["kind"]>("frame");
  const [message, setMessage] = useState("");

  const remove = async (d: CosmeticDef) => {
    if (!window.confirm(`Удалить «${d.name}»?`)) return;
    try { await api.delete(`/admin/cosmetics/${d.id}`); await reload(); setMessage("Удалено"); } catch (e) {
      const detail = (e as { response?: { data?: { detail?: unknown } } })?.response?.data?.detail;
      setMessage(typeof detail === "string" ? detail : "Не удалось");
    }
  };
  const rename = async (d: CosmeticDef, name: string, names: Record<string, string>) => {
    const form = new FormData();
    form.append("name", name); form.append("names", JSON.stringify(names));
    try { await api.put(`/admin/cosmetics/${d.id}`, form); await reload(); setMessage("Сохранено"); } catch { setMessage("Не удалось сохранить"); }
  };
  const field = "field px-2 py-1.5 text-sm";

  return (
    <main className="mx-auto max-w-4xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Каталог наград</h1>
        <p className="mt-1 text-sm text-slate-500">Рамки, значки и титулы сезонов. Создать новую можно и прямо в выборе награды пропуска (кнопка «Создать новую»).</p>
      </header>
      <section className="card space-y-3 p-4">
        <h2 className="text-lg font-semibold">Создать</h2>
        <div className="flex flex-wrap gap-2">
          {(Object.keys(KINDS) as CosmeticDef["kind"][]).map((k) => (
            <button key={k} type="button" onClick={() => setKind(k)} className={`rounded-lg px-3 py-1.5 text-sm ${kind === k ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}>{KINDS[k]}</button>
          ))}
        </div>
        <CosmeticCreateForm kind={kind} onCreated={() => void reload()} />
      </section>
      {message && <p className="text-sm text-slate-500">{message}</p>}
      {(Object.keys(KINDS) as CosmeticDef["kind"][]).map((k) => (
        <section key={k} className="card space-y-2 p-4">
          <h2 className="text-lg font-semibold">{KINDS[k]}</h2>
          <div className="grid gap-3 sm:grid-cols-2">
            {defs.filter((d) => d.kind === k).map((d) => (
              <div key={d.id} className="flex items-center gap-3 rounded-2xl p-3" style={{ background: "#12151f" }}>
                <img src={artUrl(d.id)} alt="" style={{ width: k === "title" ? 120 : 72, height: 72, objectFit: "contain" }} />
                <div className="min-w-0 flex-1 space-y-1">
                  <input className={`${field} w-full`} defaultValue={d.name} onBlur={(e) => e.target.value !== d.name && void rename(d, e.target.value, d.names)} />
                  {Object.entries(d.names).map(([code, text]) => (
                    <input key={code} className={`${field} w-full`} placeholder={code} defaultValue={text} onBlur={(e) => e.target.value !== text && void rename(d, d.name, { ...d.names, [code]: e.target.value })} />
                  ))}
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

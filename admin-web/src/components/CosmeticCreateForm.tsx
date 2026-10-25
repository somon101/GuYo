import { useEffect, useState } from "react";
import { api } from "../api/client";
import { listLanguages, type LanguageDetail } from "../api/endpoints";
import type { CosmeticDef } from "./rewardVisuals";

const field = "field px-2 py-1.5 text-sm";

export const KIND_HINT: Record<CosmeticDef["kind"], string> = {
  frame: "Квадратный PNG: кольцо с пустым прозрачным центром.",
  badge: "Квадратный PNG с прозрачным фоном.",
  title: "Широкий PNG-лента (около 3:1) без надписи: название приложение напишет само, на языке игрока.",
};

/** Make one new frame / badge / title: the picture, the Russian name and a name for every
 *  interface language that is open. Saved at once; `onCreated` gets the new catalog item. */
export function CosmeticCreateForm({ kind, onCreated }: { kind: CosmeticDef["kind"]; onCreated: (d: CosmeticDef) => void }) {
  const [langs, setLangs] = useState<LanguageDetail[]>([]);
  const [name, setName] = useState("");
  const [names, setNames] = useState<Record<string, string>>({});
  const [file, setFile] = useState<File | null>(null);
  const [message, setMessage] = useState("");
  useEffect(() => {
    listLanguages().then((all) => setLangs(all.filter((l) => l.is_enabled && l.ui_ready && l.code !== "ru"))).catch(() => undefined);
  }, []);

  const save = async () => {
    if (!file || !name.trim()) { setMessage("Нужны название и картинка PNG"); return; }
    const form = new FormData();
    form.append("kind", kind); form.append("name", name); form.append("names", JSON.stringify(names)); form.append("image", file);
    try {
      const { data } = await api.post<CosmeticDef>("/admin/cosmetics", form);
      setName(""); setNames({}); setFile(null); setMessage("Сохранено");
      onCreated(data);
    } catch (e) {
      const detail = (e as { response?: { data?: { detail?: unknown } } })?.response?.data?.detail;
      setMessage(typeof detail === "string" ? detail : "Не удалось сохранить");
    }
  };

  return (
    <div className="space-y-2">
      <p className="text-xs text-slate-500">{KIND_HINT[kind]}</p>
      <div className="flex flex-wrap gap-2">
        <input className={`${field} w-56`} placeholder="Название (по-русски)" value={name} onChange={(e) => setName(e.target.value)} />
        {langs.map((l) => (
          <input key={l.code} className={`${field} w-44`} placeholder={`${l.native_name || l.name} (${l.code})`} value={names[l.code] ?? ""} onChange={(e) => setNames({ ...names, [l.code]: e.target.value })} />
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <input type="file" accept="image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        <button type="button" className="rounded-lg bg-indigo-600 px-3 py-2 text-sm text-white hover:bg-indigo-700" onClick={() => void save()}>Сохранить</button>
        {message && <span className="text-sm text-slate-500">{message}</span>}
      </div>
    </div>
  );
}

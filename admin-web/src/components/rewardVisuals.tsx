import { createContext, useEffect, useState, type ReactNode } from "react";
import { API_URL, api } from "../api/client";

// How season-pass cosmetics look. Frames, badges and titles are pictures the admin
// uploaded (the catalog); the title picture is an empty ribbon, its name is written on it.

export type CosmeticDef = { id: number; kind: "frame" | "badge" | "title"; name: string; names: Record<string, string>; used_in?: string[] };

export const BOOSTER_KINDS = {
  chest: { label: "Удвоитель сундуков", does: "призы из сундуков ×2", icon: "preview/booster.png" },
  rating: { label: "Удвоитель рейтинга", does: "очки рейтинга ×2, откуда бы ни пришли", icon: "preview/booster_rating.png" },
  xp: { label: "Удвоитель пропуска", does: "энергия пропуска ×2, откуда бы ни пришла", icon: "preview/booster_xp.png" },
} as const;
export type BoosterKind = keyof typeof BOOSTER_KINDS;

/** Catalog ids the pass being edited already hands out: the picker does not offer them again. */
export const UsedCosmetics = createContext<{ keys: Set<string>; season: string | null }>({ keys: new Set(), season: null });

/** Hidden from the picker: handed out in this pass already, or by the pass of another season. */
export function isTaken(d: CosmeticDef, used: { keys: Set<string>; season: string | null }): boolean {
  return used.keys.has(String(d.id)) || (d.used_in ?? []).some((n) => n !== used.season);
}

export function usedCosmetics(def: { levels: { free?: { key?: string | null; type?: string } | null; premium?: { key?: string | null; type?: string } | null }[] } | null | undefined): Set<string> {
  const out = new Set<string>();
  for (const l of def?.levels ?? []) for (const r of [l.free, l.premium]) if (r && (r.type === "frame" || r.type === "badge" || r.type === "title") && r.key) out.add(String(r.key));
  return out;
}

export const artUrl = (id: string | number) => `${API_URL}/cosmetics/art/${id}`;

let cache: CosmeticDef[] | null = null;
/** The catalog (loaded once; `reload` after a change). */
export function useCatalog(): { defs: CosmeticDef[]; reload: () => Promise<void> } {
  const [defs, setDefs] = useState<CosmeticDef[]>(cache ?? []);
  const reload = async () => {
    const { data } = await api.get<CosmeticDef[]>("/admin/cosmetics");
    cache = data;
    setDefs(data);
  };
  useEffect(() => { void reload().catch(() => undefined); }, []);
  return { defs, reload };
}

export const catalogName = (key?: string | null): string => cache?.find((d) => String(d.id) === String(key))?.name ?? "";

export function nameOf(defs: CosmeticDef[], key?: string | null): string {
  return defs.find((d) => String(d.id) === String(key))?.name ?? "";
}

/** A stand-in avatar: a round face on a soft background (or the person's photo). */
function Face({ size, src }: { size: number; src?: string | null }) {
  if (src) return <img src={src} alt="" style={{ width: size, height: size, borderRadius: "50%", objectFit: "cover" }} />;
  return (
    <span style={{ width: size, height: size, borderRadius: "50%", display: "inline-flex", alignItems: "center", justifyContent: "center", background: "linear-gradient(135deg,#8b93ff,#5862dd)", color: "#fff", fontWeight: 900, fontSize: size * 0.42 }}>S</span>
  );
}

/** The avatar inside a frame picture, as the app draws it (the photo under the ring). */
export function FrameAvatar({ frameKey, size = 64, src }: { frameKey?: string | null; size?: number; src?: string | null }) {
  if (!frameKey) return <Face size={size} src={src} />;
  return (
    <span style={{ position: "relative", width: size, height: size, display: "inline-flex", alignItems: "center", justifyContent: "center" }}>
      <Face size={size * 0.74} src={src} />
      <img src={artUrl(frameKey)} alt="" style={{ position: "absolute", inset: 0, width: size, height: size, objectFit: "contain", maxWidth: "none" }} />
    </span>
  );
}

/** A badge picture. */
export function BadgeMark({ badgeKey, size = 48 }: { badgeKey?: string | null; size?: number }) {
  if (!badgeKey) return null;
  return <img src={artUrl(badgeKey)} alt="" style={{ width: size, height: size, objectFit: "contain", maxWidth: "none" }} />;
}

/** A title: the empty ribbon picture with the name written on it. */
export function TitleRibbon({ titleKey, text, width = 200 }: { titleKey?: string | null; text?: string; width?: number }) {
  const label = text?.trim() || "Название титула";
  return (
    <span style={{ position: "relative", display: "inline-block", width, aspectRatio: "1000 / 336" }}>
      {titleKey && <img src={artUrl(titleKey)} alt="" style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "contain" }} />}
      <span style={{ position: "absolute", left: "27%", right: "27%", top: "34%", bottom: "34%", display: "flex", alignItems: "center", justifyContent: "center", color: "#fff", fontWeight: 900, fontSize: width * 0.07 * Math.min(1, 11 / Math.max(label.length, 1)), textShadow: "0 1px 3px rgba(0,0,0,0.8)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{label}</span>
    </span>
  );
}

/** A mini profile: how the person looks with the chosen frame, badge and title. */
export function ProfileMock({ frame, badge, title, titleKey, src, login = "somon" }: { frame?: string | null; badge?: string | null; title?: string | null; titleKey?: string | null; src?: string | null; login?: string }) {
  return (
    <div className="flex items-center gap-3 rounded-2xl p-3" style={{ background: "#12151f", width: 320 }}>
      <FrameAvatar frameKey={frame} size={84} src={src} />
      <div className="min-w-0">
        <div className="flex items-center gap-2 font-black text-white">{login} {badge && <BadgeMark badgeKey={badge} size={26} />}</div>
        <div className="mt-1">{titleKey || title ? <TitleRibbon titleKey={titleKey} text={title ?? ""} width={190} /> : <span className="text-xs text-white/40">без звания</span>}</div>
      </div>
    </div>
  );
}

/** A selectable tile in a picker. */
export function Tile({ selected, onClick, children, label }: { selected: boolean; onClick: () => void; children: ReactNode; label: string }) {
  return (
    <button type="button" onClick={onClick} className="flex flex-col items-center gap-1 rounded-xl p-2 text-xs" style={{ background: "#12151f", color: "#fff", minWidth: 84, boxShadow: selected ? "inset 0 0 0 2px #ffd54f" : "inset 0 0 0 1px rgba(255,255,255,0.12)" }}>
      {children}
      <span style={{ opacity: selected ? 1 : 0.75 }}>{label}</span>
    </button>
  );
}

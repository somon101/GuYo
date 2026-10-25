import type { ReactNode } from "react";

// How season-pass rewards look, drawn like the app draws them (colours from the app's
// frameColors/badgeLook). Used by the reward picker so every choice is seen, not read.

export const FRAME_LOOKS: Record<string, { name: string; colors: string[] }> = {
  gold: { name: "Золото", colors: ["#FFD54F", "#FF9800", "#FFE082"] },
  aurora: { name: "Северное сияние", colors: ["#6EE7B7", "#60A5FA", "#A78BFA"] },
  fire: { name: "Огонь", colors: ["#FF7043", "#FFB74D", "#FF5252"] },
  ocean: { name: "Океан", colors: ["#38BDF8", "#2563EB", "#22D3EE"] },
  emerald: { name: "Изумруд", colors: ["#34D399", "#059669", "#6EE7B7"] },
  royal: { name: "Королевская", colors: ["#8B5CF6", "#FFD54F", "#6D28D9"] },
  rose: { name: "Роза", colors: ["#F472B6", "#FB7185", "#FDA4AF"] },
  ice: { name: "Лёд", colors: ["#BAE6FD", "#7DD3FC", "#E0F2FE"] },
};

export const BADGE_LOOKS: Record<string, { name: string; colors: [string, string]; glyph: string }> = {
  crown: { name: "Корона", colors: ["#FFE066", "#FF9800"], glyph: "👑" },
  champion: { name: "Кубок", colors: ["#FFD54F", "#FF8F00"], glyph: "🏆" },
  medal: { name: "Медаль", colors: ["#90CAF9", "#3F7CFF"], glyph: "🏅" },
  flame: { name: "Пламя", colors: ["#FFA06B", "#E5391F"], glyph: "🔥" },
  star: { name: "Звезда", colors: ["#FFE066", "#FFA000"], glyph: "⭐" },
  diamond: { name: "Бриллиант", colors: ["#7FDBFF", "#7C4DFF"], glyph: "💎" },
  rocket: { name: "Ракета", colors: ["#FF8AB8", "#8E3CFF"], glyph: "🚀" },
  shield: { name: "Щит", colors: ["#6EE7B7", "#0E9F6E"], glyph: "🛡️" },
  bolt: { name: "Молния", colors: ["#FFF176", "#FFA000"], glyph: "⚡" },
  heart: { name: "Сердце", colors: ["#FF8A8A", "#D62F4F"], glyph: "❤️" },
  leaf: { name: "Лист", colors: ["#A5E887", "#2E9E4F"], glyph: "🍃" },
};

/** A stand-in avatar: a round face on a soft background. */
function Face({ size }: { size: number }) {
  return (
    <span style={{ width: size, height: size, borderRadius: "50%", display: "inline-flex", alignItems: "center", justifyContent: "center", background: "linear-gradient(135deg,#8b93ff,#5862dd)", color: "#fff", fontWeight: 900, fontSize: size * 0.42 }}>S</span>
  );
}

/** The avatar with a season-pass frame, as the app wears it (a coloured ring round the photo). */
export function FrameAvatar({ frameKey, size = 64 }: { frameKey?: string | null; size?: number }) {
  const look = frameKey ? FRAME_LOOKS[frameKey] : undefined;
  if (!look) return <Face size={size} />;
  const ring = Math.max(2.5, size * 0.07);
  const c = look.colors;
  return (
    <span style={{ width: size, height: size, borderRadius: "50%", padding: ring, display: "inline-flex", background: `conic-gradient(${[...c, c[0]].join(",")})` }}>
      <span style={{ padding: ring * 0.35, borderRadius: "50%", background: "#12151f", display: "inline-flex" }}>
        <Face size={size - 2 * ring - ring * 0.7} />
      </span>
    </span>
  );
}

/** A badge: a round gradient with its icon. */
export function BadgeMark({ badgeKey, size = 48 }: { badgeKey?: string | null; size?: number }) {
  const look = BADGE_LOOKS[badgeKey ?? "crown"] ?? BADGE_LOOKS.crown;
  return (
    <span style={{ width: size, height: size, borderRadius: "50%", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: size * 0.5, background: `linear-gradient(135deg,${look.colors[0]},${look.colors[1]})`, boxShadow: "0 2px 6px rgba(0,0,0,0.3), inset 0 0 0 2px rgba(255,255,255,0.35)" }}>{look.glyph}</span>
  );
}

/** A title: the line of text under the name in a profile. */
export function TitleChip({ text }: { text?: string }) {
  return (
    <span style={{ display: "inline-block", padding: "2px 10px", borderRadius: 999, fontSize: 12, fontWeight: 700, color: "#0b3d2c", background: "linear-gradient(135deg,#6EE7B7,#0E9F6E)" }}>{text?.trim() || "Название титула"}</span>
  );
}

/** A mini profile: how the person looks with the chosen frame, badge and title. */
export function ProfileMock({ frame, badge, title }: { frame?: string | null; badge?: string | null; title?: string }) {
  return (
    <div className="flex items-center gap-3 rounded-2xl p-3" style={{ background: "#12151f", width: 280 }}>
      <FrameAvatar frameKey={frame} size={64} />
      <div className="min-w-0">
        <div className="flex items-center gap-2 font-black text-white">somon {badge !== undefined && badge !== null && <BadgeMark badgeKey={badge} size={22} />}</div>
        <div className="mt-1">{title !== undefined ? <TitleChip text={title} /> : <span className="text-xs text-white/40">без звания</span>}</div>
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

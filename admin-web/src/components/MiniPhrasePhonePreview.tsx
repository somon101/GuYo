import { useEffect, useState } from "react";
import { previewMiniPhrase, type MiniPhrasePreview } from "../api/endpoints";

/** Same colours as the app (mobile/lib/widgets/mini_phrases/mini_phrase_style.dart). */
const ROLE_COLOR: Record<string, string> = {
  pronoun: "#6B4EE6",
  verb: "#D9730D",
  noun: "#0E9384",
  adjective: "#C93B83",
  adverb: "#2F6FDB",
};
const ROLE_Q: Record<string, string> = {
  pronoun: "кто",
  verb: "действие",
  noun: "что",
  adjective: "какой",
  adverb: "как",
};
const color = (role: string | null) => (role && ROLE_COLOR[role]) || "#64748b";

/** A phone mock-up showing the app's explanation screen for one mini-phrase,
 * rendered by the server exactly as a learner would get it. */
export function MiniPhrasePhonePreview({ id, onClose }: { id: number; onClose: () => void }) {
  const [ui, setUi] = useState<"ru" | "tg" | "uz">("tg");
  const [data, setData] = useState<MiniPhrasePreview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setError(null);
    previewMiniPhrase(id, ui)
      .then(setData)
      .catch(() => setError("Не удалось загрузить предпросмотр"));
  }, [id, ui]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div className="flex max-h-full flex-col items-center gap-3" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-2 rounded-full bg-white/90 p-1 text-sm">
          {(["tg", "uz", "ru"] as const).map((l) => (
            <button
              key={l}
              onClick={() => setUi(l)}
              className={`rounded-full px-3 py-1 ${ui === l ? "bg-indigo-600 text-white" : "text-slate-700"}`}
            >
              {l === "tg" ? "Тоҷикӣ" : l === "uz" ? "Oʻzbek" : "Русский"}
            </button>
          ))}
          <button onClick={onClose} className="rounded-full px-3 py-1 text-slate-500 hover:text-slate-900">
            ✕
          </button>
        </div>
        <div
          className="flex w-[340px] max-w-full flex-col overflow-hidden rounded-[44px] border-[10px] border-slate-900 bg-[#F6F5FB] shadow-2xl"
          style={{ height: "min(680px, calc(100vh - 110px))" }}
          translate="no"
        >
          <div className="flex justify-center pt-2">
            <div className="h-5 w-24 rounded-full bg-slate-900" />
          </div>
          <div className="flex-1 overflow-auto px-3 py-3">
            {error && <p className="text-sm text-red-600">{error}</p>}
            {!data && !error && <p className="text-sm text-slate-500">Загрузка…</p>}
            {data && (
              <div className="rounded-3xl border border-slate-200 bg-white px-5 pb-6 pt-4 shadow-sm">
                <span className="inline-flex items-center gap-1 rounded-full bg-[#EFEBFF] px-2.5 py-1 text-xs font-bold text-[#6B4EE6]">
                  ✦ Мини-фраза
                </span>
                <p className="mt-4 flex flex-wrap gap-x-2 text-[28px] font-extrabold leading-tight">
                  {data.parts.map((p) => (
                    <span key={p.position} style={{ color: color(p.role) }}>
                      {p.text}
                    </span>
                  ))}
                </p>
                {data.translation && <p className="mt-1 text-[16px] font-medium text-slate-500">{data.translation}</p>}
                <div className="mt-5 flex flex-wrap items-start gap-2">
                  {data.parts.map((p, i) => (
                    <div key={p.position} className="flex items-start gap-2">
                      {i > 0 && <span className="pt-1.5 text-lg font-bold text-slate-400">+</span>}
                      <div className="flex flex-col items-center">
                        <span
                          className="rounded-[14px] border px-3 py-1.5 text-[16px] font-extrabold"
                          style={{ color: color(p.role), background: color(p.role) + "1F", borderColor: color(p.role) + "59" }}
                        >
                          {p.text}
                        </span>
                        <span className="mt-1 text-[11px] font-semibold text-slate-500">
                          {[p.translation, p.role && ROLE_Q[p.role]].filter(Boolean).join(" · ")}
                        </span>
                      </div>
                    </div>
                  ))}
                  <span className="pt-1.5 text-lg font-bold text-slate-400">=</span>
                  <span className="rounded-[14px] bg-[#6B4EE6] px-3.5 py-1.5 text-[16px] font-extrabold text-white">{data.text}</span>
                </div>
                {data.explanation.length > 0 && (
                  <p className="mt-5 rounded-2xl bg-[#EFEBFF] p-3.5 text-[15px] leading-relaxed text-[#3B2A8C]">
                    {data.explanation.map((s, i) => (
                      <span
                        key={i}
                        className={s.kind === "part" || s.kind === "phrase" ? "font-extrabold" : s.kind === "translation" ? "font-semibold" : ""}
                        style={s.kind === "part" ? { color: color(s.role) } : s.kind === "translation" ? { color: "#64748b" } : undefined}
                      >
                        {s.text}
                      </span>
                    ))}
                  </p>
                )}
              </div>
            )}
          </div>
          <div className="px-3 pb-5 pt-1">
            <div className="rounded-2xl bg-[#6B4EE6] py-3.5 text-center text-[16px] font-bold text-white">Дальше</div>
          </div>
        </div>
      </div>
    </div>
  );
}

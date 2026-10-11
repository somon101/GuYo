import { useEffect, useState, type CSSProperties } from "react";
import { previewMiniPhrase, type MiniPhrasePreview } from "../api/endpoints";

/**
 * A 1:1 copy of the app's mini-phrase explanation screen
 * (mobile/lib/widgets/mini_phrases/mini_phrase_explanation.dart) inside a
 * phone frame: a 360-dp-wide screen, every size in px = dp, the app's
 * colours (AppColors) for both themes and Roboto, the Android font.
 * The phrase and explanation text come from the server, exactly as a
 * learner with the chosen interface language receives them.
 */

type Ui = "tg" | "uz" | "ru";

const T: Record<string, [string, string]> = {
  "Мини-фразы": ["Мини-ибораҳо", "Mini-iboralar"],
  "Мини-фраза": ["Мини-ибора", "Mini-ibora"],
  "Собрать фразу": ["Ибораро ҷамъ кардан", "Iborani yigʻish"],
  кто: ["кӣ", "kim"],
  действие: ["амал", "harakat"],
  что: ["чӣ", "nima"],
  какой: ["чӣ гуна", "qanday"],
  как: ["чӣ тавр", "qanday qilib"],
};
const tr = (s: string, ui: Ui) =>
  ui === "ru" ? s : (T[s]?.[ui === "tg" ? 0 : 1] ?? s);

const ROLE_Q: Record<string, string> = {
  pronoun: "кто",
  verb: "действие",
  noun: "что",
  adjective: "какой",
  adverb: "как",
};

function palette(dark: boolean) {
  return {
    canvas: dark ? "#11131C" : "#F8F8FD",
    surface: dark ? "#1C1F2E" : "#FFFFFF",
    primary: dark ? "#7C84F0" : "#5862DD",
    primaryDark: dark ? "#E9EBFA" : "#101B63",
    secondaryText: dark ? "#9AA3CC" : "#7180B0",
    violetSurface: dark ? "#262A46" : "#EEF0FF",
    cardBorder: dark ? "#2A2E45" : "#EDEFF7",
    muted: dark ? "#5A6188" : "#B9BEDA",
    role: (role: string | null): string => {
      const c: Record<string, [string, string]> = {
        pronoun: ["#6B4EE6", "#A996FF"],
        verb: ["#D9730D", "#FFB35C"],
        noun: ["#0E9384", "#4FD6C4"],
        adjective: ["#C93B83", "#F48FC4"],
        adverb: ["#2F6FDB", "#7FB0FF"],
      };
      const pair = role ? c[role] : undefined;
      return pair ? pair[dark ? 1 : 0] : dark ? "#9AA3CC" : "#7180B0";
    },
  };
}

/** `#RRGGBB` + alpha 0..1 → `#RRGGBBAA` (Flutter's withValues(alpha:)). */
const alpha = (hex: string, a: number) =>
  hex +
  Math.round(a * 255)
    .toString(16)
    .padStart(2, "0");

export function MiniPhrasePhonePreview({
  id,
  onClose,
}: {
  id: number;
  onClose: () => void;
}) {
  const [ui, setUi] = useState<Ui>("tg");
  const [dark, setDark] = useState(false);
  const [data, setData] = useState<MiniPhrasePreview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [replay, setReplay] = useState(0);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const fit = () =>
      setScale(
        Math.min(
          1,
          (window.innerHeight - 90) / 784,
          (window.innerWidth - 32) / 384,
        ),
      );
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);

  useEffect(() => {
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href =
      "https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;600;700;800&display=swap";
    document.head.appendChild(link);
    return () => link.remove();
  }, []);

  useEffect(() => {
    setError(null);
    previewMiniPhrase(id, ui)
      .then((d) => {
        setData(d);
        setReplay((r) => r + 1);
      })
      .catch(() => setError("Не удалось загрузить предпросмотр"));
  }, [id, ui]);

  const c = palette(dark);
  const n = data?.parts.length ?? 0;
  const appear = (ms: number): CSSProperties => ({
    animation: `mpAppear 360ms cubic-bezier(.22,1,.36,1) ${ms}ms both`,
  });

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-4"
      onClick={onClose}
    >
      <style>{`@keyframes mpAppear{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}`}</style>
      <div
        className="flex max-h-full flex-col items-center gap-3"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex flex-wrap items-center justify-center gap-1 rounded-full bg-white/95 p-1 text-sm shadow">
          {(["tg", "uz", "ru"] as const).map((l) => (
            <button
              key={l}
              onClick={() => setUi(l)}
              className={`rounded-full px-3 py-1 ${ui === l ? "bg-indigo-600 text-white" : "text-slate-700"}`}
            >
              {l === "tg" ? "Тоҷикӣ" : l === "uz" ? "Oʻzbek" : "Русский"}
            </button>
          ))}
          <span className="mx-1 h-4 w-px bg-slate-300" />
          <button
            onClick={() => setDark((v) => !v)}
            className="rounded-full px-3 py-1 text-slate-700"
          >
            {dark ? "☀ Светлая" : "☾ Тёмная"}
          </button>
          <button
            onClick={() => setReplay((r) => r + 1)}
            className="rounded-full px-3 py-1 text-slate-700"
            title="Повторить анимацию"
          >
            ↻
          </button>
          <button
            onClick={onClose}
            className="rounded-full px-3 py-1 text-slate-500 hover:text-slate-900"
          >
            ✕
          </button>
        </div>

        {/* Phone: 360 × 760 dp screen in a frame, scaled down on short windows. */}
        <div style={{ width: 384 * scale, height: 784 * scale }}>
          <div
            style={{
              transform: `scale(${scale})`,
              transformOrigin: "top left",
            }}
          >
            <div
              translate="no"
              style={{
                width: 384,
                height: 784,
                padding: 12,
                borderRadius: 52,
                background: "#0B0B10",
                boxShadow:
                  "0 30px 60px rgba(0,0,0,.45), inset 0 0 0 2px #2a2a33",
              }}
            >
              <div
                style={{
                  width: 360,
                  height: 760,
                  borderRadius: 40,
                  overflow: "hidden",
                  background: c.canvas,
                  color: c.primaryDark,
                  fontFamily: "Roboto, system-ui, sans-serif",
                  display: "flex",
                  flexDirection: "column",
                  position: "relative",
                }}
              >
                {/* status bar */}
                <div
                  style={{
                    height: 32,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "0 22px",
                    fontSize: 13,
                    fontWeight: 500,
                    color: c.primaryDark,
                  }}
                >
                  <span>9:41</span>
                  <span
                    style={{
                      position: "absolute",
                      left: "50%",
                      top: 9,
                      width: 12,
                      height: 12,
                      marginLeft: -6,
                      borderRadius: 6,
                      background: "#0B0B10",
                    }}
                  />
                  <span style={{ letterSpacing: 1 }}>▂▄▆ ▮</span>
                </div>
                {/* AppBar (Material 3, 64 dp) */}
                <div
                  style={{
                    height: 64,
                    display: "flex",
                    alignItems: "center",
                    gap: 20,
                    padding: "0 16px",
                    color: c.primaryDark,
                  }}
                >
                  <span style={{ fontSize: 24, lineHeight: 1 }}>←</span>
                  <span style={{ fontSize: 22, fontWeight: 400 }}>
                    {tr("Мини-фразы", ui)}
                  </span>
                </div>

                {error && (
                  <p style={{ padding: 16, color: "#dc2626", fontSize: 14 }}>
                    {error}
                  </p>
                )}
                {!data && !error && (
                  <p
                    style={{
                      padding: 16,
                      color: c.secondaryText,
                      fontSize: 14,
                    }}
                  >
                    Загрузка…
                  </p>
                )}

                {data && (
                  <div
                    key={replay}
                    style={{
                      flex: 1,
                      display: "flex",
                      flexDirection: "column",
                      minHeight: 0,
                    }}
                  >
                    <div
                      style={{
                        flex: 1,
                        overflowY: "auto",
                        padding: "12px 16px 16px",
                      }}
                    >
                      <div
                        style={{
                          padding: "18px 20px 22px",
                          background: c.surface,
                          borderRadius: 24,
                          border: `1px solid ${c.cardBorder}`,
                          boxShadow: "0 4px 12px rgba(0,0,0,0.03)",
                        }}
                      >
                        <span
                          style={{
                            display: "inline-flex",
                            alignItems: "center",
                            gap: 5,
                            padding: "5px 10px",
                            background: c.violetSurface,
                            borderRadius: 30,
                            color: c.primary,
                            fontSize: 12.5,
                            fontWeight: 700,
                          }}
                        >
                          <span style={{ fontSize: 15, lineHeight: 1 }}>✦</span>
                          {tr("Мини-фраза", ui)}
                        </span>

                        <div
                          style={{
                            marginTop: 16,
                            display: "flex",
                            flexWrap: "wrap",
                            columnGap: 8,
                            rowGap: 4,
                          }}
                        >
                          {data.parts.map((p, i) => (
                            <span
                              key={p.position}
                              style={{
                                ...appear(90 * i),
                                fontSize: 30,
                                fontWeight: 800,
                                lineHeight: 1.15,
                                color: c.role(p.role),
                              }}
                            >
                              {p.text}
                            </span>
                          ))}
                        </div>
                        {data.translation && (
                          <div
                            style={{
                              marginTop: 6,
                              fontSize: 17,
                              fontWeight: 500,
                              color: c.secondaryText,
                            }}
                          >
                            {data.translation}
                          </div>
                        )}

                        <div
                          style={{
                            marginTop: 22,
                            display: "flex",
                            flexWrap: "wrap",
                            alignItems: "flex-start",
                            columnGap: 8,
                            rowGap: 10,
                          }}
                        >
                          {data.parts.map((p, i) => {
                            const col = c.role(p.role);
                            const caption = [
                              p.translation,
                              p.role && ROLE_Q[p.role]
                                ? tr(ROLE_Q[p.role], ui)
                                : null,
                            ]
                              .filter(Boolean)
                              .join(" · ");
                            return (
                              <span
                                key={p.position}
                                style={{ display: "contents" }}
                              >
                                {i > 0 && (
                                  <span
                                    style={{
                                      ...appear(250 + 140 * i),
                                      paddingTop: 6,
                                      fontSize: 20,
                                      fontWeight: 700,
                                      color: c.muted,
                                    }}
                                  >
                                    +
                                  </span>
                                )}
                                <span
                                  style={{
                                    ...appear(250 + 140 * i),
                                    display: "flex",
                                    flexDirection: "column",
                                    alignItems: "center",
                                  }}
                                >
                                  <span
                                    style={{
                                      padding: "7px 12px",
                                      borderRadius: 14,
                                      background: alpha(col, dark ? 0.2 : 0.12),
                                      border: `1.2px solid ${alpha(col, 0.35)}`,
                                      fontSize: 17,
                                      fontWeight: 800,
                                      color: col,
                                    }}
                                  >
                                    {p.text}
                                  </span>
                                  {caption && (
                                    <span
                                      style={{
                                        marginTop: 4,
                                        fontSize: 11.5,
                                        fontWeight: 600,
                                        color: c.secondaryText,
                                      }}
                                    >
                                      {caption}
                                    </span>
                                  )}
                                </span>
                              </span>
                            );
                          })}
                          <span
                            style={{
                              ...appear(250 + 140 * n),
                              paddingTop: 6,
                              fontSize: 20,
                              fontWeight: 700,
                              color: c.muted,
                            }}
                          >
                            =
                          </span>
                          <span
                            style={{
                              ...appear(330 + 140 * n),
                              padding: "7px 14px",
                              borderRadius: 14,
                              background: c.primary,
                              color: "#fff",
                              fontSize: 17,
                              fontWeight: 800,
                            }}
                          >
                            {data.text}
                          </span>
                        </div>

                        {data.explanation.length > 0 && (
                          <div
                            style={{
                              marginTop: 22,
                              padding: 14,
                              background: c.violetSurface,
                              borderRadius: 16,
                              fontSize: 15.5,
                              lineHeight: 1.45,
                              color: c.primaryDark,
                            }}
                          >
                            {data.explanation.map((s, i) => (
                              <span
                                key={i}
                                style={
                                  s.kind === "part"
                                    ? { fontWeight: 800, color: c.role(s.role) }
                                    : s.kind === "phrase"
                                      ? { fontWeight: 800 }
                                      : s.kind === "translation"
                                        ? {
                                            fontWeight: 600,
                                            color: c.secondaryText,
                                          }
                                        : undefined
                                }
                              >
                                {s.text}
                              </span>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>
                    <div style={{ padding: "4px 16px 12px" }}>
                      <div
                        style={{
                          height: 54,
                          borderRadius: 16,
                          background: c.primary,
                          color: "#fff",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          fontSize: 16.5,
                          fontWeight: 700,
                        }}
                      >
                        {tr("Собрать фразу", ui)}
                      </div>
                    </div>
                    {/* gesture bar */}
                    <div
                      style={{
                        height: 20,
                        display: "flex",
                        justifyContent: "center",
                        alignItems: "center",
                      }}
                    >
                      <span
                        style={{
                          width: 108,
                          height: 4,
                          borderRadius: 2,
                          background: c.primaryDark,
                          opacity: 0.35,
                        }}
                      />
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

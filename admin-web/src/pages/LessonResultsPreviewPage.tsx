import { useState } from "react";

// A preview only: the lesson results screen, variants A («Три награды») and C («Дорожка уроков»),
// side by side. Nothing is saved and nothing is sent to the server. Variant C is the one
// the owner chose and is already in the app; A is shown for comparison.

const BASE = `${import.meta.env.BASE_URL}`;
const INDIGO = "#5B66E8";
const GREEN = "#22A866";
const AMBER = "#F08C1A";

type Result = "pass" | "fail";

function Phone({ children, minHeight = 520 }: { children: React.ReactNode; minHeight?: number }) {
  return (
    <div className="mx-auto flex w-full max-w-sm flex-col rounded-[28px] p-5" style={{ background: "#0d0f1c", minHeight }}>
      {children}
    </div>
  );
}

function Btn({ kind, children }: { kind: "primary" | "secondary" | "ghost"; children: React.ReactNode }) {
  const styles: Record<string, React.CSSProperties> = {
    primary: { background: INDIGO, color: "#fff" },
    secondary: { background: GREEN, color: "#fff" },
    ghost: { background: "transparent", color: "rgba(255,255,255,0.6)" },
  };
  return (
    <div className="flex h-12 w-full items-center justify-center rounded-2xl text-sm font-bold uppercase tracking-wide" style={styles[kind]}>
      {children}
    </div>
  );
}

function Label({ children }: { children: React.ReactNode }) {
  return <div className="mb-2 text-center text-[11px] font-bold uppercase tracking-wide text-white/40">{children}</div>;
}

function VariantA({ result }: { result: Result }) {
  if (result === "fail") {
    return (
      <Phone>
        <div className="text-xs font-bold uppercase tracking-wide text-white/50">Урок 3</div>
        <div className="mt-2 text-3xl font-black text-white">Осталось 2 слова</div>
        <div className="mt-2 text-sm text-white/60">Это около 30 секунд. Урок засчитается сразу.</div>
        <div className="mt-6 grid grid-cols-6 gap-1.5">
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <i key={i} className="h-2 rounded-full" style={{ background: i < 4 ? GREEN : i === 4 ? "rgba(255,255,255,0.12)" : "rgba(255,255,255,0.06)", boxShadow: i >= 4 ? "inset 0 0 0 1px rgba(240,140,26,0.6)" : "none" }} />
          ))}
        </div>
        <div className="mt-6 flex items-center gap-3 rounded-2xl bg-white/5 px-4 py-3">
          <img src={`${BASE}preview/points.png`} alt="" className="h-9 w-9 object-contain" />
          <div>
            <div className="font-bold text-white">Ждёт после урока</div>
            <div className="text-xs text-white/60">+27 очков, цель дня и сундук</div>
          </div>
        </div>
        <div className="mt-auto space-y-2 pt-6">
          <Btn kind="primary">Добить 2 слова</Btn>
          <Btn kind="ghost">Позже</Btn>
        </div>
      </Phone>
    );
  }

  const days = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];
  return (
    <div className="space-y-4">
      {/* Screen 1: points and daily goal */}
      <div>
        <Label>1 · Очки и цель дня</Label>
        <Phone minHeight={300}>
          <div className="text-xs font-bold uppercase tracking-wide text-white/50">Урок 3 пройден</div>
          <div className="mt-3 flex items-center gap-2 text-6xl font-black tracking-tight text-white">
            <img src={`${BASE}preview/points.png`} alt="" className="h-14 w-14 object-contain" />
            48
          </div>
          <div className="text-sm text-white/60">очков в рейтинг</div>
          <div className="mt-5 rounded-xl bg-white/5 p-3 text-sm text-white">
            <div className="flex justify-between font-bold">
              <span>Цель дня</span>
              <span className="text-white/60">4 / 4 урока</span>
            </div>
            <div className="mt-2 h-[7px] overflow-hidden rounded-full bg-white/15">
              <div className="h-full w-full" style={{ background: GREEN }} />
            </div>
            <div className="mt-2 text-xs font-bold" style={{ color: GREEN }}>Цель дня выполнена</div>
          </div>
          <div className="mt-auto pt-5">
            <Btn kind="primary">Продолжить</Btn>
          </div>
        </Phone>
      </div>

      {/* Screen 2: streak */}
      <div>
        <Label>2 · Серия</Label>
        <Phone minHeight={300}>
          <div className="flex flex-col items-center text-center">
            <div className="flex h-20 w-20 items-center justify-center rounded-full text-3xl font-black text-white" style={{ background: "linear-gradient(160deg,#F26A1B,#FFC53D)" }}>14</div>
            <div className="mt-3 text-lg font-bold text-white">дней подряд</div>
          </div>
          <div className="mt-5 grid grid-cols-7 gap-1 text-center">
            {days.map((d, i) => (
              <div key={d} className="flex flex-col items-center gap-1 text-[10px] text-white/60">
                <span
                  className="flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold text-white"
                  style={{ background: i < 3 || i === 3 ? (i === 3 ? "transparent" : GREEN) : "rgba(255,255,255,0.08)", boxShadow: i === 3 ? `inset 0 0 0 2px ${AMBER}` : "none" }}
                >
                  {i < 3 ? "✓" : ""}
                </span>
                {d}
              </div>
            ))}
          </div>
          <div className="mt-4 text-center text-sm text-white/60">Завтра будет 15. Зайдите хотя бы на один урок.</div>
          <div className="mt-auto pt-5">
            <Btn kind="primary">Продолжить</Btn>
          </div>
        </Phone>
      </div>

      {/* Screen 3: chest */}
      <div>
        <Label>3 · Сундук</Label>
        <Phone minHeight={300}>
          <div className="text-xs font-bold uppercase tracking-wide text-white/50">Награда за цель дня</div>
          <div className="mt-1 text-2xl font-black text-white">Сундук ваш</div>
          <div className="mt-4 flex justify-center">
            <img src={`${BASE}preview/chest_closed.png`} alt="" className="h-36 w-36 object-contain" />
          </div>
          <div className="mt-4 grid grid-cols-2 gap-2">
            <div className="flex flex-col items-center rounded-xl bg-white/5 py-3">
              <img src={`${BASE}preview/gem.png`} alt="" className="h-10 w-10 object-contain" />
              <b className="mt-1 text-white">+10</b>
              <small className="text-white/60">алмазов</small>
            </div>
            <div className="flex flex-col items-center rounded-xl bg-white/5 py-3">
              <img src={`${BASE}preview/energy.png`} alt="" className="h-10 w-10 object-contain" />
              <b className="mt-1 text-white">+20</b>
              <small className="text-white/60">энергии</small>
            </div>
          </div>
          <div className="mt-auto pt-5">
            <Btn kind="primary">К урокам</Btn>
          </div>
        </Phone>
      </div>
    </div>
  );
}

function VariantC({ result }: { result: Result }) {
  const pass = result === "pass";
  return (
    <Phone>
      <div className="text-2xl font-black text-white">{pass ? "Урок 3 пройден" : "Ещё 2 слова"}</div>
      <div className="mt-3 flex flex-wrap gap-2 text-xs font-bold text-white">
        <span className="flex items-center gap-1 rounded-full bg-white/10 px-3 py-1.5">
          <img src={`${BASE}preview/points.png`} alt="" className="h-4 w-4 object-contain" /> +{pass ? 48 : 21}
        </span>
        <span className="rounded-full bg-white/10 px-3 py-1.5">{pass ? 92 : 64}% точность</span>
        <span className="rounded-full bg-white/10 px-3 py-1.5">{pass ? "2:14" : "3:02"}</span>
      </div>

      {/* Lesson track: done → current → next */}
      <div className="relative mt-8 h-44">
        <svg className="absolute inset-0 h-full w-full" viewBox="0 0 296 210" preserveAspectRatio="none">
          <path d="M60 170 C120 170 120 105 150 105 S190 40 240 40" fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth="6" strokeLinecap="round" strokeDasharray="1 14" />
        </svg>
        <Node x={20} y={81} label="2" done />
        <Node x={51} y={50} label={pass ? "3" : "4/6"} done={pass} current={!pass} />
        <Node x={81} y={19} label="4" locked={!pass} open={pass} />
      </div>

      <div className="mt-2 flex items-center gap-3 rounded-2xl bg-white/5 px-4 py-3 text-white">
        <div className="flex-1">
          <div className="font-bold">{pass ? "Урок 4 открыт" : "Урок 4 откроется после 2 слов"}</div>
          <div className="text-xs text-white/60">{pass ? "6 новых слов, около 3 минут" : "Это около 30 секунд"}</div>
        </div>
      </div>

      <div className="mt-auto space-y-2 pt-6">
        {pass ? (
          <>
            <Btn kind="primary">Начать урок 4</Btn>
            <Btn kind="ghost">На сегодня хватит</Btn>
          </>
        ) : (
          <>
            <Btn kind="secondary">Добить 2 слова</Btn>
            <Btn kind="ghost">Позже</Btn>
          </>
        )}
      </div>
    </Phone>
  );
}

function Node({ x, y, label, done, current, open, locked }: { x: number; y: number; label: string; done?: boolean; current?: boolean; open?: boolean; locked?: boolean }) {
  const bg = done ? GREEN : open ? INDIGO : "rgba(255,255,255,0.08)";
  const ring = current ? `0 0 0 3px ${AMBER}` : open ? `0 0 0 3px rgba(91,102,232,0.35)` : "none";
  return (
    <div
      className="absolute flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full text-sm font-black text-white"
      style={{ left: `${x}%`, top: `${y}%`, background: bg, boxShadow: ring, opacity: locked ? 0.45 : 1 }}
    >
      {locked ? "🔒" : label}
    </div>
  );
}

export function LessonResultsPreviewPage() {
  const [result, setResult] = useState<Result>("pass");
  return (
    <main className="mx-auto max-w-5xl space-y-5">
      <header>
        <h1 className="text-2xl font-bold">Предпросмотр итогов урока: варианты A и C</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. A «Три награды»: три экрана подряд (очки и цель дня, серия, сундук). C «Дорожка уроков» (выбран и уже в приложении): пройденный урок загорается, следующий открывается.
        </p>
      </header>

      <section className="card flex flex-wrap items-center gap-2 p-4 text-sm">
        <span className="text-slate-500">Результат:</span>
        {(
          [
            ["pass", "Пройден"],
            ["fail", "Не хватило"],
          ] as [Result, string][]
        ).map(([v, label]) => (
          <button
            key={v}
            type="button"
            onClick={() => setResult(v)}
            className={`rounded-lg px-3 py-1.5 ${result === v ? "bg-indigo-600 text-white" : "border border-slate-300 text-slate-700"}`}
          >
            {label}
          </button>
        ))}
      </section>

      <section className="grid gap-6 rounded-3xl p-6 md:grid-cols-2" style={{ background: "#12151f" }}>
        <div>
          <div className="mb-3 text-center text-xs font-bold uppercase tracking-wide text-white/50">A. Три награды</div>
          <VariantA result={result} />
        </div>
        <div>
          <div className="mb-3 text-center text-xs font-bold uppercase tracking-wide text-white/50">C. Дорожка уроков (в приложении)</div>
          <VariantC result={result} />
        </div>
      </section>
    </main>
  );
}

import { useState } from "react";

// A preview only: the lesson results screen, variants B («Счёт») and C («Дорожка уроков»),
// side by side. Nothing is saved and nothing is sent to the server. Variant C is the one
// the owner chose and is already in the app; B is shown for comparison.

const BASE = `${import.meta.env.BASE_URL}`;
const INDIGO = "#5B66E8";
const GREEN = "#22A866";
const AMBER = "#F08C1A";

type Result = "pass" | "fail";

function Phone({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto flex w-full max-w-sm flex-col rounded-[28px] p-5" style={{ background: "#0d0f1c", minHeight: 520 }}>
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

function VariantB({ result }: { result: Result }) {
  const pass = result === "pass";
  const lines = pass
    ? [["Урок пройден", 30], ["Точность 92%", 10], ["Быстро: 2:14", 8]]
    : [["Ответы", 21]];
  const total = lines.reduce((s, l) => s + (l[1] as number), 0);
  return (
    <Phone>
      <div className="text-xs font-bold uppercase tracking-wide text-white/50">{pass ? "Урок 3 пройден" : "Урок 3: осталось 2 слова"}</div>
      <div className="mt-2 text-7xl font-black tracking-tight text-white">{total}</div>
      <div className="text-sm text-white/70">очков за урок</div>

      <div className="mt-4 space-y-2">
        {(lines as [string, number][]).map(([label, pts]) => (
          <div key={label} className="flex items-center justify-between rounded-xl bg-white/5 px-3 py-2.5 text-sm text-white">
            <span>{label}</span>
            <b>+{pts}</b>
          </div>
        ))}
        {!pass && (
          <div className="flex items-center justify-between rounded-xl px-3 py-2.5 text-sm text-white/50" style={{ boxShadow: "inset 0 0 0 1.5px rgba(255,255,255,0.15)" }}>
            <span>За завершение урока</span>
            <b>+27 ждёт</b>
          </div>
        )}
      </div>

      <div className="mt-4 rounded-xl bg-white/5 px-3 py-2.5 text-sm text-white">
        <div className="flex justify-between">
          <span>Пропуск, уровень {pass ? 8 : 7}</span>
          <span className="text-white/60">{pass ? "28 / 400" : "361 / 400"}</span>
        </div>
        <div className="mt-2 h-[7px] overflow-hidden rounded-full bg-white/15">
          <div className="h-full" style={{ width: pass ? "7%" : "90%", background: "#ffd54f" }} />
        </div>
      </div>

      <div className="mt-3 flex items-center justify-between rounded-xl bg-white/5 px-3 py-2.5 text-sm text-white">
        <span>Рейтинг {pass ? "#6" : "#7"}</span>
        <span style={{ color: pass ? GREEN : AMBER }}>{pass ? "↑ Вы обошли Zarina" : "До Zarina 29 очков"}</span>
      </div>

      <div className="mt-auto space-y-2 pt-6">
        {pass ? (
          <Btn kind="primary">Продолжить</Btn>
        ) : (
          <>
            <Btn kind="primary">Добить 2 слова</Btn>
            <Btn kind="ghost">Позже</Btn>
          </>
        )}
      </div>
    </Phone>
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
        <h1 className="text-2xl font-bold">Предпросмотр итогов урока: варианты B и C</h1>
        <p className="mt-1 text-sm text-slate-500">
          Только показ. B «Счёт»: строки складываются в общее число, растут пропуск и рейтинг. C «Дорожка уроков» (выбран и уже в приложении): пройденный урок загорается, следующий открывается.
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
          <div className="mb-3 text-center text-xs font-bold uppercase tracking-wide text-white/50">B. Счёт</div>
          <VariantB result={result} />
        </div>
        <div>
          <div className="mb-3 text-center text-xs font-bold uppercase tracking-wide text-white/50">C. Дорожка уроков (в приложении)</div>
          <VariantC result={result} />
        </div>
      </section>
    </main>
  );
}

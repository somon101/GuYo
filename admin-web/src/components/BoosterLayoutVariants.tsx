import { useState } from "react";
import { BOOSTER_KINDS, type BoosterKind } from "./rewardVisuals";
import { green } from "../pages/DuelPreviewPage";

// Four compact ways to show «Мои бонусы» (the doublers), on the same made-up data.
// A preview only: nothing is sent anywhere.

const BASE = `${import.meta.env.BASE_URL}`;
const KINDS = Object.keys(BOOSTER_KINDS) as BoosterKind[];
type Held = Record<BoosterKind, Record<number, number>>;
const DATA: Held = { chest: { 30: 1, 60: 10, 1440: 0 }, rating: { 120: 10, 30: 0 }, xp: { 180: 11, 60: 0 } };
const RUNNING: Partial<Record<BoosterKind, string>> = { chest: "36:59" };
const label = (m: number) => (m >= 60 && m % 60 === 0 ? `${m / 60} ч` : `${m} мин`);
const short = (m: number) => (m >= 60 && m % 60 === 0 ? `${m / 60}ч` : `${m}м`);
const icon = (k: BoosterKind, size: number) => <img src={`${BASE}${BOOSTER_KINDS[k].icon}`} alt="" draggable={false} style={{ width: size, height: size, objectFit: "contain", flexShrink: 0 }} />;
const total = (k: BoosterKind) => Object.values(DATA[k]).reduce((a, b) => a + b, 0);
const visible = KINDS.filter((k) => total(k) > 0 || RUNNING[k]);
const timer = (t: string) => <span className="rounded-full px-2 py-0.5 text-[11px] font-black" style={{ background: "rgba(0,0,0,0.35)", color: "#ffd54f", boxShadow: "inset 0 0 0 1.5px #ffd54f" }}>{t}</span>;
const plate = (n: number) => <span className="rounded-full px-1.5 text-[11px] font-black text-white" style={{ background: "#1b1247", boxShadow: "0 0 0 1.5px #ffc928" }}>{n}</span>;
const btn = (text = "Включить", small = true) => <button className={`${small ? "px-3 py-1 text-[11px]" : "px-4 py-1.5 text-xs"} shrink-0 rounded-lg font-black uppercase`} style={green}>{text}</button>;

function Phone({ title, note, children }: { title: string; note: string; children: React.ReactNode }) {
  return (
    <div className="w-[300px] shrink-0">
      <div className="mb-1 text-sm font-bold">{title}</div>
      <div className="mb-2 text-xs text-slate-500">{note}</div>
      <div className="rounded-3xl p-3 text-white" style={{ background: "linear-gradient(160deg,#2b1f6e,#1b1247)", minHeight: 360 }}>
        <div className="mb-2 text-center text-sm font-black">Мои сундуки · 372</div>
        {children}
      </div>
    </div>
  );
}

const chests = (
  <div className="mt-2 flex gap-2 rounded-2xl p-2" style={{ background: "rgba(255,255,255,0.1)" }}>
    {["wood", "silver", "purple", "gold"].map((c) => <img key={c} src={`${BASE}chests/${c}_closed.png`} alt="" style={{ width: 44, height: 44, objectFit: "contain" }} />)}
  </div>
);

function A() {
  const [open, setOpen] = useState<BoosterKind | null>("chest");
  return (
    <Phone title="A · Плитки" note="Одна строка на вид; сроки раскрываются нажатием.">
      <div className="space-y-1.5">
        {visible.map((k) => (
          <div key={k} className="rounded-xl p-2" style={{ background: "rgba(255,255,255,0.12)" }}>
            <button className="flex w-full items-center gap-2 text-left" onClick={() => setOpen(open === k ? null : k)}>
              {icon(k, 34)}<span className="min-w-0 flex-1 truncate text-xs font-black">{BOOSTER_KINDS[k].label}</span>
              {RUNNING[k] && timer(RUNNING[k]!)}{plate(total(k))}<span className="text-white/60">{open === k ? "▴" : "▾"}</span>
            </button>
            {open === k && (
              <div className="mt-2 space-y-1">
                {Object.entries(DATA[k]).filter(([, q]) => q > 0).map(([m, q]) => (
                  <div key={m} className="flex items-center gap-2 rounded-lg px-2 py-1" style={{ background: "rgba(0,0,0,0.2)" }}>
                    <span className="flex-1 text-xs font-bold">{label(Number(m))}</span>{plate(q)}{btn()}
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
      {chests}
    </Phone>
  );
}

function B() {
  const [pick, setPick] = useState<Record<string, number>>({ chest: 60, rating: 120, xp: 180 });
  return (
    <Phone title="B · Чипы" note="Сроки маленькими чипами, одна кнопка на вид; пустые не показываются.">
      <div className="space-y-2">
        {visible.map((k) => (
          <div key={k} className="rounded-xl p-2" style={{ background: "rgba(255,255,255,0.12)" }}>
            <div className="flex items-center gap-2">{icon(k, 30)}<span className="min-w-0 flex-1 truncate text-xs font-black">{BOOSTER_KINDS[k].label}</span>{RUNNING[k] && timer(RUNNING[k]!)}</div>
            <div className="mt-1.5 flex items-center gap-1.5">
              <div className="flex min-w-0 flex-1 flex-wrap gap-1">
                {Object.entries(DATA[k]).filter(([, q]) => q > 0).map(([m, q]) => (
                  <button key={m} onClick={() => setPick({ ...pick, [k]: Number(m) })} className="rounded-full px-2 py-0.5 text-[11px] font-black" style={{ background: pick[k] === Number(m) ? "#ffd54f" : "rgba(0,0,0,0.3)", color: pick[k] === Number(m) ? "#1b1247" : "#fff" }}>{short(Number(m))} · {q}</button>
                ))}
              </div>
              {btn()}
            </div>
          </div>
        ))}
      </div>
      {chests}
    </Phone>
  );
}

function C() {
  const [tab, setTab] = useState<BoosterKind>(visible[0]);
  return (
    <Phone title="C · Вкладки" note="Три вкладки-иконки; внутри сетка билетов.">
      <div className="mb-2 flex gap-1">
        {visible.map((k) => (
          <button key={k} onClick={() => setTab(k)} className="flex flex-1 items-center justify-center gap-1 rounded-xl py-1" style={{ background: tab === k ? "rgba(255,213,79,0.25)" : "rgba(255,255,255,0.1)", boxShadow: tab === k ? "inset 0 0 0 1.5px #ffd54f" : undefined }}>
            {icon(k, 26)}{RUNNING[k] ? timer(RUNNING[k]!) : plate(total(k))}
          </button>
        ))}
      </div>
      <div className="mb-1 text-[11px] text-white/70">{BOOSTER_KINDS[tab].label}: {BOOSTER_KINDS[tab].does}</div>
      <div className="grid grid-cols-2 gap-1.5">
        {Object.entries(DATA[tab]).filter(([, q]) => q > 0).map(([m, q]) => (
          <div key={m} className="flex flex-col items-center gap-1 rounded-xl p-2" style={{ background: "rgba(255,255,255,0.12)" }}>
            <div className="relative">{icon(tab, 40)}<span className="absolute -bottom-1 -right-2">{plate(q)}</span></div>
            <div className="text-xs font-black">{label(Number(m))}</div>{btn()}
          </div>
        ))}
      </div>
      {chests}
    </Phone>
  );
}

function D() {
  const [panel, setPanel] = useState(false);
  return (
    <Phone title="D · Полоса" note="Узкая полоса сверху, панель выезжает; сундуки сразу под ней.">
      <button className="flex w-full items-center gap-2 rounded-xl px-2 py-1.5" style={{ background: "rgba(255,255,255,0.12)" }} onClick={() => setPanel(!panel)}>
        <span className="text-xs font-black">Бонусы</span>
        <span className="flex flex-1 items-center justify-end gap-2">{visible.map((k) => <span key={k} className="flex items-center gap-1">{icon(k, 24)}{RUNNING[k] ? timer(RUNNING[k]!) : plate(total(k))}</span>)}</span>
        <span className="text-white/60">{panel ? "▴" : "▾"}</span>
      </button>
      {panel && (
        <div className="mt-1.5 space-y-1 rounded-xl p-2" style={{ background: "rgba(0,0,0,0.25)" }}>
          {visible.flatMap((k) => Object.entries(DATA[k]).filter(([, q]) => q > 0).map(([m, q]) => (
            <div key={`${k}${m}`} className="flex items-center gap-2">{icon(k, 24)}<span className="flex-1 truncate text-[11px] font-bold">{BOOSTER_KINDS[k].label} · {label(Number(m))}</span>{plate(q)}{btn()}</div>
          )))}
        </div>
      )}
      {chests}
      <div className="mt-2 text-center text-[11px] text-white/50">…дальше список сундуков, листать не нужно</div>
    </Phone>
  );
}

export function BoosterLayoutVariants() {
  return (
    <section className="card space-y-3 p-4">
      <h2 className="text-lg font-semibold">Варианты компактного вида «Мои бонусы»</h2>
      <p className="text-sm text-slate-500">Одни и те же данные в четырёх видах. Нажимайте, раскрывайте, переключайте. Скажите букву, какой вариант нравится (можно собрать из нескольких).</p>
      <div className="flex gap-4 overflow-x-auto pb-2"><A /><B /><C /><D /></div>
    </section>
  );
}

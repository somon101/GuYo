import { useState } from "react";
import {
  checkLanguage,
  publishLanguage,
  unpublishLanguage,
  type LanguageCheck,
  type LanguageDetail,
  type ReadinessIssue,
} from "../api/endpoints";

const KINDS: { kind: "learn" | "native"; label: string; field: "learn_published" | "native_published" }[] = [
  { kind: "learn", label: "Для изучения", field: "learn_published" },
  { kind: "native", label: "Как язык перевода", field: "native_published" },
];

function when(at: string | undefined): string {
  return at ? new Date(at).toLocaleString("ru-RU", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "";
}

/** Публикация языка: язык можно выбрать в приложении (изучать / читать на нём)
 * только когда проверка не нашла ни одного недостатка. Здесь видно, чего
 * не хватает, и почему публикацию сняли. */
export function LanguagePublication({ language, onChanged }: { language: LanguageDetail; onChanged: () => void }) {
  const [check, setCheck] = useState<LanguageCheck | null>(language.last_check);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await action();
      setCheck(await checkLanguage(language.code));
      onChanged();
    } catch (e: unknown) {
      const detail = (e as { response?: { data?: { detail?: { message?: string; issues?: ReadinessIssue[] } | string } } })
        ?.response?.data?.detail;
      setError(typeof detail === "string" ? detail : detail?.message ?? "Не удалось выполнить");
      try {
        setCheck(await checkLanguage(language.code));
      } catch {
        /* the list stays as it was */
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-4 rounded-xl border border-slate-200 p-3">
      <div className="mb-2 flex items-center justify-between gap-2">
        <span className="text-sm font-semibold text-slate-800">Публикация</span>
        <button
          onClick={() => run(async () => {})}
          disabled={busy}
          className="btn-tinted rounded-full px-3 py-1 text-xs font-medium disabled:opacity-60"
        >
          {busy ? "Проверяем…" : "Проверить"}
        </button>
      </div>
      {check && <p className="mb-2 text-[11px] text-slate-400">Проверено {when(check.checked_at)}</p>}
      {error && <p className="mb-2 text-xs text-red-600">{error}</p>}
      <div className="flex flex-col gap-3">
        {KINDS.map(({ kind, label, field }) => {
          const published = language[field];
          const issues = check?.[kind] ?? null;
          const removed = check?.unpublished?.filter((u) => u.kind === kind).at(-1);
          const kept = check?.kept?.includes(kind);
          return (
            <div key={kind}>
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm text-slate-700">{label}:</span>
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                    published ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-500"
                  }`}
                >
                  {published ? "опубликован" : "не опубликован"}
                </span>
                {published ? (
                  <button
                    onClick={() => run(() => unpublishLanguage(language.code, kind))}
                    disabled={busy}
                    className="text-xs text-slate-500 hover:underline disabled:opacity-60"
                  >
                    снять
                  </button>
                ) : (
                  <button
                    onClick={() => run(() => publishLanguage(language.code, kind))}
                    disabled={busy || issues === null || issues.length > 0}
                    title={issues === null ? "Сначала нажмите «Проверить»" : issues.length ? "Сначала исправьте недостатки" : ""}
                    className="rounded-full bg-indigo-600 px-3 py-1 text-xs font-medium text-white hover:bg-indigo-700 disabled:opacity-40"
                  >
                    Опубликовать
                  </button>
                )}
              </div>
              {removed && !published && (
                <p className="mt-1 text-xs text-red-600">Снят автоматически {when(removed.at)}: {removed.reason.join("; ")}</p>
              )}
              {kept && published && (
                <p className="mt-1 text-xs text-amber-700">
                  Есть недостатки, но язык не снят: это последний опубликованный язык этого вида.
                </p>
              )}
              {issues && issues.length === 0 && <p className="mt-1 text-xs text-emerald-700">Всё на месте — 100%.</p>}
              {issues && issues.length > 0 && (
                <ul className="mt-1 space-y-1">
                  {issues.map((i) => (
                    <li key={i.code} className="text-xs">
                      <span className="font-medium text-red-600">{i.text}</span>
                      {i.examples.length > 0 && (
                        <span className="ml-1 text-slate-500" translate="no">
                          — {i.examples.slice(0, 8).join(", ")}
                          {i.count > 8 ? " …" : ""}
                        </span>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

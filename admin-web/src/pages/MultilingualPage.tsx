import { useEffect, useState } from "react";
import { getMultilingualStatus, type MultilingualStatus } from "../api/endpoints";

const LANGUAGE_LABELS: Record<string, string> = {
  ru: "Русский",
  tg: "Тоҷикӣ",
  uz: "Oʻzbekcha",
  en: "English",
  zh: "中文",
};

const label = (code: string) => LANGUAGE_LABELS[code] ?? code;

/**
 * «Многоязычность»: что реально лежит в новой структуре.
 *
 * Одно понятие («Человек») живёт записями на нескольких языках, и человек учит
 * то, что выбрал в настройках. Страница показывает, чего по каждому языку не
 * хватает -- прежде всего озвучки и форм, -- и прогоняет сверку переноса.
 */
export function MultilingualPage() {
  const [status, setStatus] = useState<MultilingualStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    getMultilingualStatus()
      .then((data) => {
        if (!cancelled) setStatus(data);
      })
      .catch(() => {
        if (!cancelled) setError("Не удалось загрузить состояние многоязычности");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const tile = "card flex flex-col gap-1 p-4";
  const tileLabel = "text-xs font-medium uppercase tracking-wide text-slate-400";
  const tileValue = "text-[24px] font-bold tracking-tight text-slate-900";

  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">
        Многоязычность
      </h1>
      <p className="mb-6 text-sm text-slate-500">
        Одно понятие — записи на разных языках. Человек учит тот язык, что выбрал в
        настройках, а подсказки видит на своём родном.
      </p>

      {loading && <p className="text-sm text-slate-500">Считаем…</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}

      {status && !loading && (
        <>
          <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className={tile}>
              <span className={tileLabel}>Понятия</span>
              <span className={tileValue}>{status.totals.concepts}</span>
            </div>
            <div className={tile}>
              <span className={tileLabel}>Языковые записи</span>
              <span className={tileValue}>{status.totals.word_entries}</span>
            </div>
            <div className={tile}>
              <span className={tileLabel}>Формы</span>
              <span className={tileValue}>{status.totals.word_entry_forms}</span>
            </div>
            <div className={tile}>
              <span className={tileLabel}>Понятия фраз</span>
              <span className={tileValue}>{status.totals.phrase_concepts}</span>
              <span className="text-xs text-slate-400">
                записи фраз: {status.totals.phrase_entries}
              </span>
            </div>
          </div>

          <section className="mb-8">
            <h2 className="mb-2 text-lg font-semibold text-slate-900">По языкам</h2>
            <p className="mb-3 text-xs text-slate-500">
              Красным — там, где данных нет вовсе: без озвучки не работают упражнения
              «Произнеси слово» и «Услышь слово», без форм не собираются мини-фразы.
            </p>
            <div className="card overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-[var(--fill)] text-left text-xs uppercase tracking-wide text-slate-500">
                  <tr>
                    <th className="px-4 py-2 font-medium">Язык</th>
                    <th className="px-4 py-2 font-medium">Записей</th>
                    <th className="px-4 py-2 font-medium">С озвучкой</th>
                    <th className="px-4 py-2 font-medium">С транскрипцией</th>
                    <th className="px-4 py-2 font-medium">Форм</th>
                  </tr>
                </thead>
                <tbody>
                  {status.languages.map((row) => (
                    <tr key={row.language} className="border-t border-[var(--separator)]">
                      <td className="px-4 py-2 font-medium text-slate-900">
                        {label(row.language)}
                      </td>
                      <td className="px-4 py-2 text-slate-700">{row.entries}</td>
                      <td
                        className={`px-4 py-2 ${row.with_audio === 0 ? "font-medium text-red-600" : "text-slate-700"}`}
                      >
                        {row.with_audio}
                      </td>
                      <td className="px-4 py-2 text-slate-700">{row.with_transcription}</td>
                      <td
                        className={`px-4 py-2 ${row.forms === 0 ? "font-medium text-red-600" : "text-slate-700"}`}
                      >
                        {row.forms}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          {status.sample && (
            <section className="mb-8">
              <h2 className="mb-2 text-lg font-semibold text-slate-900">
                Пример: понятие №{status.sample.concept_id}
              </h2>
              <p className="mb-3 text-xs text-slate-500">
                Одно и то же понятие на всех языках — это и есть многоязычная структура.
              </p>
              <ul className="flex flex-col gap-2">
                {status.sample.entries.map((entry) => (
                  <li
                    key={entry.language}
                    className="card flex flex-wrap items-center justify-between gap-2 p-3"
                  >
                    <span className="text-sm font-medium text-slate-900">
                      {label(entry.language)}: {entry.text || "—"}
                    </span>
                    <span className="text-xs text-slate-500">
                      аудио: {entry.has_audio ? "есть" : "нет"} · форм: {entry.forms}
                    </span>
                  </li>
                ))}
              </ul>
            </section>
          )}

          <section>
            <h2 className="mb-2 text-lg font-semibold text-slate-900">
              Сверка переноса
            </h2>
            {status.checks_failed === 0 ? (
              <p className="mb-3 text-sm text-emerald-700">
                Все {status.checks.length} проверок пройдены: старая и новая структуры
                сходятся.
              </p>
            ) : (
              <p className="mb-3 text-sm font-semibold text-red-600">
                Провалено проверок: {status.checks_failed} из {status.checks.length}
              </p>
            )}
            <ul className="flex flex-col gap-1">
              {status.checks.map((check) => (
                <li key={check.name} className="flex items-baseline gap-2 text-sm">
                  <span className={check.ok ? "text-emerald-600" : "text-red-600"}>
                    {check.ok ? "✓" : "✗"}
                  </span>
                  <span className={check.ok ? "text-slate-600" : "font-medium text-red-700"}>
                    {check.name}
                  </span>
                  {check.detail && (
                    <span className="text-xs text-slate-400">{check.detail}</span>
                  )}
                </li>
              ))}
            </ul>
          </section>
        </>
      )}
    </div>
  );
}

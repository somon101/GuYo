import { useEffect, useState } from "react";
import { Link, Navigate } from "react-router-dom";
import { listDictionaries } from "../api/endpoints";
import type { Dictionary } from "../types";

/** Раздел «База» — само содержимое: понятия, слова, фразы, мини-фразы.
 *
 * Раньше до него надо было идти окольным путём: открыть язык, найти слово,
 * перейти по номеру понятия. Теперь это отдельный раздел меню, и языки к нему
 * отношения не имеют — язык лишь срез этих данных.
 *
 * Когда набор понятий один (обычный случай), раздел открывает его содержимое
 * СРАЗУ — список слов с категориями и вкладками, — без промежуточной карточки.
 * Промежуточный список нужен, только если наборов несколько. */
export function BasePage() {
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    listDictionaries()
      .then((data) => {
        if (!cancelled) setDictionaries(data);
      })
      .catch(() => {
        if (!cancelled) setError("Не удалось загрузить базу");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (isLoading) {
    return <p className="text-sm text-slate-500">Загрузка…</p>;
  }
  if (error) {
    return <p className="text-sm text-red-600">{error}</p>;
  }
  if (dictionaries.length === 1) {
    return <Navigate to={`/dictionaries/${dictionaries[0].id}`} replace />;
  }

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">База</h1>
      <p className="mb-6 text-sm text-slate-500">
        Понятия и всё, что к ним привязано: слова, переводы, формы, фразы и мини-фразы. Одно
        понятие — записи на всех языках, поэтому правка здесь меняет все языки сразу.
      </p>

      <ul className="flex flex-col gap-3">
        {dictionaries.map((d) => (
          <li key={d.id} className="card p-5">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <p className="text-base font-medium text-slate-900">{d.name}</p>
              <span className="text-xs text-slate-400">
                {d.word_count} слов · {d.is_published ? "опубликован" : "черновик"}
              </span>
            </div>

            <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
              <Link
                to={`/dictionaries/${d.id}`}
                className="btn-tinted rounded-lg px-3 py-2 text-center text-sm font-medium"
              >
                Слова
              </Link>
              <Link
                to={`/dictionaries/${d.id}/phrases`}
                className="btn-tinted rounded-lg px-3 py-2 text-center text-sm font-medium"
              >
                Фразы
              </Link>
              <Link
                to={`/dictionaries/${d.id}/mini-phrases`}
                className="btn-tinted rounded-lg px-3 py-2 text-center text-sm font-medium"
              >
                Мини-фразы
              </Link>
              <Link
                to={`/dictionaries/${d.id}/audit`}
                className="btn-tinted rounded-lg px-3 py-2 text-center text-sm font-medium"
              >
                Аудит
              </Link>
            </div>
          </li>
        ))}
        {dictionaries.length === 0 && <p className="text-sm text-slate-500">База пуста.</p>}
      </ul>
    </div>
  );
}

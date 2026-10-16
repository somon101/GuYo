import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { listLanguageWords, type LanguageWord } from "../api/endpoints";

/** Слова одного языка: то, что человек учит, выбрав этот язык.
 *
 * Понятия общие, поэтому каждая строка ведёт в карточку понятия — там правятся
 * сразу все языки. Здесь же видно, чего у записи не хватает: озвучки или форм. */
export function LanguageWordsPage() {
  const { code = "" } = useParams();
  const [rows, setRows] = useState<LanguageWord[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    listLanguageWords(code, { search, limit: 100 })
      .then((data) => {
        if (cancelled) return;
        setRows(data.entries);
        setTotal(data.total);
      })
      .catch(() => {
        if (!cancelled) setError("Не удалось загрузить слова этого языка");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [code, search]);

  return (
    <div className="mx-auto max-w-4xl">
      <Link to="/dictionaries" className="mb-4 inline-block text-sm text-indigo-600 hover:underline">
        ← Языки
      </Link>
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">
        Слова языка «{code}»
      </h1>
      <p className="mb-4 text-sm text-slate-500">
        Всего записей: {total}. Каждая ведёт в карточку понятия — там правятся все языки
        сразу.
      </p>

      <input
        className="mb-4 w-full max-w-sm field px-3 py-2 text-sm"
        placeholder="Поиск по слову"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      {loading && <p className="text-sm text-slate-500">Загрузка…</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}

      {!loading && !error && (
        <div className="card overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-[var(--fill)] text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-2 font-medium">Слово</th>
                <th className="px-4 py-2 font-medium">Транскрипция</th>
                <th className="px-4 py-2 font-medium">Озвучка</th>
                <th className="px-4 py-2 font-medium">Формы</th>
                <th className="px-4 py-2 font-medium" />
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id} className="border-t border-[var(--separator)]">
                  <td className="px-4 py-2 font-medium text-slate-900">{row.text}</td>
                  <td className="px-4 py-2 text-slate-600">{row.transcription || "—"}</td>
                  <td className={`px-4 py-2 ${row.has_audio ? "text-slate-600" : "text-red-600"}`}>
                    {row.has_audio ? "есть" : "нет"}
                  </td>
                  <td className={`px-4 py-2 ${row.forms > 0 ? "text-slate-600" : "text-red-600"}`}>
                    {row.forms}
                  </td>
                  <td className="px-4 py-2">
                    <Link
                      to={`/languages/${code}/words/${row.id}`}
                      className="text-indigo-600 hover:underline"
                    >
                      Открыть →
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {rows.length === 0 && (
            <p className="p-4 text-sm text-slate-500">
              У этого языка пока нет слов — их наполняют в карточке понятия, импортом или
              ИИ-генератором.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

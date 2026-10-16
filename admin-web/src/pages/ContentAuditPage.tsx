import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { getContentAudit, type ContentAudit } from "../api/endpoints";
import { LanguageSectionTabs } from "../components/LanguageSectionTabs";

/** Клик по фразе открывает её редактор. */
function phraseLink(dictionaryId: number, phraseId: number) {
  return `/dictionaries/${dictionaryId}/phrases/${phraseId}`;
}

/**
 * «Аудит контента»: что не сходится в словаре.
 *
 * Фраза не хранит ссылок на слова -- её слова выводятся из текста предложения, --
 * поэтому фраза может использовать слово, которого в словаре нет. Такая фраза
 * никому и никогда не показывается (человек видит фразу только когда выучил ВСЕ её
 * слова), и до этого отчёта об этом никто не узнавал. Мини-фразы наоборот всегда
 * ссылаются на слово, но их часть может не совпадать ни со словом, ни с одной его
 * формой -- тогда в упражнении слово не подсветится.
 */
export function ContentAuditPage() {
  const { id } = useParams();
  const dictionaryId = Number(id);
  const [audit, setAudit] = useState<ContentAudit | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    getContentAudit(dictionaryId)
      .then((data) => {
        if (!cancelled) setAudit(data);
      })
      .catch(() => {
        if (!cancelled) setError("Не удалось загрузить аудит контента");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [dictionaryId]);

  const tile =
    "card p-4 flex flex-col gap-1";
  const tileLabel = "text-xs font-medium uppercase tracking-wide text-slate-400";
  const tileValue = "text-[26px] font-bold tracking-tight text-slate-900";

  return (
    <div className="mx-auto max-w-3xl">
      <Link
        to="/dictionaries"
        className="mb-4 inline-block text-sm text-indigo-600 hover:underline"
      >
        ← Все языки
      </Link>

      <LanguageSectionTabs dictionaryId={dictionaryId} active="audit" />

      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">
        Аудит контента
      </h1>
      <p className="mb-6 text-sm text-slate-500">
        Проверка, что все слова фраз есть в словаре, а части мини-фраз совпадают со
        своими словами и формами.
      </p>

      {loading && <p className="text-sm text-slate-500">Считаем…</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}

      {audit && !loading && (
        <>
          <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className={tile}>
              <span className={tileLabel}>Слов в словаре</span>
              <span className={tileValue}>{audit.words_in_dictionary}</span>
            </div>
            <div className={tile}>
              <span className={tileLabel}>Слов и форм</span>
              <span className={tileValue}>{audit.tokens_available}</span>
              <span className="text-xs text-slate-400">
                по ним ищем слова фраз
              </span>
            </div>
            <div className={tile}>
              <span className={tileLabel}>Фраз готовы</span>
              <span className={tileValue}>
                {audit.phrases.ready}
                <span className="text-base font-medium text-slate-400">
                  {" "}
                  / {audit.phrases.total}
                </span>
              </span>
            </div>
            <div className={tile}>
              <span className={tileLabel}>Частей без формы</span>
              <span
                className={
                  audit.mini_phrases.parts_without_matching_form > 0
                    ? "text-[26px] font-bold tracking-tight text-red-600"
                    : "text-[26px] font-bold tracking-tight text-emerald-600"
                }
              >
                {audit.mini_phrases.parts_without_matching_form}
              </span>
              <span className="text-xs text-slate-400">
                из {audit.mini_phrases.parts_total} частей
              </span>
            </div>
          </div>

          {audit.phrases.with_missing_words === 0 ? (
            <div className="mb-6 card p-4 text-sm text-emerald-700">
              Все фразы обеспечены словами словаря — ни одна не скрыта из-за
              пропущенного слова.
            </div>
          ) : (
            <div className="mb-6 card p-4">
              <p className="text-sm font-semibold text-red-600">
                {audit.phrases.with_missing_words} фраз(ы) используют слова, которых
                нет в словаре
              </p>
              <p className="mt-1 text-xs text-slate-500">
                Фраза показывается человеку только когда выучены ВСЕ её слова.
                Значит эти фразы сейчас не видит никто: добавьте слова в словарь или
                перепишите фразы.
              </p>
            </div>
          )}

          {audit.missing_words.length > 0 && (
            <section className="mb-8">
              <h2 className="mb-2 text-lg font-semibold text-slate-900">
                Чего не хватает в словаре
              </h2>
              <p className="mb-3 text-xs text-slate-500">
                Готовый список для наполнения: столько слов нужно добавить (или
                переписать использующие их фразы).
              </p>
              <div className="card overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-[var(--fill)] text-left text-xs uppercase tracking-wide text-slate-500">
                    <tr>
                      <th className="px-4 py-2 font-medium">Слово</th>
                      <th className="px-4 py-2 font-medium">Фраз</th>
                      <th className="px-4 py-2 font-medium">Пример фразы</th>
                    </tr>
                  </thead>
                  <tbody>
                    {audit.missing_words.map((row) => (
                      <tr key={row.word} className="border-t border-[var(--separator)]">
                        <td className="px-4 py-2 font-medium text-slate-900">
                          {row.word}
                        </td>
                        <td className="px-4 py-2 text-slate-600">{row.phrases}</td>
                        <td className="px-4 py-2 text-slate-500">
                          {row.example ?? "—"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}

          {audit.phrases.items.length > 0 && (
            <section className="mb-8">
              <h2 className="mb-2 text-lg font-semibold text-slate-900">
                Фразы с пропущенными словами
              </h2>
              <ul className="flex flex-col gap-2">
                {audit.phrases.items.map((phrase) => (
                  <li key={phrase.id} className="card p-4">
                    <Link
                      to={phraseLink(dictionaryId, phrase.id)}
                      className="text-sm font-medium text-slate-900 hover:text-indigo-600"
                    >
                      {phrase.original}
                    </Link>
                    <p className="mt-1 text-xs text-red-600">
                      Не хватает: {phrase.missing.join(", ")}
                    </p>
                  </li>
                ))}
              </ul>
            </section>
          )}

          <section>
            <h2 className="mb-2 text-lg font-semibold text-slate-900">
              Мини-фразы
            </h2>
            {audit.mini_phrases.items.length === 0 ? (
              <p className="text-sm text-slate-500">
                Все {audit.mini_phrases.parts_total} частей совпадают со своими
                словами или формами — проблем нет.
              </p>
            ) : (
              <ul className="flex flex-col gap-2">
                {audit.mini_phrases.items.map((part) => (
                  <li
                    key={`${part.mini_phrase_id}-${part.position}`}
                    className="card p-4"
                  >
                    <p className="text-sm font-medium text-slate-900">
                      Фраза: {part.mini_phrase}
                    </p>
                    <p className="mt-1 text-xs text-red-600">
                      Часть «{part.part_text}» ссылается на слово «{part.word}», но
                      ни слово, ни одна его форма так не называются — добавьте форму
                      «{part.part_text}» слову «{part.word}».
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}
    </div>
  );
}

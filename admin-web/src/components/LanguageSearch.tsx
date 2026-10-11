import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { listPhrases, listWords } from "../api/endpoints";
import type { Phrase, Word } from "../types";
import { matches } from "../utils/search";
import { SearchBox } from "./SearchBox";

/** Search across every word (or phrase) of a language, shown on the
 * category screens: while the query is empty the page shows its categories
 * as usual; once typed, the whole list is loaded once and the matches
 * replace the categories. */
export function LanguageSearch({
  dictionaryId,
  kind,
  query,
  onQuery,
}: {
  dictionaryId: number;
  kind: "words" | "phrases";
  query: string;
  onQuery: (q: string) => void;
}) {
  const [words, setWords] = useState<Word[] | null>(null);
  const [phrases, setPhrases] = useState<Phrase[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const active = query.trim() !== "";

  useEffect(() => {
    if (!active) return;
    if (kind === "words" && words === null) {
      listWords(dictionaryId)
        .then(setWords)
        .catch(() => setError("Не удалось загрузить слова"));
    }
    if (kind === "phrases" && phrases === null) {
      listPhrases(dictionaryId)
        .then(setPhrases)
        .catch(() => setError("Не удалось загрузить фразы"));
    }
  }, [active, kind, dictionaryId, words, phrases]);

  const foundWords = (words ?? []).filter((w) =>
    matches(
      query,
      w.word,
      w.transcription,
      w.category_name,
      ...w.forms.map((f) => f.text),
      ...w.translations.map((t) => t.text),
    ),
  );
  const foundPhrases = (phrases ?? []).filter((p) =>
    matches(
      query,
      p.original,
      p.translation_tg,
      p.translation_uz,
      p.translation_en,
      p.transcription,
      p.category_name,
    ),
  );
  const loaded = kind === "words" ? words !== null : phrases !== null;

  return (
    <>
      <SearchBox
        value={query}
        onChange={onQuery}
        placeholder={
          kind === "words"
            ? "Поиск по всем словам языка: слово, форма, перевод, тема"
            : "Поиск по всем фразам языка: фраза, перевод, тема"
        }
        found={
          loaded
            ? kind === "words"
              ? foundWords.length
              : foundPhrases.length
            : undefined
        }
      />
      {active && error && <p className="mb-4 text-sm text-red-600">{error}</p>}
      {active && !loaded && !error && (
        <p className="mb-4 text-sm text-slate-500">Поиск…</p>
      )}
      {active && loaded && (
        <ul className="mb-6 flex flex-col gap-2" translate="no">
          {kind === "words"
            ? foundWords.slice(0, 200).map((w) => (
                <li key={w.id}>
                  <Link
                    to={`/dictionaries/${dictionaryId}/words/${w.id}`}
                    className="card card-link flex flex-wrap items-baseline gap-x-3 gap-y-1 p-3.5"
                  >
                    <span className="font-serif text-[17px] font-medium text-slate-900">
                      {w.word}
                    </span>
                    <span className="font-serif text-[15px] text-slate-600">
                      {w.translation}
                    </span>
                    {w.category_name && (
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-500">
                        {w.category_name}
                      </span>
                    )}
                    <span className="ml-auto text-sm text-indigo-600">
                      Редактировать →
                    </span>
                  </Link>
                </li>
              ))
            : foundPhrases.slice(0, 200).map((p) => (
                <li key={p.id}>
                  <Link
                    to={`/dictionaries/${dictionaryId}/phrases/${p.id}`}
                    className="card card-link flex flex-wrap items-baseline gap-x-3 gap-y-1 p-3.5"
                  >
                    <span className="font-serif text-[17px] font-medium text-slate-900">
                      {p.original}
                    </span>
                    <span className="font-serif text-[15px] text-slate-600">
                      {p.translation_tg}
                    </span>
                    {p.category_name && (
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-500">
                        {p.category_name}
                      </span>
                    )}
                    <span className="ml-auto text-sm text-indigo-600">
                      Редактировать →
                    </span>
                  </Link>
                </li>
              ))}
          {(kind === "words" ? foundWords.length : foundPhrases.length) >
            200 && (
            <li className="text-xs text-slate-500">
              Показаны первые 200 — уточните запрос
            </li>
          )}
        </ul>
      )}
    </>
  );
}

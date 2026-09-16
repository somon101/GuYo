import { Link } from "react-router-dom";

/** Switches between a language block's two content areas -- Слова (Words)
 * and Фразы (Phrases). Each is its own top-level tree (own categories, own
 * editor); this is just the shared nav shown at the top of both. */
export function LanguageSectionTabs({
  dictionaryId,
  active,
}: {
  dictionaryId: number;
  active: "words" | "phrases";
}) {
  const tabClass = (isActive: boolean) =>
    `rounded-md px-3 py-1.5 text-sm font-medium ${
      isActive ? "bg-indigo-600 text-white" : "text-slate-600 hover:bg-slate-100"
    }`;

  return (
    <div className="mb-4 flex gap-2">
      <Link to={`/dictionaries/${dictionaryId}`} className={tabClass(active === "words")}>
        Слова
      </Link>
      <Link to={`/dictionaries/${dictionaryId}/phrases`} className={tabClass(active === "phrases")}>
        Фразы
      </Link>
    </div>
  );
}

import { Link } from "react-router-dom";

/** Switches between a language block's content areas -- Слова (Words),
 * Фразы (Phrases) and Мини-фразы (Mini-phrases) -- plus the content audit
 * that checks whether the words those two use actually exist here. Each is
 * its own top-level tree (own categories, own editor); this is just the
 * shared nav shown at the top of all of them. Drawn as an iOS segmented
 * control (see SegmentedControl); these are links rather than in-page state
 * because each side is its own screen. */
export function LanguageSectionTabs({
  dictionaryId,
  active,
}: {
  dictionaryId: number;
  active: "words" | "phrases" | "mini-phrases" | "audit";
}) {
  const segmentClass = (isActive: boolean) =>
    `rounded-[7px] px-5 py-1 text-center text-[13px] font-medium transition-colors ${
      isActive
        ? "bg-[var(--segment-thumb)] text-slate-900 shadow-[0_3px_8px_rgb(0_0_0/0.12),0_3px_1px_rgb(0_0_0/0.04)]"
        : "text-slate-600 hover:text-slate-900"
    }`;

  return (
    <div className="mb-4 grid w-fit grid-cols-4 rounded-[9px] bg-[var(--fill)] p-0.5">
      <Link
        to={`/dictionaries/${dictionaryId}`}
        aria-current={active === "words" ? "page" : undefined}
        className={segmentClass(active === "words")}
      >
        Слова
      </Link>
      <Link
        to={`/dictionaries/${dictionaryId}/phrases`}
        aria-current={active === "phrases" ? "page" : undefined}
        className={segmentClass(active === "phrases")}
      >
        Фразы
      </Link>
      <Link
        to={`/dictionaries/${dictionaryId}/mini-phrases`}
        aria-current={active === "mini-phrases" ? "page" : undefined}
        className={segmentClass(active === "mini-phrases")}
      >
        Мини-фразы
      </Link>
      <Link
        to={`/dictionaries/${dictionaryId}/audit`}
        aria-current={active === "audit" ? "page" : undefined}
        className={segmentClass(active === "audit")}
      >
        Аудит
      </Link>
    </div>
  );
}

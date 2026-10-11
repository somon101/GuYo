/** Lower-case, ё → е, punctuation → spaces: «Ещё, раз!» ≈ «еще раз». */
export function normalizeSearch(text: string | null | undefined): string {
  return (text ?? "")
    .toLowerCase()
    .replace(/ё/g, "е")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

/** True when every word of `query` occurs in at least one of `texts`. */
export function matches(
  query: string,
  ...texts: (string | null | undefined)[]
): boolean {
  const terms = normalizeSearch(query).split(" ").filter(Boolean);
  if (terms.length === 0) return true;
  const haystack = texts.map(normalizeSearch).join(" | ");
  return terms.every((t) => haystack.includes(t));
}

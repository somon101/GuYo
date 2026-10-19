import { useEffect, useState } from "react";
import { listLanguages, type LanguageDetail } from "../api/endpoints";

let cached: Promise<LanguageDetail[]> | null = null;

/** Every language in the database (Admin Web → Языки), in its order. Loaded
 * once per page session: adding a language makes it appear everywhere a
 * translation or an explanation is edited. */
export function useLanguages(): LanguageDetail[] {
  const [languages, setLanguages] = useState<LanguageDetail[]>([]);
  useEffect(() => {
    if (!cached) cached = listLanguages().catch(() => (cached = null, []) as unknown as LanguageDetail[]);
    cached.then(setLanguages);
  }, []);
  return languages;
}

/** One field per language from the database, for texts kept by language
 * (mini-phrase hints, template explanations). Empty = no text in it yet. */
export function PerLanguageFields({
  values,
  onChange,
  label,
  multiline = false,
  exclude,
}: {
  values: Record<string, string>;
  onChange: (values: Record<string, string>) => void;
  label: (language: LanguageDetail) => string;
  multiline?: boolean;
  exclude?: string | null;
}) {
  const languages = useLanguages().filter((l) => l.code !== exclude);
  if (languages.length === 0) return <p className="text-xs text-slate-400">Загрузка языков…</p>;
  return (
    <div className="flex flex-col gap-3">
      {languages.map((l) => (
        <label key={l.code} className="block text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">
            {label(l)}
            {!(values[l.code] ?? "").trim() && <span className="ml-1 text-amber-600">— пусто</span>}
          </span>
          {multiline ? (
            <textarea
              rows={3}
              className="field w-full px-3 py-2 text-sm"
              value={values[l.code] ?? ""}
              onChange={(e) => onChange({ ...values, [l.code]: e.target.value })}
            />
          ) : (
            <input
              className="field w-full px-3 py-2 text-sm"
              value={values[l.code] ?? ""}
              onChange={(e) => onChange({ ...values, [l.code]: e.target.value })}
            />
          )}
        </label>
      ))}
    </div>
  );
}

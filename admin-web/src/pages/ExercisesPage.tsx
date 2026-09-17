import { useEffect, useState } from "react";
import { getExerciseSettings, setExerciseSettings } from "../api/endpoints";

// Declarative extra settings beyond "Количество слов", which every
// exercise built on the learned-words architecture has. Only "Собери
// слово" needs these three today; a future exercise just lists whichever
// of them (or none) it needs -- the backend already stores/serves any
// exercise_key's fields without a schema change (see ExerciseSettings).
type ExtraField =
  | { kind: "number"; key: "wrongLetterCount"; label: string; min: number; max: number }
  | { kind: "number"; key: "minWordLength"; label: string; min: number; max: number }
  | { kind: "boolean"; key: "caseSensitive"; label: string };

const EXERCISES: { key: string; label: string; description: string; extraFields?: ExtraField[] }[] = [
  {
    key: "true_or_false",
    label: "Правда или ложь",
    description: "Сколько изученных пользователем слов используется в одном запуске упражнения",
  },
  {
    key: "matching",
    label: "Сопоставление",
    description: "Сколько изученных пользователем слов используется в одном раунде упражнения",
  },
  {
    key: "build_word",
    label: "Собери слово",
    description: "Сколько изученных пользователем слов используется в одном прохождении упражнения",
    extraFields: [
      { kind: "number", key: "wrongLetterCount", label: "Неправильных букв", min: 0, max: 20 },
      { kind: "number", key: "minWordLength", label: "Минимальная длина слова", min: 1, max: 50 },
      { kind: "boolean", key: "caseSensitive", label: "Учитывать регистр" },
    ],
  },
];

export function ExercisesPage() {
  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-6 text-xl font-semibold text-slate-900">Упражнения</h1>
      <ul className="flex flex-col gap-3">
        {EXERCISES.map((ex) => (
          <li key={ex.key}>
            <ExerciseSettingRow
              exerciseKey={ex.key}
              label={ex.label}
              description={ex.description}
              extraFields={ex.extraFields ?? []}
            />
          </li>
        ))}
      </ul>
    </div>
  );
}

function ExerciseSettingRow({
  exerciseKey,
  label,
  description,
  extraFields,
}: {
  exerciseKey: string;
  label: string;
  description: string;
  extraFields: ExtraField[];
}) {
  const [wordCount, setWordCount] = useState<number | null>(null);
  const [wrongLetterCount, setWrongLetterCount] = useState<number | null>(null);
  const [minWordLength, setMinWordLength] = useState<number | null>(null);
  const [caseSensitive, setCaseSensitive] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [savedNotice, setSavedNotice] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setLoadError(null);
    getExerciseSettings(exerciseKey)
      .then((s) => {
        if (cancelled) return;
        setWordCount(s.word_count);
        setWrongLetterCount(s.wrong_letter_count);
        setMinWordLength(s.min_word_length);
        setCaseSensitive(s.case_sensitive ?? false);
      })
      .catch(() => {
        if (!cancelled) setLoadError("Не удалось загрузить настройку");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [exerciseKey]);

  async function handleSave() {
    if (wordCount == null) return;
    setIsSaving(true);
    setSaveError(null);
    setSavedNotice(false);
    try {
      const updated = await setExerciseSettings(exerciseKey, {
        wordCount,
        wrongLetterCount: extraFields.some((f) => f.key === "wrongLetterCount") ? wrongLetterCount : undefined,
        minWordLength: extraFields.some((f) => f.key === "minWordLength") ? minWordLength : undefined,
        caseSensitive: extraFields.some((f) => f.key === "caseSensitive") ? caseSensitive : undefined,
      });
      setWordCount(updated.word_count);
      setWrongLetterCount(updated.wrong_letter_count);
      setMinWordLength(updated.min_word_length);
      setCaseSensitive(updated.case_sensitive ?? false);
      setSavedNotice(true);
      setTimeout(() => setSavedNotice(false), 3000);
    } catch {
      setSaveError("Не удалось сохранить");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="rounded-lg border border-slate-200 bg-white p-5">
      <p className="text-base font-medium text-slate-900">{label}</p>
      <p className="mt-1 text-sm text-slate-500">{description}</p>

      {isLoading ? (
        <p className="mt-4 text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="mt-4 text-sm text-red-600">{loadError}</p>
      ) : (
        <div className="mt-4 flex flex-col gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <label className="text-sm font-medium text-slate-700" htmlFor={`count-${exerciseKey}`}>
              Количество слов
            </label>
            <input
              id={`count-${exerciseKey}`}
              type="number"
              min={1}
              max={100}
              className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
              value={wordCount ?? ""}
              onChange={(e) => setWordCount(e.target.value ? Number(e.target.value) : null)}
            />
          </div>

          {extraFields.map((field) => {
            if (field.kind === "boolean") {
              return (
                <label key={field.key} className="flex items-center gap-2 text-sm font-medium text-slate-700">
                  <input
                    type="checkbox"
                    checked={caseSensitive}
                    onChange={(e) => setCaseSensitive(e.target.checked)}
                    className="h-4 w-4 rounded border-slate-300"
                  />
                  {field.label}
                </label>
              );
            }
            const value = field.key === "wrongLetterCount" ? wrongLetterCount : minWordLength;
            const setValue = field.key === "wrongLetterCount" ? setWrongLetterCount : setMinWordLength;
            return (
              <div key={field.key} className="flex flex-wrap items-center gap-3">
                <label className="text-sm font-medium text-slate-700" htmlFor={`${field.key}-${exerciseKey}`}>
                  {field.label}
                </label>
                <input
                  id={`${field.key}-${exerciseKey}`}
                  type="number"
                  min={field.min}
                  max={field.max}
                  className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                  value={value ?? ""}
                  onChange={(e) => setValue(e.target.value ? Number(e.target.value) : null)}
                />
              </div>
            );
          })}

          <div className="flex items-center gap-3">
            <button
              onClick={handleSave}
              disabled={isSaving || wordCount == null || wordCount < 1}
              className="rounded-md bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
            >
              {isSaving ? "Сохранение…" : "Сохранить"}
            </button>
            {savedNotice && <span className="text-sm text-emerald-600">Сохранено</span>}
            {saveError && <span className="text-sm text-red-600">{saveError}</span>}
          </div>
        </div>
      )}
    </div>
  );
}

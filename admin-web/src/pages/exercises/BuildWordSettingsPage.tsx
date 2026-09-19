import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getExerciseSettings, setExerciseSettings } from "../../api/endpoints";

const EXERCISE_KEY = "build_word";
const DEFAULT_CORRECT_POINTS = 30;
const DEFAULT_INCORRECT_POINTS = 15;

// This page owns only "Собери слово"'s own settings -- see
// TrueOrFalseSettingsPage.tsx for why each exercise gets its own page
// instead of a shared settings form. Its extra fields (wrong letter count,
// minimum word length, case sensitivity) live here and nowhere else.
export function BuildWordSettingsPage() {
  const [wordCount, setWordCount] = useState<number | null>(null);
  const [wrongLetterCount, setWrongLetterCount] = useState<number | null>(null);
  const [minWordLength, setMinWordLength] = useState<number | null>(null);
  const [caseSensitive, setCaseSensitive] = useState(false);
  const [correctPoints, setCorrectPoints] = useState<number | null>(null);
  const [incorrectPoints, setIncorrectPoints] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [savedNotice, setSavedNotice] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setLoadError(null);
    getExerciseSettings(EXERCISE_KEY)
      .then((s) => {
        if (cancelled) return;
        setWordCount(s.word_count);
        setWrongLetterCount(s.wrong_letter_count);
        setMinWordLength(s.min_word_length);
        setCaseSensitive(s.case_sensitive ?? false);
        setCorrectPoints(s.correct_points ?? DEFAULT_CORRECT_POINTS);
        setIncorrectPoints(s.incorrect_points ?? DEFAULT_INCORRECT_POINTS);
      })
      .catch(() => {
        if (!cancelled) setLoadError("Не удалось загрузить настройки");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  async function handleSave() {
    if (wordCount == null) return;
    setIsSaving(true);
    setSaveError(null);
    setSavedNotice(false);
    try {
      const updated = await setExerciseSettings(EXERCISE_KEY, {
        wordCount,
        wrongLetterCount,
        minWordLength,
        caseSensitive,
        correctPoints,
        incorrectPoints,
      });
      setWordCount(updated.word_count);
      setWrongLetterCount(updated.wrong_letter_count);
      setMinWordLength(updated.min_word_length);
      setCaseSensitive(updated.case_sensitive ?? false);
      setCorrectPoints(updated.correct_points ?? DEFAULT_CORRECT_POINTS);
      setIncorrectPoints(updated.incorrect_points ?? DEFAULT_INCORRECT_POINTS);
      setSavedNotice(true);
      setTimeout(() => setSavedNotice(false), 3000);
    } catch {
      setSaveError("Не удалось сохранить");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl">
      <Link to="/exercises" className="text-sm font-medium text-indigo-600 hover:text-indigo-700">
        ← Упражнения
      </Link>
      <h1 className="mb-1 mt-3 text-xl font-semibold text-slate-900">Собери слово</h1>
      <p className="mb-6 text-sm text-slate-500">
        Сколько изученных пользователем слов используется в одном прохождении упражнения
      </p>

      <div className="rounded-lg border border-slate-200 bg-white p-5">
        {isLoading ? (
          <p className="text-sm text-slate-500">Загрузка…</p>
        ) : loadError ? (
          <p className="text-sm text-red-600">{loadError}</p>
        ) : (
          <div className="flex flex-col gap-4">
            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="build-word-word-count">
                Количество слов
              </label>
              <input
                id="build-word-word-count"
                type="number"
                min={1}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={wordCount ?? ""}
                onChange={(e) => setWordCount(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="build-word-wrong-letter-count">
                Неправильных букв
              </label>
              <input
                id="build-word-wrong-letter-count"
                type="number"
                min={0}
                max={20}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={wrongLetterCount ?? ""}
                onChange={(e) => setWrongLetterCount(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="build-word-min-word-length">
                Минимальная длина слова
              </label>
              <input
                id="build-word-min-word-length"
                type="number"
                min={1}
                max={50}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={minWordLength ?? ""}
                onChange={(e) => setMinWordLength(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

            <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
              <input
                type="checkbox"
                checked={caseSensitive}
                onChange={(e) => setCaseSensitive(e.target.checked)}
                className="h-4 w-4 rounded border-slate-300"
              />
              Учитывать регистр
            </label>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="build-word-correct-points">
                Баллов за правильный ответ
              </label>
              <input
                id="build-word-correct-points"
                type="number"
                min={0}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={correctPoints ?? ""}
                onChange={(e) => setCorrectPoints(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="build-word-incorrect-points">
                Баллов снимается за неправильный ответ
              </label>
              <input
                id="build-word-incorrect-points"
                type="number"
                min={0}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={incorrectPoints ?? ""}
                onChange={(e) => setIncorrectPoints(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

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
    </div>
  );
}

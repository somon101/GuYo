import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getExerciseSettings, setExerciseSettings } from "../../api/endpoints";

const EXERCISE_KEY = "speaking_word";
const DEFAULT_CORRECT_POINTS = 15;
const DEFAULT_INCORRECT_POINTS = 5;
const DEFAULT_MATCH_THRESHOLD = 70;

// "Произнеси слово" always uses every word of the lesson it's part of (same
// as "Сопоставление"/"Правда или ложь"/"Собери слово" today) -- there is no
// "how many words per run" control here on purpose, since a word_count
// field wouldn't actually change anything for this exercise inside a
// Lesson. word_count is still sent to the backend (a required column) with
// this fixed value, just never shown as a setting an admin could change
// without it doing anything.
const FIXED_WORD_COUNT = 10;

export function SpeakingWordSettingsPage() {
  const [enabled, setEnabled] = useState(true);
  const [correctPoints, setCorrectPoints] = useState<number | null>(null);
  const [incorrectPoints, setIncorrectPoints] = useState<number | null>(null);
  const [matchThreshold, setMatchThreshold] = useState<number | null>(null);
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
        setEnabled(s.enabled ?? true);
        setCorrectPoints(s.correct_points ?? DEFAULT_CORRECT_POINTS);
        setIncorrectPoints(s.incorrect_points ?? DEFAULT_INCORRECT_POINTS);
        setMatchThreshold(s.speech_match_threshold ?? DEFAULT_MATCH_THRESHOLD);
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
    setIsSaving(true);
    setSaveError(null);
    setSavedNotice(false);
    try {
      const updated = await setExerciseSettings(EXERCISE_KEY, {
        wordCount: FIXED_WORD_COUNT,
        enabled,
        correctPoints,
        incorrectPoints,
        speechMatchThreshold: matchThreshold,
      });
      setEnabled(updated.enabled ?? true);
      setCorrectPoints(updated.correct_points ?? DEFAULT_CORRECT_POINTS);
      setIncorrectPoints(updated.incorrect_points ?? DEFAULT_INCORRECT_POINTS);
      setMatchThreshold(updated.speech_match_threshold ?? DEFAULT_MATCH_THRESHOLD);
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
      <h1 className="mb-1 mt-3 text-xl font-semibold text-slate-900">Произнеси слово 🎙️</h1>
      <p className="mb-6 text-sm text-slate-500">
        Пользователь произносит слово вслух; распознанный текст сравнивается с целевым словом на устройстве
      </p>

      <div className="rounded-lg border border-slate-200 bg-white p-5">
        {isLoading ? (
          <p className="text-sm text-slate-500">Загрузка…</p>
        ) : loadError ? (
          <p className="text-sm text-red-600">{loadError}</p>
        ) : (
          <div className="flex flex-col gap-4">
            <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
              <input
                type="checkbox"
                checked={enabled}
                onChange={(e) => setEnabled(e.target.checked)}
                className="h-4 w-4 rounded border-slate-300"
              />
              Упражнение включено
            </label>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="speaking-word-correct-points">
                Баллов за правильный ответ
              </label>
              <input
                id="speaking-word-correct-points"
                type="number"
                min={0}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={correctPoints ?? ""}
                onChange={(e) => setCorrectPoints(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="speaking-word-incorrect-points">
                Баллов снимается за неправильный ответ
              </label>
              <input
                id="speaking-word-incorrect-points"
                type="number"
                min={0}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={incorrectPoints ?? ""}
                onChange={(e) => setIncorrectPoints(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="speaking-word-match-threshold">
                Порог совпадения ответа (0–100)
              </label>
              <input
                id="speaking-word-match-threshold"
                type="number"
                min={0}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={matchThreshold ?? ""}
                onChange={(e) => setMatchThreshold(e.target.value ? Number(e.target.value) : null)}
              />
            </div>
            <p className="-mt-2 text-xs text-slate-400">
              Минимальное текстовое сходство распознанной речи с целевым словом, при котором ответ засчитывается
              правильным. Меньше — снисходительнее к неточному распознаванию, больше — строже.
            </p>

            <div className="flex items-center gap-3">
              <button
                onClick={handleSave}
                disabled={isSaving}
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

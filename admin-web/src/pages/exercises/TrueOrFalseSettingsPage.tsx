import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getExerciseSettings, setExerciseSettings } from "../../api/endpoints";

const EXERCISE_KEY = "true_or_false";

// This page owns only "Правда или ложь"'s own settings. It deliberately
// does not share a form/component with the other exercise settings pages --
// each exercise's settings evolve independently, so a future field added
// here should never require touching Matching's or Build-Word's page.
export function TrueOrFalseSettingsPage() {
  const [wordCount, setWordCount] = useState<number | null>(null);
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
      const updated = await setExerciseSettings(EXERCISE_KEY, { wordCount });
      setWordCount(updated.word_count);
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
      <h1 className="mb-1 mt-3 text-xl font-semibold text-slate-900">Правда или ложь</h1>
      <p className="mb-6 text-sm text-slate-500">
        Сколько изученных пользователем слов используется в одном запуске упражнения
      </p>

      <div className="rounded-lg border border-slate-200 bg-white p-5">
        {isLoading ? (
          <p className="text-sm text-slate-500">Загрузка…</p>
        ) : loadError ? (
          <p className="text-sm text-red-600">{loadError}</p>
        ) : (
          <div className="flex flex-col gap-4">
            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="true-or-false-word-count">
                Количество слов
              </label>
              <input
                id="true-or-false-word-count"
                type="number"
                min={1}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={wordCount ?? ""}
                onChange={(e) => setWordCount(e.target.value ? Number(e.target.value) : null)}
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

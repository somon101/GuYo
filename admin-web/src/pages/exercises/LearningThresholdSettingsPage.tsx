import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getLearningSettings, setLearningSettings } from "../../api/endpoints";

// Global setting (not per-exercise): the score a word's WordProgress needs
// to reach before it counts as learned across the whole "Уроки" system --
// see LearningSettings in types/index.ts.
const DEFAULT_THRESHOLD = 60;

export function LearningThresholdSettingsPage() {
  const [thresholdScore, setThresholdScore] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [savedNotice, setSavedNotice] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setLoadError(null);
    getLearningSettings()
      .then((s) => {
        if (cancelled) return;
        setThresholdScore(s.threshold_score ?? DEFAULT_THRESHOLD);
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
    if (thresholdScore == null) return;
    setIsSaving(true);
    setSaveError(null);
    setSavedNotice(false);
    try {
      const updated = await setLearningSettings(thresholdScore);
      setThresholdScore(updated.threshold_score ?? DEFAULT_THRESHOLD);
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
      <h1 className="mb-1 mt-3 text-xl font-semibold text-slate-900">Проходной порог изучения слова</h1>
      <p className="mb-6 text-sm text-slate-500">
        Минимальный счёт слова (0–100), при достижении которого оно считается изученным и попадает в «Мои слова».
        Пока счёт слова ниже порога, оно остаётся в текущем уроке для повторения.
      </p>

      <div className="rounded-lg border border-slate-200 bg-white p-5">
        {isLoading ? (
          <p className="text-sm text-slate-500">Загрузка…</p>
        ) : loadError ? (
          <p className="text-sm text-red-600">{loadError}</p>
        ) : (
          <div className="flex flex-col gap-4">
            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="learning-threshold-score">
                Порог (0–100)
              </label>
              <input
                id="learning-threshold-score"
                type="number"
                min={0}
                max={100}
                className="w-24 rounded-md border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={thresholdScore ?? ""}
                onChange={(e) => setThresholdScore(e.target.value ? Number(e.target.value) : null)}
              />
            </div>

            <div className="flex items-center gap-3">
              <button
                onClick={handleSave}
                disabled={isSaving || thresholdScore == null || thresholdScore < 0 || thresholdScore > 100}
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

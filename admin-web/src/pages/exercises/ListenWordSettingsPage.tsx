import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getExerciseSettings, setExerciseSettings } from "../../api/endpoints";

const EXERCISE_KEY = "listen_word";
const DEFAULT_OPTION_COUNT = 4;

// Same reasoning as SpeakingWordSettingsPage: "Услышь слово" always plays
// through every (audio-having) word of the lesson it's part of, so there's
// no "how many words per run" setting here -- only option_count (how many
// buttons ONE task shows) genuinely changes behavior. word_count is still
// sent with this fixed value since the backend column is required.
const FIXED_WORD_COUNT = 10;

export function ListenWordSettingsPage() {
  const [enabled, setEnabled] = useState(true);
  const [optionCount, setOptionCount] = useState<number | null>(null);
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
        setOptionCount(s.option_count ?? DEFAULT_OPTION_COUNT);
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
        optionCount,
      });
      setEnabled(updated.enabled ?? true);
      setOptionCount(updated.option_count ?? DEFAULT_OPTION_COUNT);
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
      <h1 className="mb-1 mt-3 text-[26px] font-bold tracking-tight text-slate-900">Услышь слово 🔊</h1>
      <p className="mb-6 text-sm text-slate-500">
        Проигрывается озвучка слова, пользователь выбирает его среди вариантов
      </p>

      <div className="card p-5">
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
                className="switch"
              />
              Упражнение включено
            </label>

            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium text-slate-700" htmlFor="listen-word-option-count">
                Количество вариантов ответа
              </label>
              <input
                id="listen-word-option-count"
                type="number"
                min={2}
                max={10}
                className="w-24 field px-3 py-1.5 text-sm"
                value={optionCount ?? ""}
                onChange={(e) => setOptionCount(e.target.value ? Number(e.target.value) : null)}
              />
            </div>



            <div className="flex items-center gap-3">
              <button
                onClick={handleSave}
                disabled={isSaving}
                className="rounded-full bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
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

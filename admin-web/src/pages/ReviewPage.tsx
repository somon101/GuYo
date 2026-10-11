import { useEffect, useState } from "react";
import { getRatingSettings, updateRatingSettings } from "../api/endpoints";
import type { RatingSettings } from "../types";

/** «Повтори слово»: whether a right answer in the app's «Повторить
 * сегодня» earns rating points, and how many. Stored on the same rating
 * settings as every other points rule. */
export function ReviewPage() {
  const [settings, setSettings] = useState<RatingSettings | null>(null);
  const [enabled, setEnabled] = useState(false);
  const [points, setPoints] = useState(5);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    getRatingSettings()
      .then((s) => {
        setSettings(s);
        setEnabled(s.review_points_enabled);
        setPoints(s.review_points_per_correct);
      })
      .catch(() => setError("Не удалось загрузить настройки"));
  }, []);

  async function handleSave() {
    if (!settings) return;
    setError(null);
    setSaved(false);
    setIsSaving(true);
    try {
      const next = await updateRatingSettings({
        ...settings,
        review_points_enabled: enabled,
        review_points_per_correct: points,
      });
      setSettings(next);
      setSaved(true);
    } catch {
      setError("Не удалось сохранить");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">Повтори слово</h1>
      <p className="mb-6 max-w-2xl text-sm text-slate-500">
        В приложении на главной появляется карточка «Повторить сегодня» — выученные слова, которые
        пользователь начинает забывать. Здесь можно давать за них очки для ранга.
      </p>

      {!settings ? (
        error ? <p className="text-sm text-red-600">{error}</p> : <p className="text-sm text-slate-500">Загрузка…</p>
      ) : (
        <div className="card flex flex-col gap-5 p-5">
          <label className="flex items-start gap-3">
            <input
              type="checkbox"
              className="switch mt-0.5"
              checked={enabled}
              onChange={(e) => setEnabled(e.target.checked)}
            />
            <span>
              <span className="block text-sm font-semibold text-slate-900">Давать очки за повторение</span>
              <span className="mt-0.5 block text-sm text-slate-500">
                За каждый правильный ответ на забываемое слово. Одно слово даёт очки один раз за раз,
                когда начинает забываться: после правильного ответа оно снова «закреплено».
              </span>
            </span>
          </label>

          <div className={enabled ? "" : "pointer-events-none opacity-50"}>
            <label className="mb-1.5 block text-sm font-medium text-slate-700">Очков за правильный ответ</label>
            <input
              type="number"
              min={0}
              max={1000}
              className="field w-32 px-3 py-2 text-sm"
              value={points}
              onChange={(e) => setPoints(Math.max(0, Number(e.target.value)))}
            />
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={handleSave}
              disabled={isSaving}
              className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
            >
              {isSaving ? "Сохранение…" : "Сохранить"}
            </button>
            {saved && <span className="text-sm text-emerald-600">Сохранено</span>}
            {error && <span className="text-sm text-red-600">{error}</span>}
          </div>
        </div>
      )}
    </div>
  );
}

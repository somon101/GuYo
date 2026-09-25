import axios from "axios";
import { useEffect, useRef, useState, type DragEvent, type FormEvent } from "react";
import { Link } from "react-router-dom";
import {
  createWordLevel,
  deleteWordLevel,
  listWordLevels,
  reorderWordLevels,
  updateWordLevel,
  type WordLevelInput,
} from "../../api/endpoints";
import type { WordLevel } from "../../types";

// Replaces the old single "Проходной порог изучения слова" number with an
// admin-defined ladder (see backend/app/word_levels/) -- the TOP enabled
// level's own min_points becomes the new "word is learned" threshold
// everywhere else in the app (Уроки completion, Мои слова, achievements,
// rating). Nothing here is hardcoded in Flutter or backend logic.
export function WordLevelsSettingsPage() {
  const [levels, setLevels] = useState<WordLevel[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [editing, setEditing] = useState<WordLevel | "new" | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [isReordering, setIsReordering] = useState(false);
  const dragId = useRef<number | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      setLevels(await listWordLevels());
    } catch {
      setLoadError("Не удалось загрузить уровни");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function handleDelete(level: WordLevel) {
    if (!confirm(`Удалить уровень «${level.name}»? Это действие нельзя отменить.`)) return;
    setActionError(null);
    setDeletingId(level.id);
    try {
      await deleteWordLevel(level.id);
      setLevels((prev) => prev.filter((x) => x.id !== level.id));
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setActionError(detail ?? "Не удалось удалить уровень");
    } finally {
      setDeletingId(null);
    }
  }

  function handleDragStart(id: number) {
    dragId.current = id;
  }

  function handleDragOver(e: DragEvent<HTMLLIElement>, overId: number) {
    e.preventDefault();
    if (dragId.current === null || dragId.current === overId) return;
    const from = levels.findIndex((l) => l.id === dragId.current);
    const to = levels.findIndex((l) => l.id === overId);
    if (from === -1 || to === -1) return;
    const next = [...levels];
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    setLevels(next);
  }

  async function handleDragEnd() {
    dragId.current = null;
    setIsReordering(true);
    setActionError(null);
    try {
      setLevels(await reorderWordLevels(levels.map((l) => l.id)));
    } catch {
      setActionError("Не удалось сохранить новый порядок");
    } finally {
      setIsReordering(false);
    }
  }

  const topLevel = [...levels].filter((l) => l.enabled).sort((a, b) => b.min_points - a.min_points)[0];

  return (
    <div className="mx-auto max-w-2xl">
      <Link to="/exercises" className="text-sm font-medium text-indigo-600 hover:text-indigo-700">
        ← Упражнения
      </Link>
      <h1 className="mb-1 mt-3 text-xl font-semibold text-slate-900">Уровни слов</h1>
      <p className="mb-6 text-sm text-slate-500">
        Диапазоны очков закрепления не должны пересекаться. Самый верхний включённый уровень считается «изученным» --
        именно его нижняя граница используется как проходной порог во всём приложении.
        {topLevel && (
          <>
            {" "}
            Сейчас это «<span className="font-medium text-slate-700">{topLevel.name}</span>» (от {topLevel.min_points}).
          </>
        )}
      </p>

      <button
        onClick={() => setEditing("new")}
        className="mb-4 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
      >
        + Добавить уровень
      </button>

      {editing !== null && (
        <WordLevelForm
          level={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            if (editing === "new") setLevels((prev) => [...prev, saved]);
            else setLevels((prev) => prev.map((l) => (l.id === saved.id ? saved : l)));
          }}
          onCancel={() => setEditing(null)}
        />
      )}

      {actionError && <p className="mb-3 text-sm text-red-600">{actionError}</p>}

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : levels.length === 0 ? (
        <p className="text-sm text-slate-500">
          Уровней пока нет -- используется старый единый порог ({"≥"} 60), пока вы не настроите лестницу.
        </p>
      ) : (
        <ul className={`flex flex-col gap-2 ${isReordering ? "opacity-60" : ""}`}>
          {levels.map((level) => (
            <li
              key={level.id}
              draggable
              onDragStart={() => handleDragStart(level.id)}
              onDragOver={(e) => handleDragOver(e, level.id)}
              onDragEnd={handleDragEnd}
              className={`flex cursor-grab items-center gap-3 rounded-lg border border-slate-200 bg-white p-3 active:cursor-grabbing ${level.enabled ? "" : "opacity-50"}`}
            >
              <div className="min-w-0 flex-1">
                <p className="font-medium text-slate-900">{level.name}</p>
                <p className="text-xs text-slate-500">
                  {level.min_points} – {level.max_points ?? "∞"}
                  {" · вклад в Priority: "}
                  {level.priority_weight}
                  {!level.enabled && " · отключён"}
                </p>
              </div>
              <div className="flex shrink-0 gap-3">
                <button onClick={() => setEditing(level)} className="text-sm font-medium text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button
                  onClick={() => handleDelete(level)}
                  disabled={deletingId === level.id}
                  className="text-sm text-slate-400 hover:text-red-600 disabled:opacity-60"
                >
                  {deletingId === level.id ? "…" : "Удалить"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function WordLevelForm({
  level,
  onSaved,
  onCancel,
}: {
  level: WordLevel | null;
  onSaved: (l: WordLevel) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState(level?.name ?? "");
  const [minPoints, setMinPoints] = useState(level?.min_points ?? 0);
  const [hasMax, setHasMax] = useState(level ? level.max_points !== null : false);
  const [maxPoints, setMaxPoints] = useState(level?.max_points ?? 100);
  const [enabled, setEnabled] = useState(level?.enabled ?? true);
  const [priorityWeight, setPriorityWeight] = useState(level?.priority_weight ?? 0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!name.trim()) {
      setError("Заполните название");
      return;
    }
    if (hasMax && maxPoints < minPoints) {
      setError("Верхняя граница меньше нижней");
      return;
    }
    const input: WordLevelInput = {
      name: name.trim(),
      minPoints,
      maxPoints: hasMax ? maxPoints : null,
      enabled,
      order: level?.order ?? 0,
      priorityWeight,
    };
    setIsSubmitting(true);
    try {
      const saved = level ? await updateWordLevel(level.id, input) : await createWordLevel(input);
      onSaved(saved);
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setError(detail ?? "Не удалось сохранить уровень");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-4 flex flex-col gap-4 rounded-lg border border-slate-200 bg-slate-50 p-4">
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Название</label>
        <input
          className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Закреплено"
          autoFocus
        />
      </div>

      <div className="flex flex-wrap gap-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Мин. очков</label>
          <input
            type="number"
            min={0}
            className="w-28 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={minPoints}
            onChange={(e) => setMinPoints(Number(e.target.value))}
          />
        </div>
        <div>
          <label className="mb-1 flex items-center gap-2 text-sm font-medium text-slate-700">
            <input type="checkbox" checked={hasMax} onChange={(e) => setHasMax(e.target.checked)} className="h-4 w-4 rounded border-slate-300" />
            Макс. очков
          </label>
          <input
            type="number"
            min={0}
            disabled={!hasMax}
            className="w-28 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 disabled:bg-slate-100"
            value={maxPoints}
            onChange={(e) => setMaxPoints(Number(e.target.value))}
            placeholder="без границы"
          />
        </div>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Вклад в Priority</label>
        <input
          type="number"
          step="any"
          className="w-28 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={priorityWeight}
          onChange={(e) => setPriorityWeight(Number(e.target.value))}
        />
        <p className="mt-1 text-xs text-slate-400">Насколько слово на этом уровне повышает свой Priority Score (см. страницу «Приоритет»).</p>
      </div>

      <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
        <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} className="h-4 w-4 rounded border-slate-300" />
        Включён
      </label>

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : level ? "Сохранить" : "Создать"}
        </button>
        <button type="button" onClick={onCancel} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50">
          Отмена
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </form>
  );
}

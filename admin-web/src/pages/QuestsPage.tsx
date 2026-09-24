import axios from "axios";
import { useEffect, useRef, useState, type DragEvent, type FormEvent } from "react";
import {
  createQuest,
  deleteQuest,
  listQuestExerciseTypes,
  listQuests,
  listWordLevels,
  reorderQuests,
  updateQuest,
  type QuestInput,
} from "../api/endpoints";
import type { Quest, WordLevel } from "../types";

// Same 5 labels ExercisesPage.tsx already uses -- Quests may only target
// these word-scoped exercise types (never "Собери фразу"/"Собери фразу на
// слух", which aren't tied to a specific word_id on the backend).
const EXERCISE_LABELS: Record<string, string> = {
  true_or_false: "Правда или ложь",
  matching: "Сопоставление",
  build_word: "Собери слово",
  speaking_word: "Произнеси слово 🎙️",
  listen_word: "Услышь слово 🔊",
};

export function QuestsPage() {
  const [quests, setQuests] = useState<Quest[]>([]);
  const [wordLevels, setWordLevels] = useState<WordLevel[]>([]);
  const [exerciseTypes, setExerciseTypes] = useState<string[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Quest | "new" | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [isReordering, setIsReordering] = useState(false);
  const dragId = useRef<number | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [q, l, t] = await Promise.all([listQuests(), listWordLevels(), listQuestExerciseTypes()]);
      setQuests(q);
      setWordLevels(l);
      setExerciseTypes(t);
    } catch {
      setLoadError("Не удалось загрузить квесты");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function handleDelete(quest: Quest) {
    if (!confirm(`Удалить квест «${quest.name}»? Это действие нельзя отменить.`)) return;
    setActionError(null);
    setDeletingId(quest.id);
    try {
      await deleteQuest(quest.id);
      setQuests((prev) => prev.filter((x) => x.id !== quest.id));
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setActionError(detail ?? "Не удалось удалить квест");
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
    const from = quests.findIndex((q) => q.id === dragId.current);
    const to = quests.findIndex((q) => q.id === overId);
    if (from === -1 || to === -1) return;
    const next = [...quests];
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    setQuests(next);
  }

  async function handleDragEnd() {
    dragId.current = null;
    setIsReordering(true);
    setActionError(null);
    try {
      setQuests(await reorderQuests(quests.map((q) => q.id)));
    } catch {
      setActionError("Не удалось сохранить новый порядок");
    } finally {
      setIsReordering(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-slate-900">Квесты</h1>
          <p className="mt-0.5 text-sm text-slate-500">
            Слово может выполнить только ОДИН квест в день -- независимо от того, какой именно.
          </p>
        </div>
        <button
          onClick={() => setEditing("new")}
          disabled={wordLevels.length === 0}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          + Добавить квест
        </button>
      </div>

      {wordLevels.length === 0 && !isLoading && (
        <p className="mb-4 text-sm text-amber-700">
          Сначала настройте хотя бы один уровень слов в разделе «Упражнения → Уровни слов».
        </p>
      )}

      {editing !== null && (
        <QuestForm
          quest={editing === "new" ? null : editing}
          wordLevels={wordLevels}
          exerciseTypes={exerciseTypes}
          onSaved={(saved) => {
            setEditing(null);
            if (editing === "new") setQuests((prev) => [...prev, saved]);
            else setQuests((prev) => prev.map((q) => (q.id === saved.id ? saved : q)));
          }}
          onCancel={() => setEditing(null)}
        />
      )}

      {actionError && <p className="mb-3 text-sm text-red-600">{actionError}</p>}

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : quests.length === 0 ? (
        <p className="text-sm text-slate-500">Квестов пока нет</p>
      ) : (
        <ul className={`flex flex-col gap-2 ${isReordering ? "opacity-60" : ""}`}>
          {quests.map((quest) => (
            <li
              key={quest.id}
              draggable
              onDragStart={() => handleDragStart(quest.id)}
              onDragOver={(e) => handleDragOver(e, quest.id)}
              onDragEnd={handleDragEnd}
              className={`flex cursor-grab items-center gap-3 rounded-lg border border-slate-200 bg-white p-4 active:cursor-grabbing ${quest.enabled ? "" : "opacity-50"}`}
            >
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium text-slate-900">{quest.name}</p>
                  {!quest.enabled && (
                    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700">отключён</span>
                  )}
                </div>
                <p className="mt-0.5 text-xs text-slate-500">
                  Уровень «{quest.word_level_name}» · {EXERCISE_LABELS[quest.exercise_key] ?? quest.exercise_key} · награда +
                  {quest.reward_points} · {quest.daily_target} раз в день
                </p>
              </div>
              <div className="flex shrink-0 gap-3">
                <button onClick={() => setEditing(quest)} className="text-sm font-medium text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button
                  onClick={() => handleDelete(quest)}
                  disabled={deletingId === quest.id}
                  className="text-sm text-slate-400 hover:text-red-600 disabled:opacity-60"
                >
                  {deletingId === quest.id ? "…" : "Удалить"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function QuestForm({
  quest,
  wordLevels,
  exerciseTypes,
  onSaved,
  onCancel,
}: {
  quest: Quest | null;
  wordLevels: WordLevel[];
  exerciseTypes: string[];
  onSaved: (q: Quest) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState(quest?.name ?? "");
  const [wordLevelId, setWordLevelId] = useState(quest?.word_level_id ?? wordLevels[0]?.id ?? 0);
  const [exerciseKey, setExerciseKey] = useState(quest?.exercise_key ?? exerciseTypes[0] ?? "");
  const [rewardPoints, setRewardPoints] = useState(quest?.reward_points ?? 10);
  const [dailyTarget, setDailyTarget] = useState(quest?.daily_target ?? 1);
  const [enabled, setEnabled] = useState(quest?.enabled ?? true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!name.trim() || !wordLevelId || !exerciseKey) {
      setError("Заполните все поля");
      return;
    }
    if (dailyTarget < 1) {
      setError("Цель за день не может быть меньше 1");
      return;
    }
    const input: QuestInput = {
      name: name.trim(),
      wordLevelId,
      exerciseKey,
      rewardPoints,
      dailyTarget,
      enabled,
      order: quest?.order ?? 0,
    };
    setIsSubmitting(true);
    try {
      const saved = quest ? await updateQuest(quest.id, input) : await createQuest(input);
      onSaved(saved);
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setError(detail ?? "Не удалось сохранить квест");
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
          placeholder="Квест уровня 3"
          autoFocus
        />
      </div>

      <div className="flex flex-wrap gap-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Уровень слова</label>
          <select
            className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={wordLevelId}
            onChange={(e) => setWordLevelId(Number(e.target.value))}
          >
            {wordLevels.map((l) => (
              <option key={l.id} value={l.id}>
                {l.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Упражнение</label>
          <select
            className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={exerciseKey}
            onChange={(e) => setExerciseKey(e.target.value)}
          >
            {exerciseTypes.map((key) => (
              <option key={key} value={key}>
                {EXERCISE_LABELS[key] ?? key}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Награда (рейтинговые очки)</label>
          <input
            type="number"
            min={0}
            className="w-32 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={rewardPoints}
            onChange={(e) => setRewardPoints(Number(e.target.value))}
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Цель за день</label>
          <input
            type="number"
            min={1}
            className="w-32 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={dailyTarget}
            onChange={(e) => setDailyTarget(Number(e.target.value))}
          />
          <p className="mt-1 max-w-48 text-xs text-slate-400">
            Сколько раз за день нужно выполнить квест, чтобы он считался пройденным. Награда начисляется за каждое
            выполнение независимо от цели.
          </p>
        </div>
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
          {isSubmitting ? "Сохранение…" : quest ? "Сохранить" : "Создать"}
        </button>
        <button type="button" onClick={onCancel} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50">
          Отмена
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </form>
  );
}

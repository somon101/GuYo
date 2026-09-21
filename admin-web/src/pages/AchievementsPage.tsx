import axios from "axios";
import { useEffect, useState, type FormEvent } from "react";
import {
  createAchievement,
  deleteAchievement,
  listAchievementIcons,
  listAchievements,
  listConditionTypes,
  updateAchievement,
  type AchievementInput,
} from "../api/endpoints";
import type { Achievement, AchievementIcon, ConditionType } from "../types";

export function AchievementsPage() {
  const [achievements, setAchievements] = useState<Achievement[]>([]);
  const [icons, setIcons] = useState<AchievementIcon[]>([]);
  const [conditionTypes, setConditionTypes] = useState<ConditionType[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Achievement | "new" | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [a, i, c] = await Promise.all([listAchievements(), listAchievementIcons(), listConditionTypes()]);
      setAchievements(a);
      setIcons(i);
      setConditionTypes(c);
    } catch {
      setLoadError("Не удалось загрузить достижения");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function handleDelete(a: Achievement) {
    if (!confirm(`Удалить достижение «${a.title}»? Это действие нельзя отменить.`)) return;
    setActionError(null);
    setDeletingId(a.id);
    try {
      await deleteAchievement(a.id);
      setAchievements((prev) => prev.filter((x) => x.id !== a.id));
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setActionError(detail ?? "Не удалось удалить достижение");
    } finally {
      setDeletingId(null);
    }
  }

  const iconEmoji = (id: string) => icons.find((i) => i.id === id)?.emoji ?? "❔";
  const conditionLabel = (id: string) => conditionTypes.find((c) => c.id === id)?.label ?? id;

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-slate-900">Достижения</h1>
        <button
          onClick={() => setEditing("new")}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Добавить достижение
        </button>
      </div>

      {editing !== null && (
        <AchievementForm
          achievement={editing === "new" ? null : editing}
          icons={icons}
          conditionTypes={conditionTypes}
          onSaved={() => {
            setEditing(null);
            reload();
          }}
          onCancel={() => setEditing(null)}
        />
      )}

      {actionError && <p className="mb-4 text-sm text-red-600">{actionError}</p>}

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : achievements.length === 0 ? (
        <p className="text-sm text-slate-500">Достижений пока нет</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {achievements.map((a) => (
            <li
              key={a.id}
              className={`rounded-lg border bg-white p-4 ${a.enabled ? "border-slate-200" : "border-slate-200 opacity-60"}`}
            >
              <div className="flex items-start gap-3">
                <span className="text-2xl leading-none">{iconEmoji(a.icon)}</span>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-medium text-slate-900">{a.title}</p>
                    <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-500">
                      порядок: {a.order}
                    </span>
                    {!a.enabled && (
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700">
                        отключено
                      </span>
                    )}
                  </div>
                  <p className="mt-0.5 text-sm text-slate-500">{a.description}</p>
                  <p className="mt-1 text-xs text-slate-400">
                    {conditionLabel(a.condition_type)} ≥ {a.condition_value}
                  </p>
                </div>
                <div className="flex shrink-0 gap-2">
                  <button
                    onClick={() => setEditing(a)}
                    className="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
                  >
                    Изменить
                  </button>
                  <button
                    onClick={() => handleDelete(a)}
                    disabled={deletingId === a.id}
                    className="text-sm text-slate-400 hover:text-red-600 disabled:opacity-60"
                  >
                    {deletingId === a.id ? "…" : "Удалить"}
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function AchievementForm({
  achievement,
  icons,
  conditionTypes,
  onSaved,
  onCancel,
}: {
  achievement: Achievement | null;
  icons: AchievementIcon[];
  conditionTypes: ConditionType[];
  onSaved: () => void;
  onCancel: () => void;
}) {
  const [title, setTitle] = useState(achievement?.title ?? "");
  const [description, setDescription] = useState(achievement?.description ?? "");
  const [icon, setIcon] = useState(achievement?.icon ?? icons[0]?.id ?? "");
  const [conditionType, setConditionType] = useState(achievement?.condition_type ?? conditionTypes[0]?.id ?? "");
  const [conditionValue, setConditionValue] = useState(achievement?.condition_value ?? 1);
  const [enabled, setEnabled] = useState(achievement?.enabled ?? true);
  const [order, setOrder] = useState(achievement?.order ?? 0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!title.trim() || !description.trim() || !icon || !conditionType) {
      setError("Заполните все поля");
      return;
    }
    const input: AchievementInput = {
      title: title.trim(),
      description: description.trim(),
      icon,
      conditionType,
      conditionValue,
      enabled,
      order,
    };
    setIsSubmitting(true);
    try {
      if (achievement) {
        await updateAchievement(achievement.id, input);
      } else {
        await createAchievement(input);
      }
      onSaved();
    } catch {
      setError("Не удалось сохранить достижение");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-6 flex flex-col gap-4 rounded-lg border border-slate-200 bg-white p-5">
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Название</label>
        <input
          className="w-full max-w-sm rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Первый шаг"
          autoFocus
        />
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Описание</label>
        <input
          className="w-full max-w-sm rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Ты открыл свою первую фразу"
        />
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Иконка</label>
        <div className="flex flex-wrap gap-2">
          {icons.map((i) => (
            <button
              key={i.id}
              type="button"
              onClick={() => setIcon(i.id)}
              className={`flex h-11 w-11 items-center justify-center rounded-lg border text-xl ${
                icon === i.id ? "border-indigo-500 bg-indigo-50" : "border-slate-200 hover:bg-slate-50"
              }`}
              title={i.id}
            >
              {i.emoji}
            </button>
          ))}
        </div>
      </div>

      <div className="flex flex-wrap gap-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Условие</label>
          <select
            className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={conditionType}
            onChange={(e) => setConditionType(e.target.value)}
          >
            {conditionTypes.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Порог</label>
          <input
            type="number"
            min={1}
            className="w-24 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={conditionValue}
            onChange={(e) => setConditionValue(Number(e.target.value))}
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Порядок отображения</label>
          <input
            type="number"
            className="w-24 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={order}
            onChange={(e) => setOrder(Number(e.target.value))}
          />
        </div>
      </div>

      <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
        <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} className="h-4 w-4 rounded border-slate-300" />
        Включено
      </label>

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : achievement ? "Сохранить" : "Создать"}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
        >
          Отмена
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </form>
  );
}

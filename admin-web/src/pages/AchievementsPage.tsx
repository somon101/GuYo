import axios from "axios";
import { useEffect, useRef, useState, type ChangeEvent, type DragEvent, type FormEvent } from "react";
import { API_URL } from "../api/client";
import {
  createAchievement,
  deleteAchievement,
  listAchievements,
  listConditionTypes,
  reorderAchievements,
  updateAchievement,
  type AchievementInput,
} from "../api/endpoints";
import type { Achievement, AchievementVisibility, ConditionType } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

export function AchievementsPage() {
  const [achievements, setAchievements] = useState<Achievement[]>([]);
  const [conditionTypes, setConditionTypes] = useState<ConditionType[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Achievement | "new" | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [isReordering, setIsReordering] = useState(false);
  const dragId = useRef<number | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [a, c] = await Promise.all([listAchievements(), listConditionTypes()]);
      setAchievements(a);
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

  const conditionLabel = (id: string) => conditionTypes.find((c) => c.id === id)?.label ?? id;

  // Native HTML5 drag-and-drop -- reorders the local list immediately for a
  // responsive feel, then persists the FULL new order to the backend on
  // drop (never only client-side state).
  function handleDragStart(id: number) {
    dragId.current = id;
  }

  function handleDragOver(e: DragEvent<HTMLLIElement>, overId: number) {
    e.preventDefault();
    if (dragId.current === null || dragId.current === overId) return;
    setAchievements((prev) => {
      const from = prev.findIndex((a) => a.id === dragId.current);
      const to = prev.findIndex((a) => a.id === overId);
      if (from === -1 || to === -1) return prev;
      const next = [...prev];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved);
      return next;
    });
  }

  async function handleDragEnd() {
    dragId.current = null;
    setIsReordering(true);
    setActionError(null);
    try {
      const saved = await reorderAchievements(achievements.map((a) => a.id));
      setAchievements(saved);
    } catch {
      setActionError("Не удалось сохранить новый порядок");
      reload();
    } finally {
      setIsReordering(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-slate-900">Достижения</h1>
          <p className="mt-0.5 text-sm text-slate-500">Перетаскивайте карточки, чтобы изменить порядок цепочки</p>
        </div>
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
        <ul className={`relative flex flex-col ${isReordering ? "opacity-60" : ""}`}>
          {achievements.map((a, index) => (
            <li
              key={a.id}
              draggable
              onDragStart={() => handleDragStart(a.id)}
              onDragOver={(e) => handleDragOver(e, a.id)}
              onDragEnd={handleDragEnd}
              className="relative flex cursor-grab gap-4 pb-3 active:cursor-grabbing"
            >
              {/* the connecting line running down through every node but the last */}
              {index < achievements.length - 1 && (
                <span
                  className="absolute left-[27px] top-14 h-full w-0.5"
                  style={{ backgroundColor: a.color, opacity: 0.25 }}
                />
              )}

              <ChainIcon achievement={a} />

              <div
                className={`min-w-0 flex-1 rounded-lg border bg-white p-3 ${a.enabled ? "border-slate-200" : "border-slate-200 opacity-50"}`}
              >
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium text-slate-900">{a.title}</p>
                  {a.visibility === "hidden" && (
                    <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-500">
                      {a.show_before_unlock ? "скрытое (виден силуэт)" : "полностью скрытое"}
                    </span>
                  )}
                  {!a.enabled && (
                    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700">
                      отключено
                    </span>
                  )}
                </div>
                <p className="mt-0.5 text-sm text-slate-500">{a.description}</p>
                <p className="mt-1 text-xs font-medium" style={{ color: a.color }}>
                  {conditionLabel(a.condition_type)} ≥ {a.condition_value}
                </p>

                <div className="mt-2 flex gap-3">
                  <button
                    onClick={() => setEditing(a)}
                    className="text-sm font-medium text-indigo-600 hover:text-indigo-700"
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

function ChainIcon({ achievement }: { achievement: Achievement }) {
  return (
    <div
      className="relative z-10 flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-full border-2 bg-white"
      style={{ borderColor: achievement.color }}
    >
      {achievement.icon_url ? (
        <img src={mediaUrl(achievement.icon_url)!} alt="" className="h-full w-full object-cover" />
      ) : (
        <span className="text-lg" style={{ color: achievement.color }}>
          ?
        </span>
      )}
    </div>
  );
}

function AchievementForm({
  achievement,
  conditionTypes,
  onSaved,
  onCancel,
}: {
  achievement: Achievement | null;
  conditionTypes: ConditionType[];
  onSaved: () => void;
  onCancel: () => void;
}) {
  const [title, setTitle] = useState(achievement?.title ?? "");
  const [description, setDescription] = useState(achievement?.description ?? "");
  const [conditionType, setConditionType] = useState(achievement?.condition_type ?? conditionTypes[0]?.id ?? "");
  const [conditionValue, setConditionValue] = useState(achievement?.condition_value ?? 1);
  const [color, setColor] = useState(achievement?.color ?? "#6366F1");
  const [visibility, setVisibility] = useState<AchievementVisibility>(achievement?.visibility ?? "visible");
  const [showBeforeUnlock, setShowBeforeUnlock] = useState(achievement?.show_before_unlock ?? true);
  const [enabled, setEnabled] = useState(achievement?.enabled ?? true);
  const [icon, setIcon] = useState<File | null>(null);
  const [removeIcon, setRemoveIcon] = useState(false);
  const [iconPreview, setIconPreview] = useState<string | null>(
    achievement?.icon_url ? mediaUrl(achievement.icon_url) : null,
  );
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function handleIconChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    setIcon(file);
    setRemoveIcon(false);
    setIconPreview(file ? URL.createObjectURL(file) : achievement?.icon_url ? mediaUrl(achievement.icon_url) : null);
  }

  function handleRemoveIcon() {
    setIcon(null);
    setRemoveIcon(true);
    setIconPreview(null);
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!title.trim() || !description.trim() || !conditionType) {
      setError("Заполните все поля");
      return;
    }
    if (!achievement && !icon) {
      setError("Загрузите изображение для иконки достижения");
      return;
    }
    const input: AchievementInput = {
      title: title.trim(),
      description: description.trim(),
      conditionType,
      conditionValue,
      color,
      visibility,
      showBeforeUnlock,
      enabled,
      order: achievement?.order ?? 0,
      icon,
      removeIcon,
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
        <label className="mb-1 block text-sm font-medium text-slate-700">Слоган / описание</label>
        <input
          className="w-full max-w-sm rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Ты открыл свою первую фразу"
        />
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Иконка</label>
        <p className="mb-2 text-xs text-slate-400">
          Загрузите готовое изображение -- оно и будет показано пользователю как иконка достижения.
        </p>
        <div className="flex items-center gap-3">
          <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full border border-slate-200 bg-slate-50">
            {iconPreview ? (
              <img src={iconPreview} alt="" className="h-full w-full object-cover" />
            ) : (
              <span className="text-xs text-slate-400">нет</span>
            )}
          </div>
          <div className="flex flex-col gap-1">
            <input type="file" accept="image/png,image/jpeg,image/webp" onChange={handleIconChange} className="text-sm" />
            {iconPreview && (
              <button type="button" onClick={handleRemoveIcon} className="w-fit text-xs text-red-600 hover:underline">
                Удалить иконку
              </button>
            )}
          </div>
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
          <label className="mb-1 block text-sm font-medium text-slate-700">Цвет</label>
          <div className="flex items-center gap-2">
            <input
              type="color"
              value={color}
              onChange={(e) => setColor(e.target.value)}
              className="h-9 w-9 cursor-pointer rounded border border-slate-300 p-0.5"
            />
            <input
              type="text"
              value={color}
              onChange={(e) => setColor(e.target.value)}
              className="w-24 rounded-md border border-slate-300 px-2 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            />
          </div>
        </div>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Видимость</label>
        <div className="flex flex-wrap gap-4">
          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input
              type="radio"
              checked={visibility === "visible"}
              onChange={() => setVisibility("visible")}
              className="h-4 w-4"
            />
            Открытое -- видно сразу, с прогрессом
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input
              type="radio"
              checked={visibility === "hidden"}
              onChange={() => setVisibility("hidden")}
              className="h-4 w-4"
            />
            Скрытое -- условие не показывается заранее
          </label>
        </div>
        {visibility === "hidden" && (
          <label className="mt-2 flex items-center gap-2 pl-6 text-sm text-slate-700">
            <input
              type="checkbox"
              checked={showBeforeUnlock}
              onChange={(e) => setShowBeforeUnlock(e.target.checked)}
              className="h-4 w-4 rounded border-slate-300"
            />
            Показывать силуэт до получения (иначе достижение появится только после получения)
          </label>
        )}
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

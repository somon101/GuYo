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

// Purely a display grouping/labeling choice for this page -- the backend's
// own condition_type set (app/achievements/conditions.py's CONDITION_TYPES)
// is untouched, and any condition_type not listed here still gets its own
// chain automatically (see conditionGroups below), just with the backend's
// own generic label instead of one of these shorter ones.
const GROUP_ORDER = ["words_learned", "phrases_opened", "lessons_completed", "streak_days"];
const GROUP_LABEL_OVERRIDES: Record<string, string> = {
  words_learned: "Изученные слова",
  phrases_opened: "Открытые фразы",
  lessons_completed: "Пройденные уроки",
  streak_days: "Активность",
};
const CONDITION_UNIT: Record<string, string> = {
  words_learned: "слов",
  phrases_opened: "фраз",
  lessons_completed: "уроков",
  streak_days: "дней",
};

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

  // Native HTML5 drag-and-drop, same mechanism as before, just scoped to
  // ONE chain at a time: dragging within a condition_type's row only
  // reshuffles that row's own items relative to each other -- every other
  // achievement (any other condition_type) keeps its exact current
  // position in the underlying list. The backend's `order` is still one
  // shared, global field (see admin_achievements.py's reorder endpoint),
  // so persisting still sends the FULL id list, just with only this one
  // chain's slice of it actually changed.
  function handleDragStart(id: number) {
    dragId.current = id;
  }

  function handleDragOver(e: DragEvent<HTMLDivElement>, conditionType: string, overId: number) {
    e.preventDefault();
    const draggedId = dragId.current;
    if (draggedId === null || draggedId === overId) return;
    setAchievements((prev) => {
      const subset = prev.filter((a) => a.condition_type === conditionType);
      const fromIdx = subset.findIndex((a) => a.id === draggedId);
      const toIdx = subset.findIndex((a) => a.id === overId);
      if (fromIdx === -1 || toIdx === -1) return prev;
      const reordered = [...subset];
      const [moved] = reordered.splice(fromIdx, 1);
      reordered.splice(toIdx, 0, moved);

      let cursor = 0;
      return prev.map((a) => (a.condition_type === conditionType ? reordered[cursor++] : a));
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

  // Every known condition_type gets its own chain, in GROUP_ORDER first,
  // then any the backend knows about that isn't in that fixed list (a
  // future condition_type needs zero changes here to get its own chain).
  const knownIds = conditionTypes.map((c) => c.id);
  const orderedGroupIds = [...GROUP_ORDER.filter((id) => knownIds.includes(id)), ...knownIds.filter((id) => !GROUP_ORDER.includes(id))];

  return (
    <div className="mx-auto max-w-5xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-slate-900">Достижения</h1>
          <p className="mt-0.5 text-sm text-slate-500">Каждый тип условия -- своя цепочка. Перетаскивайте карточки внутри цепочки, чтобы изменить порядок.</p>
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
        <div className={`flex flex-col gap-8 ${isReordering ? "opacity-60" : ""}`}>
          {orderedGroupIds.map((conditionType) => {
            const items = achievements
              .filter((a) => a.condition_type === conditionType)
              .sort((a, b) => a.order - b.order);
            if (items.length === 0) return null;
            const label = GROUP_LABEL_OVERRIDES[conditionType] ?? conditionTypes.find((c) => c.id === conditionType)?.label ?? conditionType;
            return (
              <AchievementChain
                key={conditionType}
                label={label}
                conditionType={conditionType}
                items={items}
                onDragStart={handleDragStart}
                onDragOver={handleDragOver}
                onDragEnd={handleDragEnd}
                onEdit={setEditing}
                onDelete={handleDelete}
                deletingId={deletingId}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}

function AchievementChain({
  label,
  conditionType,
  items,
  onDragStart,
  onDragOver,
  onDragEnd,
  onEdit,
  onDelete,
  deletingId,
}: {
  label: string;
  conditionType: string;
  items: Achievement[];
  onDragStart: (id: number) => void;
  onDragOver: (e: DragEvent<HTMLDivElement>, conditionType: string, overId: number) => void;
  onDragEnd: () => void;
  onEdit: (a: Achievement) => void;
  onDelete: (a: Achievement) => void;
  deletingId: number | null;
}) {
  const unit = CONDITION_UNIT[conditionType];
  return (
    <div>
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">{label}</h2>
      <div className="overflow-x-auto pb-2">
        <div className="flex w-max items-start">
          {items.map((a, index) => (
            <div key={a.id} className="flex items-start">
              <div
                draggable
                onDragStart={() => onDragStart(a.id)}
                onDragOver={(e) => onDragOver(e, conditionType, a.id)}
                onDragEnd={onDragEnd}
                className="group flex w-28 shrink-0 cursor-grab flex-col items-center gap-1.5 rounded-lg p-2 text-center active:cursor-grabbing hover:bg-slate-50"
              >
                <ChainIcon achievement={a} />
                <p className={`w-full truncate text-xs font-semibold ${a.enabled ? "text-slate-900" : "text-slate-400"}`} title={a.title}>
                  {a.title}
                </p>
                <p className="text-[11px] font-medium" style={{ color: a.enabled ? a.color : "#94a3b8" }}>
                  {a.condition_value} {unit}
                </p>
                {a.visibility === "hidden" && (
                  <span className="text-[10px] text-slate-400">{a.show_before_unlock ? "🔒 силуэт" : "🔒 скрыто"}</span>
                )}
                {!a.enabled && <span className="text-[10px] font-medium text-amber-600">отключено</span>}
                <div className="mt-0.5 flex gap-2 opacity-0 group-hover:opacity-100">
                  <button onClick={() => onEdit(a)} className="text-[11px] font-medium text-indigo-600 hover:text-indigo-700">
                    Изменить
                  </button>
                  <button
                    onClick={() => onDelete(a)}
                    disabled={deletingId === a.id}
                    className="text-[11px] text-slate-400 hover:text-red-600 disabled:opacity-60"
                  >
                    {deletingId === a.id ? "…" : "Удалить"}
                  </button>
                </div>
              </div>

              {index < items.length - 1 && (
                <div className="mt-7 h-0.5 w-6 shrink-0" style={{ backgroundColor: a.color, opacity: 0.3 }} />
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function ChainIcon({ achievement }: { achievement: Achievement }) {
  return (
    <div
      className="relative z-10 flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-full border-2 bg-white"
      style={{ borderColor: achievement.enabled ? achievement.color : "#cbd5e1" }}
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

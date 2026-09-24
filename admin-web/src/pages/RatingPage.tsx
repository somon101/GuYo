import axios from "axios";
import { useEffect, useRef, useState, type ChangeEvent, type DragEvent, type FormEvent } from "react";
import { API_URL } from "../api/client";
import {
  createRank,
  createSeason,
  deleteSeason,
  deleteSeasonIcon,
  deleteRank,
  endSeason,
  getRatingSettings,
  listRanks,
  listSeasons,
  setSeasonIcon,
  reorderRanks,
  updateRank,
  updateRatingSettings,
  updateSeason,
  type RankInput,
} from "../api/endpoints";
import type { Rank, RatingResetMode, RatingSettings, Season, SeasonStatus } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

export function RatingPage() {
  const [settings, setSettings] = useState<RatingSettings | null>(null);
  const [ranks, setRanks] = useState<Rank[]>([]);
  const [seasons, setSeasons] = useState<Season[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [s, r, se] = await Promise.all([getRatingSettings(), listRanks(), listSeasons()]);
      setSettings(s);
      setRanks(r);
      setSeasons(se);
    } catch {
      setLoadError("Не удалось загрузить настройки рейтинга");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-6 text-xl font-semibold text-slate-900">Рейтинг</h1>

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : (
        <div className="flex flex-col gap-6">
          <PointsCard settings={settings!} onSaved={setSettings} />
          <RanksCard ranks={ranks} setRanks={setRanks} />
          <SeasonsCard seasons={seasons} onChanged={reload} />
          <ResetCard settings={settings!} onSaved={setSettings} />
        </div>
      )}
    </div>
  );
}

function SectionCard({ title, subtitle, children }: { title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-slate-200 bg-white p-5">
      <h2 className="text-base font-semibold text-slate-900">{title}</h2>
      {subtitle && <p className="mt-0.5 text-xs text-slate-500">{subtitle}</p>}
      <div className="mt-4">{children}</div>
    </section>
  );
}

// --- Очки за изученное слово -------------------------------------------------

function PointsCard({
  settings,
  onSaved,
}: {
  settings: RatingSettings;
  onSaved: (s: RatingSettings) => void;
}) {
  const [value, setValue] = useState(settings.points_per_learned_word);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    setError(null);
    setIsSaving(true);
    try {
      const saved = await updateRatingSettings({ ...settings, points_per_learned_word: value });
      onSaved(saved);
    } catch {
      setError("Не удалось сохранить");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <SectionCard title="Очки" subtitle="Влияет только на будущие начисления -- уже заработанные очки не пересчитываются.">
      <div className="flex items-end gap-3">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Очков за изученное слово</label>
          <input
            type="number"
            min={0}
            className="w-32 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={value}
            onChange={(e) => setValue(Number(e.target.value))}
          />
        </div>
        <button
          onClick={handleSave}
          disabled={isSaving}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSaving ? "Сохранение…" : "Сохранить"}
        </button>
      </div>
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
    </SectionCard>
  );
}

// --- Сезонный сброс -----------------------------------------------------------

function ResetCard({ settings, onSaved }: { settings: RatingSettings; onSaved: (s: RatingSettings) => void }) {
  const [mode, setMode] = useState<RatingResetMode>(settings.season_reset_mode);
  const [value, setValue] = useState(settings.season_reset_value);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    setError(null);
    if (mode === "percent" && (value < 0 || value > 100)) {
      setError("Процент должен быть от 0 до 100");
      return;
    }
    setIsSaving(true);
    try {
      const saved = await updateRatingSettings({ ...settings, season_reset_mode: mode, season_reset_value: value });
      onSaved(saved);
    } catch {
      setError("Не удалось сохранить");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <SectionCard
      title="Сезонный сброс"
      subtitle="Применяется при завершении текущего сезона. Активен только один режим одновременно."
    >
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Режим</label>
          <select
            className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={mode}
            onChange={(e) => setMode(e.target.value as RatingResetMode)}
          >
            <option value="fixed">Фиксированное количество</option>
            <option value="percent">Процент</option>
          </select>
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Значение{mode === "percent" ? ", %" : ""}</label>
          <input
            type="number"
            min={0}
            max={mode === "percent" ? 100 : undefined}
            className="w-28 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={value}
            onChange={(e) => setValue(Number(e.target.value))}
          />
        </div>
        <button
          onClick={handleSave}
          disabled={isSaving}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSaving ? "Сохранение…" : "Сохранить"}
        </button>
      </div>
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
    </SectionCard>
  );
}

// --- Ранги ---------------------------------------------------------------------

function RanksCard({ ranks, setRanks }: { ranks: Rank[]; setRanks: (r: Rank[]) => void }) {
  const [editing, setEditing] = useState<Rank | "new" | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [isReordering, setIsReordering] = useState(false);
  const dragId = useRef<number | null>(null);

  async function handleDelete(r: Rank) {
    if (!confirm(`Удалить ранг «${r.name}»? Это действие нельзя отменить.`)) return;
    setActionError(null);
    setDeletingId(r.id);
    try {
      await deleteRank(r.id);
      setRanks(ranks.filter((x) => x.id !== r.id));
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setActionError(detail ?? "Не удалось удалить ранг");
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
    const from = ranks.findIndex((r) => r.id === dragId.current);
    const to = ranks.findIndex((r) => r.id === overId);
    if (from === -1 || to === -1) return;
    const next = [...ranks];
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    setRanks(next);
  }

  async function handleDragEnd() {
    dragId.current = null;
    setIsReordering(true);
    setActionError(null);
    try {
      const saved = await reorderRanks(ranks.map((r) => r.id));
      setRanks(saved);
    } catch {
      setActionError("Не удалось сохранить новый порядок");
    } finally {
      setIsReordering(false);
    }
  }

  return (
    <SectionCard title="Ранги" subtitle="Диапазоны очков не должны пересекаться. Перетаскивайте, чтобы изменить порядок.">
      <button
        onClick={() => setEditing("new")}
        className="mb-3 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
      >
        + Добавить ранг
      </button>

      {editing !== null && (
        <RankForm
          rank={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            if (editing === "new") setRanks([...ranks, saved]);
            else setRanks(ranks.map((r) => (r.id === saved.id ? saved : r)));
          }}
          onCancel={() => setEditing(null)}
        />
      )}

      {actionError && <p className="mb-3 text-sm text-red-600">{actionError}</p>}

      {ranks.length === 0 ? (
        <p className="text-sm text-slate-500">Рангов пока нет</p>
      ) : (
        <ul className={`flex flex-col gap-2 ${isReordering ? "opacity-60" : ""}`}>
          {ranks.map((r) => (
            <li
              key={r.id}
              draggable
              onDragStart={() => handleDragStart(r.id)}
              onDragOver={(e) => handleDragOver(e, r.id)}
              onDragEnd={handleDragEnd}
              className={`flex cursor-grab items-center gap-3 rounded-lg border p-3 active:cursor-grabbing ${r.enabled ? "border-slate-200 bg-white" : "border-slate-200 bg-white opacity-50"}`}
            >
              <div
                className="flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-full border-2 bg-white"
                style={{ borderColor: r.color }}
              >
                {r.icon_url ? (
                  <img src={mediaUrl(r.icon_url)!} alt="" className="h-full w-full object-cover" />
                ) : (
                  <span className="text-sm" style={{ color: r.color }}>
                    ?
                  </span>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="font-medium text-slate-900">{r.name}</p>
                <p className="text-xs text-slate-500">
                  {r.min_points} – {r.max_points ?? "∞"} очков
                  {!r.enabled && " · отключён"}
                </p>
              </div>
              <div className="flex shrink-0 gap-3">
                <button onClick={() => setEditing(r)} className="text-sm font-medium text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button
                  onClick={() => handleDelete(r)}
                  disabled={deletingId === r.id}
                  className="text-sm text-slate-400 hover:text-red-600 disabled:opacity-60"
                >
                  {deletingId === r.id ? "…" : "Удалить"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </SectionCard>
  );
}

function RankForm({ rank, onSaved, onCancel }: { rank: Rank | null; onSaved: (r: Rank) => void; onCancel: () => void }) {
  const [name, setName] = useState(rank?.name ?? "");
  const [minPoints, setMinPoints] = useState(rank?.min_points ?? 0);
  const [hasMax, setHasMax] = useState(rank ? rank.max_points !== null : true);
  const [maxPoints, setMaxPoints] = useState(rank?.max_points ?? 100);
  const [color, setColor] = useState(rank?.color ?? "#6366F1");
  const [enabled, setEnabled] = useState(rank?.enabled ?? true);
  const [icon, setIcon] = useState<File | null>(null);
  const [removeIcon, setRemoveIcon] = useState(false);
  const [iconPreview, setIconPreview] = useState<string | null>(rank?.icon_url ? mediaUrl(rank.icon_url) : null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function handleIconChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    setIcon(file);
    setRemoveIcon(false);
    setIconPreview(file ? URL.createObjectURL(file) : rank?.icon_url ? mediaUrl(rank.icon_url) : null);
  }

  function handleRemoveIcon() {
    setIcon(null);
    setRemoveIcon(true);
    setIconPreview(null);
  }

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
    const input: RankInput = {
      name: name.trim(),
      minPoints,
      maxPoints: hasMax ? maxPoints : null,
      color,
      enabled,
      icon,
      removeIcon,
    };
    setIsSubmitting(true);
    try {
      const saved = rank ? await updateRank(rank.id, input) : await createRank(input);
      onSaved(saved);
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setError(detail ?? "Не удалось сохранить ранг");
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
          placeholder="Бронза"
          autoFocus
        />
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Иконка</label>
        <p className="mb-2 text-xs text-slate-400">Загрузите изображение -- оно будет показано как иконка ранга.</p>
        <div className="flex items-center gap-3">
          <div className="flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-full border border-slate-200 bg-white">
            {iconPreview ? <img src={iconPreview} alt="" className="h-full w-full object-cover" /> : <span className="text-xs text-slate-400">нет</span>}
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
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Цвет</label>
          <div className="flex items-center gap-2">
            <input type="color" value={color} onChange={(e) => setColor(e.target.value)} className="h-9 w-9 cursor-pointer rounded border border-slate-300 p-0.5" />
            <input
              type="text"
              value={color}
              onChange={(e) => setColor(e.target.value)}
              className="w-24 rounded-md border border-slate-300 px-2 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            />
          </div>
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
          {isSubmitting ? "Сохранение…" : rank ? "Сохранить" : "Создать"}
        </button>
        <button type="button" onClick={onCancel} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50">
          Отмена
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </form>
  );
}

// --- Сезоны ---------------------------------------------------------------------

// datetime-local speaks the admin's own wall clock and carries no offset;
// the API speaks UTC. These two are the only place that conversion happens,
// so a period entered as "1 October, 00:00" is stored as that exact moment
// and read back as the same one.
function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromLocalInput(value: string): string | undefined {
  return value ? new Date(value).toISOString() : undefined;
}

function formatMoment(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("ru-RU", { dateStyle: "short", timeStyle: "short" });
}

const STATUS_LABELS: Record<SeasonStatus, string> = {
  scheduled: "Запланирован",
  active: "Идёт сейчас",
  completed: "Завершён",
};

const STATUS_CLASSES: Record<SeasonStatus, string> = {
  scheduled: "bg-amber-100 text-amber-700",
  active: "bg-indigo-100 text-indigo-700",
  completed: "bg-slate-100 text-slate-500",
};

function SeasonsCard({ seasons, onChanged }: { seasons: Season[]; onChanged: () => void }) {
  const [isCreating, setIsCreating] = useState(false);
  const [editing, setEditing] = useState<Season | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  function describeError(err: unknown, fallback: string): string {
    const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
    return detail ?? fallback;
  }

  async function handleEnd(season: Season) {
    if (
      !confirm(
        `Завершить «${season.name}»? Очки всех пользователей будут сброшены по текущим настройкам, а результат сохранится в истории. Это действие нельзя отменить.`,
      )
    )
      return;
    setError(null);
    setBusyId(season.id);
    try {
      await endSeason(season.id);
      onChanged();
    } catch (err) {
      setError(describeError(err, "Не удалось завершить сезон"));
    } finally {
      setBusyId(null);
    }
  }

  async function handleDelete(season: Season) {
    if (!confirm(`Удалить запланированный сезон «${season.name}»?`)) return;
    setError(null);
    setBusyId(season.id);
    try {
      await deleteSeason(season.id);
      onChanged();
    } catch (err) {
      setError(describeError(err, "Не удалось удалить сезон"));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <SectionCard
      title="Сезоны"
      subtitle="Периоды не должны пересекаться. Сезон, начинающийся ровно в момент окончания предыдущего, — это не пересечение: передача происходит автоматически."
    >
      <button
        onClick={() => {
          setIsCreating(true);
          setEditing(null);
        }}
        className="mb-3 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
      >
        + Добавить сезон
      </button>

      {(isCreating || editing) && (
        <SeasonForm
          season={editing}
          onSaved={() => {
            setIsCreating(false);
            setEditing(null);
            onChanged();
          }}
          onCancel={() => {
            setIsCreating(false);
            setEditing(null);
          }}
        />
      )}

      {error && <p className="mb-3 text-sm text-red-600">{error}</p>}

      {seasons.length === 0 ? (
        <p className="text-sm text-slate-500">Сезонов пока нет</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {seasons.map((s) => (
            <li
              key={s.id}
              className={`flex items-center gap-3 rounded-lg border p-3 ${s.status === "active" ? "border-indigo-200 bg-indigo-50" : "border-slate-200 bg-white"}`}
            >
              <SeasonIcon season={s} onChanged={onChanged} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <p className="truncate font-medium text-slate-900">{s.name}</p>
                  <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_CLASSES[s.status]}`}>
                    {STATUS_LABELS[s.status]}
                  </span>
                  <span className="shrink-0 text-xs text-slate-400">#{s.id}</span>
                </div>
                <p className="text-xs text-slate-500">
                  {formatMoment(s.starts_at)} —{" "}
                  {s.status === "completed"
                    ? formatMoment(s.ended_at)
                    : s.ends_at
                      ? formatMoment(s.ends_at)
                      : "завершается вручную"}
                </p>
              </div>
              <div className="flex shrink-0 gap-3">
                {s.status !== "completed" && (
                  <button
                    onClick={() => {
                      setIsCreating(false);
                      setEditing(s);
                    }}
                    className="text-sm font-medium text-indigo-600 hover:text-indigo-700"
                  >
                    Изменить
                  </button>
                )}
                {s.status === "active" && (
                  <button
                    onClick={() => handleEnd(s)}
                    disabled={busyId === s.id}
                    className="text-sm font-medium text-red-600 hover:text-red-700 disabled:opacity-60"
                  >
                    Завершить
                  </button>
                )}
                {s.status === "scheduled" && (
                  <button
                    onClick={() => handleDelete(s)}
                    disabled={busyId === s.id}
                    className="text-sm text-slate-400 hover:text-red-600 disabled:opacity-60"
                  >
                    Удалить
                  </button>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </SectionCard>
  );
}

/** A season's picture. Uploaded and cleared on its own endpoints, so there
 * is nothing to save afterwards -- and nothing renders it in the app yet,
 * it is only stored. */
function SeasonIcon({ season, onChanged }: { season: Season; onChanged: () => void }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isBusy, setIsBusy] = useState(false);

  async function handleFile(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setIsBusy(true);
    try {
      await setSeasonIcon(season.id, file);
      onChanged();
    } finally {
      setIsBusy(false);
    }
  }

  async function handleRemove() {
    setIsBusy(true);
    try {
      await deleteSeasonIcon(season.id);
      onChanged();
    } finally {
      setIsBusy(false);
    }
  }

  return (
    <div className="flex shrink-0 flex-col items-center gap-1">
      <div className="flex h-11 w-11 items-center justify-center overflow-hidden rounded-lg bg-slate-100">
        {season.icon_url ? (
          <img src={mediaUrl(season.icon_url)!} alt="" className="h-full w-full object-contain" />
        ) : (
          <span className="text-sm text-slate-400">—</span>
        )}
      </div>
      <div className="flex items-center gap-2 text-xs">
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          disabled={isBusy}
          className="text-indigo-600 hover:underline disabled:opacity-50"
        >
          {season.icon_url ? "Заменить" : "Иконка"}
        </button>
        {season.icon_url && (
          <button
            type="button"
            onClick={handleRemove}
            disabled={isBusy}
            className="text-rose-600 hover:underline disabled:opacity-50"
          >
            Убрать
          </button>
        )}
      </div>
      <input ref={inputRef} type="file" accept="image/*" onChange={handleFile} className="hidden" />
    </div>
  );
}

function SeasonForm({
  season,
  onSaved,
  onCancel,
}: {
  season: Season | null;
  onSaved: () => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState(season?.name ?? "");
  const [startsAt, setStartsAt] = useState(toLocalInput(season?.starts_at ?? null));
  const [hasEnd, setHasEnd] = useState(season ? season.ends_at !== null : false);
  const [endsAt, setEndsAt] = useState(toLocalInput(season?.ends_at ?? null));
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!name.trim()) {
      setError("Введите название сезона");
      return;
    }
    if (hasEnd && !endsAt) {
      setError("Укажите дату и время окончания");
      return;
    }
    setIsSubmitting(true);
    try {
      if (season) {
        await updateSeason(season.id, {
          name: name.trim(),
          startsAt: fromLocalInput(startsAt),
          endsAt: hasEnd ? fromLocalInput(endsAt) : undefined,
          clearEndsAt: !hasEnd,
        });
      } else {
        await createSeason({
          name: name.trim(),
          startsAt: fromLocalInput(startsAt),
          endsAt: hasEnd ? fromLocalInput(endsAt) : undefined,
        });
      }
      onSaved();
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setError(detail ?? "Не удалось сохранить сезон");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-4 rounded-lg border border-slate-200 bg-slate-50 p-4">
      <div className="flex flex-wrap gap-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Название</label>
          <input
            className="w-56 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Сезон 3"
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Начало</label>
          <input
            type="datetime-local"
            className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={startsAt}
            onChange={(e) => setStartsAt(e.target.value)}
          />
          <p className="mt-1 text-xs text-slate-400">Пусто — начать сразу</p>
        </div>
        <div>
          <label className="mb-1 flex items-center gap-2 text-sm font-medium text-slate-700">
            <input type="checkbox" checked={hasEnd} onChange={(e) => setHasEnd(e.target.checked)} />
            Окончание
          </label>
          <input
            type="datetime-local"
            disabled={!hasEnd}
            className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 disabled:bg-slate-100 disabled:text-slate-400"
            value={endsAt}
            onChange={(e) => setEndsAt(e.target.value)}
          />
          <p className="mt-1 text-xs text-slate-400">
            {hasEnd ? "Завершится автоматически" : "Только вручную"}
          </p>
        </div>
      </div>

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}

      <div className="mt-4 flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : season ? "Сохранить" : "Создать сезон"}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-white"
        >
          Отмена
        </button>
      </div>
    </form>
  );
}

import axios from "axios";
import { useEffect, useRef, useState, type DragEvent, type FormEvent } from "react";
import {
  createSlogan,
  deleteSlogan,
  listSlogans,
  reorderSlogans,
  updateSlogan,
} from "../api/endpoints";
import type { Slogan } from "../types";

/**
 * "Слоганы": the greeting lines shown under a user's name on Главная.
 *
 * The admin curates a pool; the backend draws one per user per day and
 * holds it (see backend/app/slogans/service.py). So editing a line here
 * changes what everyone who drew it sees, and disabling one takes it out
 * of the draw -- including for people who already drew it today.
 */
export function SlogansPage() {
  const [slogans, setSlogans] = useState<Slogan[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Slogan | "new" | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [isReordering, setIsReordering] = useState(false);
  const dragId = useRef<number | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      setSlogans(await listSlogans());
    } catch {
      setLoadError("Не удалось загрузить слоганы");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  function describeError(err: unknown, fallback: string): string {
    const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
    return detail ?? fallback;
  }

  async function handleToggle(slogan: Slogan) {
    setActionError(null);
    setBusyId(slogan.id);
    try {
      const saved = await updateSlogan(slogan.id, { enabled: !slogan.enabled });
      setSlogans((prev) => prev.map((s) => (s.id === saved.id ? saved : s)));
    } catch (err) {
      setActionError(describeError(err, "Не удалось изменить слоган"));
    } finally {
      setBusyId(null);
    }
  }

  async function handleDelete(slogan: Slogan) {
    if (
      !confirm(
        `Удалить слоган «${slogan.text}»? Тот, кому он уже выпал сегодня, получит другой. Чтобы просто перестать его показывать, достаточно выключить.`,
      )
    )
      return;
    setActionError(null);
    setBusyId(slogan.id);
    try {
      await deleteSlogan(slogan.id);
      setSlogans((prev) => prev.filter((s) => s.id !== slogan.id));
    } catch (err) {
      setActionError(describeError(err, "Не удалось удалить слоган"));
    } finally {
      setBusyId(null);
    }
  }

  function handleDragStart(id: number) {
    dragId.current = id;
  }

  function handleDragOver(e: DragEvent<HTMLLIElement>, overId: number) {
    e.preventDefault();
    if (dragId.current === null || dragId.current === overId) return;
    const from = slogans.findIndex((s) => s.id === dragId.current);
    const to = slogans.findIndex((s) => s.id === overId);
    if (from === -1 || to === -1) return;
    const next = [...slogans];
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    setSlogans(next);
  }

  async function handleDragEnd() {
    dragId.current = null;
    setIsReordering(true);
    setActionError(null);
    try {
      setSlogans(await reorderSlogans(slogans.map((s) => s.id)));
    } catch {
      setActionError("Не удалось сохранить новый порядок");
    } finally {
      setIsReordering(false);
    }
  }

  const enabledCount = slogans.filter((s) => s.enabled).length;

  return (
    <div className="p-6">
      <h1 className="mb-1 text-xl font-semibold text-slate-900">Слоганы</h1>
      <p className="mb-6 max-w-2xl text-sm text-slate-500">
        Строка под приветствием на главном экране. Каждый пользователь получает случайный включённый слоган, который
        закрепляется за ним на день — на следующий день выпадает другой. Пока включённых слоганов нет, приложение
        показывает собственную встроенную строку.
      </p>

      <div className="mb-4 flex items-center gap-3">
        <button
          onClick={() => setEditing("new")}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Добавить слоган
        </button>
        <span className="text-sm text-slate-500">
          Включено: {enabledCount} из {slogans.length}
        </span>
      </div>

      {editing !== null && (
        <SloganForm
          slogan={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            setSlogans((prev) =>
              prev.some((s) => s.id === saved.id) ? prev.map((s) => (s.id === saved.id ? saved : s)) : [...prev, saved],
            );
          }}
          onCancel={() => setEditing(null)}
        />
      )}

      {actionError && <p className="mb-3 text-sm text-red-600">{actionError}</p>}

      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : slogans.length === 0 ? (
        <p className="text-sm text-slate-500">Слоганов пока нет — приложение показывает встроенную строку</p>
      ) : (
        <ul className={`flex flex-col gap-2 ${isReordering ? "opacity-60" : ""}`}>
          {slogans.map((s) => (
            <li
              key={s.id}
              draggable
              onDragStart={() => handleDragStart(s.id)}
              onDragOver={(e) => handleDragOver(e, s.id)}
              onDragEnd={handleDragEnd}
              className={`flex cursor-grab items-center gap-3 rounded-lg border border-slate-200 bg-white p-4 active:cursor-grabbing ${
                s.enabled ? "" : "opacity-50"
              }`}
            >
              <div className="min-w-0 flex-1">
                <p className="text-slate-900" translate="no">
                  {s.text}
                </p>
                {!s.enabled && <p className="mt-0.5 text-xs text-amber-700">отключён — не выпадает никому</p>}
              </div>
              <div className="flex shrink-0 gap-3">
                <button
                  onClick={() => handleToggle(s)}
                  disabled={busyId === s.id}
                  className="text-sm font-medium text-slate-500 hover:text-slate-700 disabled:opacity-60"
                >
                  {s.enabled ? "Выключить" : "Включить"}
                </button>
                <button
                  onClick={() => setEditing(s)}
                  className="text-sm font-medium text-indigo-600 hover:text-indigo-700"
                >
                  Изменить
                </button>
                <button
                  onClick={() => handleDelete(s)}
                  disabled={busyId === s.id}
                  className="text-sm text-slate-400 hover:text-red-600 disabled:opacity-60"
                >
                  {busyId === s.id ? "…" : "Удалить"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function SloganForm({
  slogan,
  onSaved,
  onCancel,
}: {
  slogan: Slogan | null;
  onSaved: (s: Slogan) => void;
  onCancel: () => void;
}) {
  const [text, setText] = useState(slogan?.text ?? "");
  const [enabled, setEnabled] = useState(slogan?.enabled ?? true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!text.trim()) {
      setError("Введите текст слогана");
      return;
    }
    setIsSubmitting(true);
    try {
      const saved = slogan
        ? await updateSlogan(slogan.id, { text: text.trim(), enabled })
        : await createSlogan({ text: text.trim(), enabled });
      onSaved(saved);
    } catch (err) {
      const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
      setError(detail ?? "Не удалось сохранить слоган");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-4 rounded-lg border border-slate-200 bg-slate-50 p-4">
      <label className="mb-1 block text-sm font-medium text-slate-700">Текст</label>
      <input
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Давай учиться сегодня!"
        maxLength={255}
        autoFocus
      />

      <label className="mt-3 flex items-center gap-2 text-sm font-medium text-slate-700">
        <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
        Включён
      </label>

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}

      <div className="mt-4 flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : slogan ? "Сохранить" : "Создать"}
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

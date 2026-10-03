import axios from "axios";
import { useEffect, useRef, useState, type DragEvent, type FormEvent } from "react";
import { API_URL } from "../api/client";
import {
  createStatusEmoji,
  createStatusPhrase,
  deleteStatusEmoji,
  deleteStatusPhrase,
  listStatusEmojis,
  listStatusPhrases,
  reorderStatusEmojis,
  reorderStatusPhrases,
  updateStatusEmoji,
  updateStatusPhrase,
} from "../api/endpoints";
import type { StatusEmoji, StatusPhrase } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

function describeError(err: unknown, fallback: string): string {
  const detail = axios.isAxiosError(err) ? (err.response?.data?.detail as string | undefined) : undefined;
  return typeof detail === "string" ? detail : fallback;
}

/**
 * "Статусы": what a user can show next to their name in the rating — one
 * emoji and one phrase, both picked from these lists (never typed by the
 * user). The emoji are GuYo's own pictures, so they look the same on every
 * phone. Disabling an item hides it from the picker and from everyone who
 * already shows it, without losing it.
 */
export function StatusesPage() {
  return (
    <div className="p-6">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">Статусы</h1>
      <p className="mb-6 max-w-2xl text-sm text-slate-500">
        Участник рейтинга выбирает одно эмодзи и одну фразу из этих списков — их видят все: эмодзи на аватарке, фраза
        по нажатию. Свой текст написать нельзя. Перетаскивайте, чтобы поменять порядок в окне выбора.
      </p>
      <EmojiSection />
      <div className="h-8" />
      <PhraseSection />
    </div>
  );
}

// Shared drag-to-reorder for both lists.
function useDragOrder<T extends { id: number }>(
  items: T[],
  setItems: (next: T[]) => void,
  save: (ids: number[]) => Promise<T[]>,
  onError: (msg: string) => void,
) {
  const dragId = useRef<number | null>(null);
  return {
    onDragStart: (id: number) => (dragId.current = id),
    onDragOver: (e: DragEvent<HTMLElement>, overId: number) => {
      e.preventDefault();
      if (dragId.current === null || dragId.current === overId) return;
      const from = items.findIndex((x) => x.id === dragId.current);
      const to = items.findIndex((x) => x.id === overId);
      if (from === -1 || to === -1) return;
      const next = [...items];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved);
      setItems(next);
    },
    onDragEnd: async () => {
      dragId.current = null;
      try {
        setItems(await save(items.map((x) => x.id)));
      } catch {
        onError("Не удалось сохранить новый порядок");
      }
    },
  };
}

function EmojiSection() {
  const [emojis, setEmojis] = useState<StatusEmoji[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<StatusEmoji | "new" | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);
  const drag = useDragOrder(emojis, setEmojis, reorderStatusEmojis, setError);

  useEffect(() => {
    listStatusEmojis()
      .then(setEmojis)
      .catch(() => setError("Не удалось загрузить эмодзи"))
      .finally(() => setIsLoading(false));
  }, []);

  async function toggle(e: StatusEmoji) {
    setBusyId(e.id);
    setError(null);
    try {
      const saved = await updateStatusEmoji(e.id, { enabled: !e.enabled });
      setEmojis((prev) => prev.map((x) => (x.id === saved.id ? saved : x)));
    } catch (err) {
      setError(describeError(err, "Не удалось изменить эмодзи"));
    } finally {
      setBusyId(null);
    }
  }

  async function remove(e: StatusEmoji) {
    if (!confirm(`Удалить эмодзи «${e.name}»? У тех, кто его выбрал, оно просто пропадёт. Можно вместо этого выключить.`))
      return;
    setBusyId(e.id);
    setError(null);
    try {
      await deleteStatusEmoji(e.id);
      setEmojis((prev) => prev.filter((x) => x.id !== e.id));
    } catch (err) {
      setError(describeError(err, "Не удалось удалить эмодзи"));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section>
      <div className="mb-3 flex items-center gap-3">
        <h2 className="text-lg font-semibold text-slate-900">Эмодзи</h2>
        <button
          onClick={() => setEditing("new")}
          className="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Добавить эмодзи
        </button>
        <span className="text-sm text-slate-500">
          Включено: {emojis.filter((e) => e.enabled).length} из {emojis.length}
        </span>
      </div>
      <p className="mb-3 max-w-2xl text-xs text-slate-500">
        Картинка PNG/WEBP с прозрачным фоном, квадратная, лучше 256×256. Она показывается маленьким значком на аватарке.
      </p>
      {editing !== null && (
        <EmojiForm
          emoji={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            setEmojis((prev) =>
              prev.some((x) => x.id === saved.id) ? prev.map((x) => (x.id === saved.id ? saved : x)) : [...prev, saved],
            );
          }}
          onCancel={() => setEditing(null)}
        />
      )}
      {error && <p className="mb-3 text-sm text-red-600">{error}</p>}
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : emojis.length === 0 ? (
        <p className="text-sm text-slate-500">Эмодзи пока нет</p>
      ) : (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(170px,1fr))] gap-3">
          {emojis.map((e) => (
            <div
              key={e.id}
              draggable
              onDragStart={() => drag.onDragStart(e.id)}
              onDragOver={(ev) => drag.onDragOver(ev, e.id)}
              onDragEnd={drag.onDragEnd}
              className={`card flex cursor-grab flex-col items-center gap-2 p-3 active:cursor-grabbing ${
                e.enabled ? "" : "opacity-50"
              }`}
            >
              {e.image_url ? (
                <img src={mediaUrl(e.image_url)!} alt={e.name} className="h-16 w-16 object-contain" />
              ) : (
                <div className="h-16 w-16 rounded-full bg-slate-100" />
              )}
              <p className="text-sm font-medium text-slate-900" translate="no">
                {e.name}
              </p>
              {!e.enabled && <p className="text-xs text-amber-700">выключено</p>}
              <div className="flex flex-wrap justify-center gap-x-3 gap-y-1 text-xs">
                <button onClick={() => toggle(e)} disabled={busyId === e.id} className="text-slate-500 hover:text-slate-700">
                  {e.enabled ? "Выключить" : "Включить"}
                </button>
                <button onClick={() => setEditing(e)} className="text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button onClick={() => remove(e)} disabled={busyId === e.id} className="text-slate-400 hover:text-red-600">
                  Удалить
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

function EmojiForm({
  emoji,
  onSaved,
  onCancel,
}: {
  emoji: StatusEmoji | null;
  onSaved: (e: StatusEmoji) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState(emoji?.name ?? "");
  const [enabled, setEnabled] = useState(emoji?.enabled ?? true);
  const [image, setImage] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(emoji?.image_url ? mediaUrl(emoji.image_url) : null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!name.trim()) return setError("Введите название");
    if (!emoji && !image) return setError("Выберите картинку");
    setIsSubmitting(true);
    try {
      const saved = emoji
        ? await updateStatusEmoji(emoji.id, { name: name.trim(), enabled, image })
        : await createStatusEmoji({ name: name.trim(), enabled, image });
      onSaved(saved);
    } catch (err) {
      setError(describeError(err, "Не удалось сохранить эмодзи"));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="card mb-4 flex flex-wrap items-end gap-4 p-4">
      <div className="flex h-20 w-20 items-center justify-center rounded-xl bg-slate-50">
        {preview ? <img src={preview} alt="" className="h-16 w-16 object-contain" /> : <span className="text-xs text-slate-400">нет</span>}
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Картинка</label>
        <input
          type="file"
          accept="image/png,image/webp,image/jpeg"
          onChange={(e) => {
            const f = e.target.files?.[0] ?? null;
            setImage(f);
            if (f) setPreview(URL.createObjectURL(f));
          }}
          className="text-sm"
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Название</label>
        <input
          className="field px-3 py-2 text-sm"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Огонь"
          maxLength={64}
        />
      </div>
      <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
        <input type="checkbox" className="switch" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
        Включено
      </label>
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : emoji ? "Сохранить" : "Добавить"}
        </button>
        <button type="button" onClick={onCancel} className="btn-tinted rounded-md px-4 py-2 text-sm font-medium">
          Отмена
        </button>
      </div>
      {error && <p className="w-full text-sm text-red-600">{error}</p>}
    </form>
  );
}

function PhraseSection() {
  const [phrases, setPhrases] = useState<StatusPhrase[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<StatusPhrase | "new" | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);
  const drag = useDragOrder(phrases, setPhrases, reorderStatusPhrases, setError);

  useEffect(() => {
    listStatusPhrases()
      .then(setPhrases)
      .catch(() => setError("Не удалось загрузить фразы"))
      .finally(() => setIsLoading(false));
  }, []);

  async function toggle(p: StatusPhrase) {
    setBusyId(p.id);
    setError(null);
    try {
      const saved = await updateStatusPhrase(p.id, { enabled: !p.enabled });
      setPhrases((prev) => prev.map((x) => (x.id === saved.id ? saved : x)));
    } catch (err) {
      setError(describeError(err, "Не удалось изменить фразу"));
    } finally {
      setBusyId(null);
    }
  }

  async function remove(p: StatusPhrase) {
    if (!confirm(`Удалить фразу «${p.text}»? У тех, кто её выбрал, она просто пропадёт. Можно вместо этого выключить.`))
      return;
    setBusyId(p.id);
    setError(null);
    try {
      await deleteStatusPhrase(p.id);
      setPhrases((prev) => prev.filter((x) => x.id !== p.id));
    } catch (err) {
      setError(describeError(err, "Не удалось удалить фразу"));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section>
      <div className="mb-3 flex items-center gap-3">
        <h2 className="text-lg font-semibold text-slate-900">Фразы</h2>
        <button
          onClick={() => setEditing("new")}
          className="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Добавить фразу
        </button>
        <span className="text-sm text-slate-500">
          Включено: {phrases.filter((p) => p.enabled).length} из {phrases.length}
        </span>
      </div>
      {editing !== null && (
        <PhraseForm
          phrase={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            setPhrases((prev) =>
              prev.some((x) => x.id === saved.id) ? prev.map((x) => (x.id === saved.id ? saved : x)) : [...prev, saved],
            );
          }}
          onCancel={() => setEditing(null)}
        />
      )}
      {error && <p className="mb-3 text-sm text-red-600">{error}</p>}
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : phrases.length === 0 ? (
        <p className="text-sm text-slate-500">Фраз пока нет</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {phrases.map((p) => (
            <li
              key={p.id}
              draggable
              onDragStart={() => drag.onDragStart(p.id)}
              onDragOver={(ev) => drag.onDragOver(ev, p.id)}
              onDragEnd={drag.onDragEnd}
              className={`card flex cursor-grab items-center gap-3 p-4 active:cursor-grabbing ${p.enabled ? "" : "opacity-50"}`}
            >
              <p className="min-w-0 flex-1 text-slate-900" translate="no">
                {p.text}
                {!p.enabled && <span className="ml-2 text-xs text-amber-700">выключена</span>}
              </p>
              <div className="flex shrink-0 gap-3 text-sm">
                <button onClick={() => toggle(p)} disabled={busyId === p.id} className="font-medium text-slate-500 hover:text-slate-700">
                  {p.enabled ? "Выключить" : "Включить"}
                </button>
                <button onClick={() => setEditing(p)} className="font-medium text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button onClick={() => remove(p)} disabled={busyId === p.id} className="text-slate-400 hover:text-red-600">
                  Удалить
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function PhraseForm({
  phrase,
  onSaved,
  onCancel,
}: {
  phrase: StatusPhrase | null;
  onSaved: (p: StatusPhrase) => void;
  onCancel: () => void;
}) {
  const [text, setText] = useState(phrase?.text ?? "");
  const [enabled, setEnabled] = useState(phrase?.enabled ?? true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!text.trim()) return setError("Введите фразу");
    setIsSubmitting(true);
    try {
      const saved = phrase
        ? await updateStatusPhrase(phrase.id, { text: text.trim(), enabled })
        : await createStatusPhrase({ text: text.trim(), enabled });
      onSaved(saved);
    } catch (err) {
      setError(describeError(err, "Не удалось сохранить фразу"));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="card mb-4 p-4">
      <label className="mb-1 block text-sm font-medium text-slate-700">Фраза (до 60 символов)</label>
      <input
        className="w-full field px-3 py-2 text-sm"
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Я буду первым!"
        maxLength={60}
        autoFocus
      />
      <label className="mt-3 flex items-center gap-2 text-sm font-medium text-slate-700">
        <input type="checkbox" className="switch" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
        Включена
      </label>
      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
      <div className="mt-4 flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : phrase ? "Сохранить" : "Создать"}
        </button>
        <button type="button" onClick={onCancel} className="btn-tinted rounded-md px-4 py-2 text-sm font-medium">
          Отмена
        </button>
      </div>
    </form>
  );
}

import { useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  addLanguageWordForm,
  deleteLanguageWordAudio,
  deleteLanguageWordForm,
  getLanguageWord,
  updateLanguageWord,
  uploadLanguageWordAudio,
  type LanguageWordDetail,
} from "../api/endpoints";

/** Карточка слова НА ОДНОМ ЯЗЫКЕ.
 *
 * Здесь правятся только языковые поля: написание, транскрипция (необязательно),
 * озвучка и формы — всё это своё у каждого языка.
 *
 * Классификация (роль, важность, категория, темы, картинка) принадлежит понятию
 * и правится в разделе «База»: она одна на все языки, дублировать её незачем —
 * связь идёт через concept_id. */
export function LanguageWordPage() {
  const { code = "", entryId = "" } = useParams();
  const id = Number(entryId);
  const [word, setWord] = useState<LanguageWordDetail | null>(null);
  const [text, setText] = useState("");
  const [transcription, setTranscription] = useState("");
  const [formText, setFormText] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const audioInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    getLanguageWord(code, id)
      .then((data) => {
        if (cancelled) return;
        setWord(data);
        setText(data.text);
        setTranscription(data.transcription ?? "");
      })
      .catch(() => {
        if (!cancelled) setError("Не удалось загрузить слово");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [code, id]);

  function apply(next: LanguageWordDetail, message: string) {
    setWord(next);
    setText(next.text);
    setTranscription(next.transcription ?? "");
    setNotice(message);
    setTimeout(() => setNotice(null), 2500);
  }

  async function saveText() {
    if (!word) return;
    setBusy(true);
    setError(null);
    try {
      const next = await updateLanguageWord(code, id, {
        text: text.trim() || word.text,
        transcription: transcription.trim(),
        removeTranscription: !transcription.trim() && !!word.transcription,
      });
      apply(next, "Сохранено");
    } catch {
      setError("Не удалось сохранить");
    } finally {
      setBusy(false);
    }
  }

  async function addForm() {
    const value = formText.trim();
    if (!value) return;
    setBusy(true);
    try {
      apply(await addLanguageWordForm(code, id, value), "Форма добавлена");
      setFormText("");
    } catch {
      setError("Не удалось добавить форму");
    } finally {
      setBusy(false);
    }
  }

  async function removeForm(formId: number) {
    setBusy(true);
    try {
      apply(await deleteLanguageWordForm(code, id, formId), "Форма удалена");
    } catch {
      setError("Не удалось удалить форму");
    } finally {
      setBusy(false);
    }
  }

  async function uploadAudio(file: File) {
    setBusy(true);
    try {
      apply(await uploadLanguageWordAudio(code, id, file), "Озвучка загружена");
    } catch {
      setError("Не удалось загрузить озвучку");
    } finally {
      setBusy(false);
    }
  }

  async function removeAudio() {
    setBusy(true);
    try {
      apply(await deleteLanguageWordAudio(code, id), "Озвучка удалена");
    } catch {
      setError("Не удалось удалить озвучку");
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <p className="text-sm text-slate-500">Загрузка…</p>;
  if (!word) return <p className="text-sm text-red-600">{error ?? "Слово не найдено"}</p>;

  const dirty = text.trim() !== word.text || transcription.trim() !== (word.transcription ?? "");

  return (
    <div className="mx-auto max-w-3xl">
      <Link
        to={`/languages/${code}/words`}
        className="mb-4 inline-block text-sm text-indigo-600 hover:underline"
      >
        ← Слова языка «{code}»
      </Link>

      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">
        Слово на языке «{code}»
      </h1>
      <p className="mb-6 text-sm text-slate-500">
        Здесь правятся только поля этого языка. Классификация общая для всех языков и живёт в
        разделе{" "}
        <Link to="/base" className="text-indigo-600 hover:underline">
          База
        </Link>
        .
      </p>

      <div className="card mb-4 p-5">
        <label className="block text-sm">
          <span className="mb-1 block text-xs font-medium text-slate-500">Исходное слово</span>
          <input
            className="w-full field px-3 py-2 text-sm"
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
        </label>
        <label className="mt-4 block text-sm">
          <span className="mb-1 block text-xs font-medium text-slate-500">
            Транскрипция (необязательно)
          </span>
          <input
            className="w-full max-w-xs field px-3 py-2 text-sm"
            placeholder="/odam/"
            value={transcription}
            onChange={(e) => setTranscription(e.target.value)}
          />
        </label>

        <div className="mt-4">
          <span className="mb-1 block text-xs font-medium text-slate-500">
            Озвучка слова на этом языке
          </span>
          <div className="flex flex-wrap items-center gap-3">
            {word.audio_url ? (
              <audio controls src={word.audio_url} className="h-9" />
            ) : (
              <span className="text-sm text-slate-400">Озвучки нет</span>
            )}
            <button
              onClick={() => audioInput.current?.click()}
              disabled={busy}
              className="btn-tinted rounded-full px-3 py-1.5 text-sm font-medium disabled:opacity-50"
            >
              {word.audio_url ? "Заменить" : "Добавить озвучку"}
            </button>
            {word.audio_url && (
              <button
                onClick={removeAudio}
                disabled={busy}
                className="btn-tinted-danger rounded-full px-3 py-1.5 text-sm font-medium disabled:opacity-50"
              >
                Удалить
              </button>
            )}
            <input
              ref={audioInput}
              type="file"
              accept="audio/*"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0] ?? null;
                if (file) void uploadAudio(file);
                e.target.value = "";
              }}
            />
          </div>
        </div>

        <div className="mt-5 flex items-center gap-3">
          <button
            onClick={saveText}
            disabled={busy || !dirty}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            {busy ? "…" : "Сохранить"}
          </button>
          {notice && <span className="text-sm text-emerald-600">{notice}</span>}
          {error && <span className="text-sm text-red-600">{error}</span>}
        </div>
      </div>

      <div className="card mb-4 p-5">
        <p className="mb-3 text-sm font-medium text-slate-900">
          Формы на языке «{code}» <span className="text-xs text-slate-400">({word.forms.length})</span>
        </p>
        <ul className="mb-3 flex flex-wrap gap-2">
          {word.forms.map((f) => (
            <li
              key={f.id}
              className="flex items-center gap-2 rounded-full bg-[var(--fill)] px-3 py-1.5 text-sm"
            >
              {f.text}
              <button
                onClick={() => void removeForm(f.id)}
                disabled={busy}
                className="text-slate-400 hover:text-red-600 disabled:opacity-50"
              >
                ✕
              </button>
            </li>
          ))}
          {word.forms.length === 0 && (
            <li className="text-sm text-red-600">
              Форм нет — без них не собираются мини-фразы и упражнение «Собери слово»
            </li>
          )}
        </ul>
        <div className="flex items-center gap-2">
          <input
            className="w-full max-w-xs field px-3 py-2 text-sm"
            placeholder="Новая форма"
            value={formText}
            onChange={(e) => setFormText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") void addForm();
            }}
          />
          <button
            onClick={addForm}
            disabled={busy || !formText.trim()}
            className="btn-tinted rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Добавить форму
          </button>
        </div>
      </div>

      <div className="card p-5">
        <p className="mb-3 text-sm font-medium text-slate-900">
          Классификация <span className="text-xs text-slate-400">— общая для всех языков</span>
        </p>
        <p className="text-sm text-slate-600">
          Понятие №{word.concept_id} · роль: {word.role ?? "не задана"} · важность:{" "}
          {word.importance}
        </p>
        {word.siblings.length > 0 && (
          <p className="mt-2 text-xs text-slate-500">
            На других языках: {word.siblings.map((s) => `${s.language} — ${s.text}`).join(", ")}
          </p>
        )}
        <Link
          to={`/dictionaries/${word.dictionary_id}/words/${word.concept_id}`}
          className="mt-3 inline-block text-sm text-indigo-600 hover:underline"
        >
          Открыть классификацию в «Базе» →
        </Link>
      </div>
    </div>
  );
}

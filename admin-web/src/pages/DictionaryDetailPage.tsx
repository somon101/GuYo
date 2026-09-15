import { useEffect, useState, type FormEvent } from "react";
import { Link, useParams } from "react-router-dom";
import { API_URL } from "../api/client";
import { createWord, deleteWord, getDictionary, listWords } from "../api/endpoints";
import type { Dictionary, Word } from "../types";
import { LANGUAGE_LABELS } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

export function DictionaryDetailPage() {
  const { id } = useParams<{ id: string }>();
  const dictionaryId = Number(id);

  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [words, setWords] = useState<Word[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isFormOpen, setIsFormOpen] = useState(false);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [dict, wordList] = await Promise.all([
        getDictionary(dictionaryId),
        listWords(dictionaryId),
      ]);
      setDictionary(dict);
      setWords(wordList);
    } catch {
      setLoadError("Не удалось загрузить словарь");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dictionaryId]);

  async function handleDelete(wordId: number) {
    if (!confirm("Удалить это слово?")) return;
    await deleteWord(wordId);
    reload();
  }

  if (isLoading) {
    return <p className="text-sm text-slate-500">Загрузка…</p>;
  }

  if (loadError || !dictionary) {
    return <p className="text-sm text-red-600">{loadError ?? "Словарь не найден"}</p>;
  }

  return (
    <div className="mx-auto max-w-3xl">
      <Link to="/dictionaries" className="mb-4 inline-block text-sm text-indigo-600 hover:underline">
        ← Все словари
      </Link>

      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-slate-900">{dictionary.name}</h1>
          <p className="text-sm text-slate-500">
            {LANGUAGE_LABELS[dictionary.language]} · {words.length} слов
          </p>
        </div>
        <button
          onClick={() => setIsFormOpen((v) => !v)}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Добавить слово
        </button>
      </div>

      {isFormOpen && (
        <AddWordForm
          dictionaryId={dictionaryId}
          languageLabel={LANGUAGE_LABELS[dictionary.language]}
          onCreated={() => {
            setIsFormOpen(false);
            reload();
          }}
          onCancel={() => setIsFormOpen(false)}
        />
      )}

      {words.length === 0 ? (
        <p className="text-sm text-slate-500">В этом словаре пока нет слов</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {words.map((w) => (
            <li
              key={w.id}
              className="flex items-start justify-between gap-4 rounded-lg border border-slate-200 bg-white p-4"
            >
              <div className="flex items-start gap-4">
                {mediaUrl(w.image_url) && (
                  <img
                    src={mediaUrl(w.image_url)!}
                    alt={w.word}
                    className="h-14 w-14 shrink-0 rounded-md border border-slate-200 object-cover"
                  />
                )}
                <div translate="no">
                  <p className="text-base font-medium text-slate-900">{w.word}</p>
                  {w.transcription && (
                    <p className="text-sm text-slate-400">{w.transcription}</p>
                  )}
                  <p className="text-sm text-slate-600">{w.translation}</p>
                  <div className="mt-2 flex gap-3">
                    {mediaUrl(w.word_audio_url) && (
                      <audio controls src={mediaUrl(w.word_audio_url)!} className="h-8" />
                    )}
                    {mediaUrl(w.translation_audio_url) && (
                      <audio controls src={mediaUrl(w.translation_audio_url)!} className="h-8" />
                    )}
                  </div>
                </div>
              </div>
              <div className="flex shrink-0 items-center gap-4">
                <Link
                  to={`/dictionaries/${dictionaryId}/words/${w.id}`}
                  className="text-sm font-medium text-indigo-600 hover:underline"
                >
                  Редактировать
                </Link>
                <button
                  onClick={() => handleDelete(w.id)}
                  className="text-sm text-slate-400 hover:text-red-600"
                >
                  Удалить
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function AddWordForm({
  dictionaryId,
  languageLabel,
  onCreated,
  onCancel,
}: {
  dictionaryId: number;
  languageLabel: string;
  onCreated: () => void;
  onCancel: () => void;
}) {
  const [word, setWord] = useState("");
  const [translation, setTranslation] = useState("");
  const [transcription, setTranscription] = useState("");
  const [wordAudio, setWordAudio] = useState<File | null>(null);
  const [translationAudio, setTranslationAudio] = useState<File | null>(null);
  const [image, setImage] = useState<File | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await createWord(dictionaryId, {
        word,
        translation,
        transcription: transcription || undefined,
        wordAudio,
        translationAudio,
        image,
      });
      onCreated();
    } catch {
      setError("Не удалось сохранить слово");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="mb-6 flex flex-col gap-4 rounded-lg border border-slate-200 bg-white p-5"
    >
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Язык</label>
        <input
          className="w-full max-w-xs rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-500"
          value={languageLabel}
          disabled
        />
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Слово</label>
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={word}
            onChange={(e) => setWord(e.target.value)}
            autoFocus
            required
          />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Перевод</label>
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={translation}
            onChange={(e) => setTranslation(e.target.value)}
            required
          />
        </div>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">
          Транскрипция <span className="font-normal text-slate-400">(необязательно)</span>
        </label>
        <input
          className="w-full max-w-xs rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          value={transcription}
          onChange={(e) => setTranscription(e.target.value)}
          placeholder="/ˈæpəl/"
        />
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <FileField label="Аудио слова" accept="audio/*" onChange={setWordAudio} />
        <FileField label="Аудио перевода" accept="audio/*" onChange={setTranslationAudio} />
        <FileField label="Изображение" accept="image/*" onChange={setImage} />
      </div>

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {isSubmitting ? "Сохранение…" : "Сохранить"}
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

function FileField({
  label,
  accept,
  onChange,
}: {
  label: string;
  accept: string;
  onChange: (file: File | null) => void;
}) {
  return (
    <div>
      <label className="mb-1 block text-sm font-medium text-slate-700">
        {label} <span className="font-normal text-slate-400">(необязательно)</span>
      </label>
      <input
        type="file"
        accept={accept}
        onChange={(e) => onChange(e.target.files?.[0] ?? null)}
        className="w-full text-sm text-slate-600 file:mr-3 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-slate-700 hover:file:bg-slate-200"
      />
    </div>
  );
}

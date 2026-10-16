import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { API_URL } from "../api/client";
import {
  getDictionary,
  getWord,
  listCategories,
  updateWord,
  upsertTranslation,
  updateWordLearning,
} from "../api/endpoints";
import type { Category, Dictionary, TranslationLanguage, Word, WordTopic } from "../types";
import { TRANSLATION_LANGUAGE_LABELS } from "../types";

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

/** Local staging for one file resource: lets the editor pick/replace/remove
 * a file and see the result immediately, without sending anything to the
 * server until "Сохранить изменения" is pressed. */
interface FileStage {
  currentUrl: string | null;
  newFile: File | null;
  removed: boolean;
}

function freshStage(currentUrl: string | null): FileStage {
  return { currentUrl, newFile: null, removed: false };
}

function stagePreviewUrl(stage: FileStage): string | null {
  if (stage.newFile) return URL.createObjectURL(stage.newFile);
  if (stage.removed) return null;
  return mediaUrl(stage.currentUrl);
}

function stageChanged(stage: FileStage): boolean {
  return stage.newFile !== null || (stage.removed && stage.currentUrl !== null);
}

interface TranslationRow {
  language: TranslationLanguage;
  originalText: string;
  text: string;
  /// Транскрипция ИМЕННО этого языка: у русского слова своя, у английского
  /// перевода -- своя. Хранится в языковой записи.
  transcription: string;
  originalTranscription: string;
  audio: FileStage;
  isNew: boolean; // not persisted yet on the server
}

export function WordEditPage() {
  const { dictId, wordId } = useParams<{ dictId: string; wordId: string }>();
  const dictionaryId = Number(dictId);
  const id = Number(wordId);

  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [word, setWord] = useState<Word | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Editable fields, seeded from the loaded word.
  const [wordText, setWordText] = useState("");
  const [transcription, setTranscription] = useState("");
  const [categoryId, setCategoryId] = useState<number | null>(null);
  const [image, setImage] = useState<FileStage>(freshStage(null));
  const [wordAudio, setWordAudio] = useState<FileStage>(freshStage(null));
  const [translations, setTranslations] = useState<TranslationRow[]>([]);

  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [savedNotice, setSavedNotice] = useState(false);

  function loadInto(w: Word) {
    setWordText(w.word);
    setTranscription(w.transcription ?? "");
    setCategoryId(w.category_id);
    setImage(freshStage(w.image_url));
    setWordAudio(freshStage(w.word_audio_url));
    const rows: TranslationRow[] = w.translations.map((t) => ({
      language: t.language,
      originalText: t.text,
      text: t.text,
      transcription: t.transcription ?? "",
      originalTranscription: t.transcription ?? "",
      audio: freshStage(t.audio_url),
      isNew: false,
    }));
    // Uzbek and English are always offered: an empty field until someone
    // (or the AI translator) fills it. Learners reading either only see
    // words translated into it.
    for (const lang of ["uz", "en"] as const) {
      if (!rows.some((r) => r.language === lang)) {
        rows.push({
          language: lang,
          originalText: "",
          text: "",
          transcription: "",
          originalTranscription: "",
          audio: freshStage(null),
          isNew: true,
        });
      }
    }
    setTranslations(rows);
  }

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [w, d, cats] = await Promise.all([
        getWord(id),
        getDictionary(dictionaryId),
        listCategories(dictionaryId),
      ]);
      setWord(w);
      setDictionary(d);
      setCategories(cats);
      loadInto(w);
    } catch {
      setLoadError("Не удалось загрузить слово");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, dictionaryId]);

  const hasChanges = useMemo(() => {
    if (!word) return false;
    if (wordText.trim() !== word.word) return true;
    if (transcription.trim() !== (word.transcription ?? "")) return true;
    if (categoryId !== word.category_id) return true;
    if (stageChanged(image) || stageChanged(wordAudio)) return true;
    return translations.some(
      (t) =>
        t.text.trim() !== t.originalText ||
        t.transcription.trim() !== t.originalTranscription ||
        stageChanged(t.audio),
    );
  }, [word, wordText, transcription, categoryId, image, wordAudio, translations]);

  async function handleSave() {
    if (!word) return;
    setIsSaving(true);
    setSaveError(null);
    setSavedNotice(false);
    try {
      const wordPatch: Parameters<typeof updateWord>[1] = {};
      if (wordText.trim() !== word.word) wordPatch.word = wordText.trim();

      const trimmedTranscription = transcription.trim();
      if (trimmedTranscription !== (word.transcription ?? "")) {
        if (trimmedTranscription) wordPatch.transcription = trimmedTranscription;
        else wordPatch.removeTranscription = true;
      }

      if (categoryId !== word.category_id) {
        if (categoryId !== null) wordPatch.categoryId = categoryId;
        else wordPatch.removeCategory = true;
      }

      if (image.newFile) wordPatch.image = image.newFile;
      else if (image.removed && image.currentUrl) wordPatch.removeImage = true;

      if (wordAudio.newFile) wordPatch.wordAudio = wordAudio.newFile;
      else if (wordAudio.removed && wordAudio.currentUrl) wordPatch.removeWordAudio = true;

      const requests: Promise<unknown>[] = [];
      if (Object.keys(wordPatch).length > 0) {
        requests.push(updateWord(id, wordPatch));
      }

      for (const t of translations) {
        if (t.isNew && !t.text.trim()) continue;
        const textChanged = t.text.trim() !== t.originalText;
        const audioChanged = stageChanged(t.audio);
        const transcriptionChanged = t.transcription.trim() !== t.originalTranscription;
        if (!textChanged && !audioChanged && !transcriptionChanged) continue;
        requests.push(
          upsertTranslation(id, t.language, {
            text: t.text.trim() || t.originalText,
            transcription: t.transcription.trim(),
            removeTranscription: !t.transcription.trim() && !!t.originalTranscription,
            audio: t.audio.newFile,
            removeAudio: t.audio.removed && !t.audio.newFile,
          }),
        );
      }

      await Promise.all(requests);
      await reload();
      setSavedNotice(true);
      setTimeout(() => setSavedNotice(false), 4000);
    } catch {
      setSaveError("Не удалось сохранить изменения. Попробуйте ещё раз.");
    } finally {
      setIsSaving(false);
    }
  }

  if (isLoading) return <p className="text-sm text-slate-500">Загрузка…</p>;
  if (loadError || !word || !dictionary) {
    return <p className="text-sm text-red-600">{loadError ?? "Слово не найдено"}</p>;
  }

  return (
    <div className="mx-auto max-w-2xl pb-24">
      <nav className="mb-4 flex flex-wrap items-center gap-1 text-sm text-slate-500">
        <Link to="/dictionaries" className="text-indigo-600 hover:underline">
          Языки
        </Link>
        <span>→</span>
        <Link to={`/dictionaries/${dictionaryId}`} className="text-indigo-600 hover:underline" translate="no">
          {dictionary.name}
        </Link>
        <span>→</span>
        <span className="text-slate-700" translate="no">{word.word}</span>
      </nav>

      <div className="mb-6 flex items-start justify-between">
        <div>
          <h1 className="text-[26px] font-bold tracking-tight text-slate-900">
            Понятие №{word.id}
          </h1>
          <p className="mt-1 text-sm text-slate-600" translate="no">
            {word.word}
          </p>
          <p className="mt-1 max-w-lg text-xs text-slate-400">
            Номер понятия — то, к чему привязаны языковые записи. Здесь правится только
            классификация; слово, транскрипция, озвучка и формы каждого языка — в разделе «Языки».
          </p>
        </div>
        <Link
          to={`/dictionaries/${dictionaryId}`}
          className="shrink-0 btn-tinted rounded-full px-3 py-1.5 text-sm font-medium"
        >
          ← Назад в базу
        </Link>
      </div>

      <Section title="Классификация">
        <p className="mb-4 text-sm text-slate-500">
          Это общее для всех языков: изображение, категория, темы, важность и роль. Дублировать
          по языкам не нужно — всё связано через номер понятия.
        </p>
        <Field label="Изображение" hint="необязательно">
          <ImageField stage={image} onChange={setImage} />
        </Field>
        <Field label="Категория" hint="необязательно">
          <select
            className="w-full max-w-xs field px-3 py-2 text-sm"
            value={categoryId ?? ""}
            onChange={(e) => setCategoryId(e.target.value ? Number(e.target.value) : null)}
          >
            <option value="">Без категории</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </Field>
      </Section>

      <WordLearningSection word={word} onSaved={setWord} />

      <Section title="Языки понятия">
        <p className="mb-4 text-sm text-slate-500">
          У каждого языка своё написание, транскрипция, озвучка и формы — они правятся в разделе
          «Языки», у своей языковой записи. Здесь только список: чтобы видеть, что уже есть.
        </p>
        <ul className="flex flex-col gap-2">
          {word.language_entries.map((entry) => (
            <li
              key={entry.id}
              className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-[var(--fill)] px-3 py-2"
            >
              <span className="text-sm">
                <span className="text-slate-500">
                  {(TRANSLATION_LANGUAGE_LABELS as Record<string, string>)[entry.language] ??
                    entry.language}
                  :
                </span>{" "}
                <span className="font-medium text-slate-900" translate="no">
                  {entry.text || "—"}
                </span>
              </span>
              <Link
                to={`/languages/${entry.language}/words/${entry.id}`}
                className="text-sm text-indigo-600 hover:underline"
              >
                Править слово →
              </Link>
            </li>
          ))}
          {word.language_entries.length === 0 && (
            <li className="text-sm text-slate-500">Языковых записей пока нет.</li>
          )}
        </ul>
      </Section>

      <div className="sticky bottom-4 mt-6 flex items-center gap-3 card shadow-float p-4">
        <button
          onClick={handleSave}
          disabled={!hasChanges || isSaving}
          className="rounded-md bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {isSaving ? "Сохранение…" : "Сохранить изменения"}
        </button>
        {savedNotice && <span className="text-sm text-emerald-600">Изменения сохранены</span>}
        {saveError && <span className="text-sm text-red-600">{saveError}</span>}
        {!hasChanges && !savedNotice && !saveError && (
          <span className="text-sm text-slate-400">Нет несохранённых изменений</span>
        )}
      </div>
    </div>
  );
}

/** One fixed-language group of Forms: existing forms (with delete) plus a
 * single-text-field "+ Добавить форму" that saves immediately. The language
 * itself is never chosen here — it's fixed by the caller (the dictionary's
 * own language, or Tajik), per the block-language rule. */

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-6 card p-5">
      <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h2>
      {children}
    </div>
  );
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mb-4 last:mb-0">
      <label className="mb-1 block text-sm font-medium text-slate-700">
        {label} {hint && <span className="font-normal text-slate-400">({hint})</span>}
      </label>
      {children}
    </div>
  );
}

function ImageField({
  stage,
  onChange,
}: {
  stage: FileStage;
  onChange: (stage: FileStage) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const preview = stagePreviewUrl(stage);

  return (
    <div>
      {preview ? (
        <div className="flex items-start gap-4">
          <img
            src={preview}
            alt="Предпросмотр"
            className="h-32 w-32 rounded-[10px] object-cover"
          />
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => inputRef.current?.click()}
              className="btn-tinted rounded-full px-3 py-1.5 text-sm font-medium"
            >
              Заменить
            </button>
            <button
              type="button"
              onClick={() => onChange({ ...stage, newFile: null, removed: true })}
              className="btn-tinted-danger rounded-full px-3 py-1.5 text-sm font-medium"
            >
              Удалить
            </button>
          </div>
        </div>
      ) : (
        <div className="flex items-center gap-3">
          <span className="text-sm text-slate-400">Изображение не добавлено</span>
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            className="btn-tinted rounded-full px-3 py-1.5 text-sm font-medium"
          >
            Добавить изображение
          </button>
        </div>
      )}
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0] ?? null;
          if (file) onChange({ currentUrl: stage.currentUrl, newFile: file, removed: false });
          e.target.value = "";
        }}
      />
    </div>
  );
}


const TOPIC_OPTIONS: { value: WordTopic; label: string }[] = [
  { value: "study", label: "Учёба" },
  { value: "work", label: "Работа" },
  { value: "communication", label: "Общение" },
  { value: "travel", label: "Путешествия" },
  { value: "relocation", label: "Переезд" },
];

const IMPORTANCE_LABELS: Record<number, string> = {
  5: "5 — самые нужные",
  4: "4 — очень нужные",
  3: "3 — обычные",
  2: "2 — реже нужны",
  1: "1 — редкие",
};

const WORD_ROLE_OPTIONS = [
  { value: "pronoun", label: "Местоимение (кто)" },
  { value: "verb", label: "Глагол (действие)" },
  { value: "noun", label: "Существительное (что)" },
  { value: "adjective", label: "Прилагательное (какой)" },
  { value: "adverb", label: "Наречие (как)" },
  { value: "preposition", label: "Предлог" },
  { value: "number", label: "Число" },
  { value: "other", label: "Другое" },
];

/** How a random lesson prioritises this word: its own form and save,
 * separate from the main multipart word form above. */
function WordLearningSection({ word, onSaved }: { word: Word; onSaved: (word: Word) => void }) {
  const [importance, setImportance] = useState(word.importance);
  const [topics, setTopics] = useState<WordTopic[]>(word.topics);
  const [role, setRole] = useState<string>(word.role ?? "");
  const [isSaving, setIsSaving] = useState(false);
  const [status, setStatus] = useState<string | null>(null);

  const isDirty =
    importance !== word.importance ||
    role !== (word.role ?? "") ||
    topics.length !== word.topics.length ||
    topics.some((t) => !word.topics.includes(t));

  function toggle(topic: WordTopic) {
    setTopics((prev) => (prev.includes(topic) ? prev.filter((t) => t !== topic) : [...prev, topic]));
    setStatus(null);
  }

  async function save() {
    setIsSaving(true);
    setStatus(null);
    try {
      onSaved(await updateWordLearning(word.id, { importance, topics, role: role || null }));
      setStatus("Сохранено");
    } catch {
      setStatus("Не удалось сохранить");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Section title="Темы, важность и роль">
      <p className="mb-4 text-sm text-slate-500">
        Случайный урок сначала берёт слова из тем, которые выбрал человек, и внутри них — самые важные.
      </p>
      <Field label="Темы" hint="можно несколько или ни одной">
        <div className="flex flex-wrap gap-2">
          {TOPIC_OPTIONS.map((o) => {
            const on = topics.includes(o.value);
            return (
              <button
                key={o.value}
                type="button"
                aria-pressed={on}
                onClick={() => toggle(o.value)}
                className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors ${
                  on ? "bg-[var(--sys-blue)] text-white" : "bg-[var(--fill)] text-slate-700 hover:bg-[var(--fill-strong)]"
                }`}
              >
                {o.label}
              </button>
            );
          })}
        </div>
      </Field>
      <Field label="Важность">
        <select
          className="w-full max-w-xs field px-3 py-2 text-sm"
          value={importance}
          onChange={(e) => {
            setImportance(Number(e.target.value));
            setStatus(null);
          }}
        >
          {[5, 4, 3, 2, 1].map((n) => (
            <option key={n} value={n}>
              {IMPORTANCE_LABELS[n]}
            </option>
          ))}
        </select>
      </Field>
      <Field label="Роль в фразе" hint="задаётся один раз — по ней объясняются все мини-фразы с этим словом">
        <select
          className="w-full max-w-xs field px-3 py-2 text-sm"
          value={role}
          onChange={(e) => {
            setRole(e.target.value);
            setStatus(null);
          }}
        >
          <option value="">Не указана</option>
          {WORD_ROLE_OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      </Field>
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={save}
          disabled={isSaving || !isDirty}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {isSaving ? "Сохранение…" : "Сохранить"}
        </button>
        {status && <span className="text-sm text-slate-500">{status}</span>}
      </div>
    </Section>
  );
}

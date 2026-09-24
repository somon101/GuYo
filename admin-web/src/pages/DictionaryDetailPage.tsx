import { useCallback, useEffect, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import { Link, useParams } from "react-router-dom";
import { API_URL } from "../api/client";
import {
  createCategory,
  deleteCategoryIcon,
  exportDictionary,
  getDictionary,
  getDictionaryImportJob,
  listCategories,
  setCategoryIcon,
  startDictionaryImport,
  type ImportJob,
} from "../api/endpoints";
import type { Category, Dictionary } from "../types";
import { Modal } from "../components/Modal";
import { LanguageSectionTabs } from "../components/LanguageSectionTabs";

const IMPORT_JOB_POLL_MS = 1500;

function mediaUrl(path: string | null): string | null {
  return path ? `${API_URL}${path}` : null;
}

// The import itself runs on the backend as a job, entirely independent of
// this component's lifetime -- so the one piece of state that actually
// needs to survive a lost React tree (navigating away, closing the tab,
// reopening Admin Web later) is just the job_id, kept here rather than in
// memory. On mount, this page checks for one and resumes polling it
// instead of assuming "no import in progress".
function importJobStorageKey(dictionaryId: number): string {
  return `guyo_import_job_${dictionaryId}`;
}

export function DictionaryDetailPage() {
  const { id } = useParams<{ id: string }>();
  const dictionaryId = Number(id);

  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const importInputRef = useRef<HTMLInputElement>(null);
  const [importJob, setImportJob] = useState<ImportJob | null>(null);
  const pollTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [dict, cats] = await Promise.all([
        getDictionary(dictionaryId),
        listCategories(dictionaryId),
      ]);
      setDictionary(dict);
      setCategories(cats);
    } catch {
      setLoadError("Не удалось загрузить язык");
    } finally {
      setIsLoading(false);
    }
  }

  const pollImportJob = useCallback(
    (jobId: string) => {
      getDictionaryImportJob(dictionaryId, jobId)
        .then((job) => {
          setImportJob(job);
          if (job.status === "pending" || job.status === "processing") {
            pollTimeoutRef.current = setTimeout(() => pollImportJob(jobId), IMPORT_JOB_POLL_MS);
            return;
          }
          // Terminal state (completed or failed): the job's result is now
          // shown from this response, so there's nothing left to resume
          // from storage next time this page loads.
          localStorage.removeItem(importJobStorageKey(dictionaryId));
          if (job.status === "completed") {
            reload();
          }
        })
        .catch(() => {
          // A transient network hiccup while polling must not make the
          // import look "lost" -- the job keeps running server-side
          // regardless, so just try again shortly.
          pollTimeoutRef.current = setTimeout(() => pollImportJob(jobId), IMPORT_JOB_POLL_MS);
        });
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [dictionaryId],
  );

  useEffect(() => {
    reload();
    const storedJobId = localStorage.getItem(importJobStorageKey(dictionaryId));
    if (storedJobId) {
      pollImportJob(storedJobId);
    }
    return () => {
      if (pollTimeoutRef.current) clearTimeout(pollTimeoutRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dictionaryId]);

  async function handleExport() {
    const blob = await exportDictionary(dictionaryId);
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${dictionary?.name ?? "dictionary"}.zip`;
    a.click();
    URL.revokeObjectURL(url);
  }

  function summaryText(job: ImportJob): string {
    return (
      `Категорий создано: ${job.categories_created} (переиспользовано: ${job.categories_reused}) · ` +
      `Слов создано: ${job.words_created} (переиспользовано: ${job.words_reused}) · ` +
      `Форм добавлено: ${job.forms_added}`
    );
  }

  async function handleImportFile(file: File) {
    setImportJob(null);
    try {
      const job = await startDictionaryImport(dictionaryId, file);
      localStorage.setItem(importJobStorageKey(dictionaryId), job.job_id);
      setImportJob(job);
      pollImportJob(job.job_id);
    } catch {
      setImportJob({
        job_id: "",
        status: "failed",
        error_message: "Не удалось отправить файл на сервер. Проверьте соединение и повторите попытку.",
        categories_created: null,
        categories_reused: null,
        words_created: null,
        words_reused: null,
        forms_added: null,
        phrases_created: null,
        phrases_reused: null,
      });
    }
  }

  const isImporting = importJob?.status === "pending" || importJob?.status === "processing";

  if (isLoading) {
    return <p className="text-sm text-slate-500">Загрузка…</p>;
  }

  if (loadError || !dictionary) {
    return <p className="text-sm text-red-600">{loadError ?? "Язык не найден"}</p>;
  }

  return (
    <div className="mx-auto max-w-3xl">
      <Link to="/dictionaries" className="mb-4 inline-block text-sm text-indigo-600 hover:underline">
        ← Все языки
      </Link>

      <LanguageSectionTabs dictionaryId={dictionaryId} active="words" />

      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-slate-900" translate="no">
            {dictionary.name}
          </h1>
          <p className="text-xs text-slate-400">ID: {dictionary.id}</p>
          <p className="text-sm text-slate-500">
            {dictionary.is_published ? "Опубликовано" : "Черновик"} · Категорий: {categories.length} ·
            Всего слов: {dictionary.word_count}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button
            onClick={handleExport}
            className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            Экспорт
          </button>
          <button
            onClick={() => importInputRef.current?.click()}
            disabled={isImporting}
            className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 disabled:opacity-50"
          >
            {isImporting ? "Импорт…" : "Импорт"}
          </button>
          <input
            ref={importInputRef}
            type="file"
            accept=".zip,application/zip"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0] ?? null;
              if (file) handleImportFile(file);
              e.target.value = "";
            }}
          />
          <button
            onClick={() => setIsModalOpen(true)}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
          >
            + Создать категорию
          </button>
        </div>
      </div>

      {importJob && (
        <p
          className={`mb-4 text-sm ${
            importJob.status === "failed"
              ? "text-red-600"
              : importJob.status === "completed"
                ? "text-emerald-600"
                : "text-slate-500"
          }`}
        >
          {importJob.status === "failed" && (importJob.error_message ?? "Не удалось импортировать файл.")}
          {importJob.status === "completed" && summaryText(importJob)}
          {(importJob.status === "pending" || importJob.status === "processing") &&
            "Импорт выполняется на сервере… Можно уйти со страницы — прогресс сохранится, и результат будет здесь при возврате."}
        </p>
      )}

      <Link
        to={`/dictionaries/${dictionaryId}/words`}
        className="mb-4 block rounded-lg border border-slate-200 bg-white p-4 text-sm font-medium text-indigo-600 hover:bg-slate-50"
      >
        Все слова ({dictionary.word_count}) →
      </Link>

      {categories.length === 0 ? (
        <p className="text-sm text-slate-500">Категорий пока нет</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {categories.map((c) => (
            <li
              key={c.id}
              className="flex items-center gap-3 rounded-lg border border-slate-200 bg-white p-4"
            >
              <CategoryIcon
                dictionaryId={dictionaryId}
                category={c}
                onChanged={(updated) =>
                  setCategories((prev) => prev.map((x) => (x.id === updated.id ? updated : x)))
                }
              />
              <Link
                to={`/dictionaries/${dictionaryId}/categories/${c.id}`}
                className="flex min-w-0 flex-1 items-center justify-between gap-3 hover:text-indigo-600"
              >
                <span className="truncate font-medium text-slate-900" translate="no">
                  {c.name}
                </span>
                <span className="shrink-0 text-sm text-slate-400">{c.word_count} слов</span>
              </Link>
            </li>
          ))}
        </ul>
      )}

      {isModalOpen && (
        <CreateCategoryModal
          dictionaryId={dictionaryId}
          onCreated={() => {
            setIsModalOpen(false);
            reload();
          }}
          onClose={() => setIsModalOpen(false)}
        />
      )}
    </div>
  );
}

/** One category's picture, uploaded and cleared right here: each is its own
 * PUT/DELETE on that category, so there is nothing to "save" afterwards.
 * A category with no icon shows a neutral placeholder -- exactly what the
 * mobile app falls back to when icon_url is null. */
function CategoryIcon({
  dictionaryId,
  category,
  onChanged,
}: {
  dictionaryId: number;
  category: Category;
  onChanged: (category: Category) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isBusy, setIsBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const url = mediaUrl(category.icon_url);

  async function handleFile(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    // Same input is reused for every replace, so clear it either way.
    e.target.value = "";
    if (!file) return;
    setIsBusy(true);
    setError(null);
    try {
      onChanged(await setCategoryIcon(dictionaryId, category.id, file));
    } catch {
      setError("Не удалось загрузить иконку");
    } finally {
      setIsBusy(false);
    }
  }

  async function handleRemove() {
    setIsBusy(true);
    setError(null);
    try {
      onChanged(await deleteCategoryIcon(dictionaryId, category.id));
    } catch {
      setError("Не удалось удалить иконку");
    } finally {
      setIsBusy(false);
    }
  }

  return (
    <div className="flex shrink-0 flex-col items-center gap-1">
      <div className="flex h-12 w-12 items-center justify-center overflow-hidden rounded-lg bg-slate-100">
        {url ? (
          <img src={url} alt="" className="h-full w-full object-contain" />
        ) : (
          <span className="text-lg text-slate-400">📁</span>
        )}
      </div>
      <div className="flex items-center gap-2 text-xs">
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          disabled={isBusy}
          className="text-indigo-600 hover:underline disabled:opacity-50"
        >
          {category.icon_url ? "Заменить" : "Иконка"}
        </button>
        {category.icon_url && (
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
      {error && <p className="text-xs text-rose-600">{error}</p>}
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        onChange={handleFile}
        className="hidden"
      />
    </div>
  );
}

function CreateCategoryModal({
  dictionaryId,
  onCreated,
  onClose,
}: {
  dictionaryId: number;
  onCreated: () => void;
  onClose: () => void;
}) {
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    setIsSaving(true);
    setError(null);
    try {
      await createCategory(dictionaryId, trimmed);
      onCreated();
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 409) setError("Категория с таким названием уже есть в этом словаре");
      else setError("Не удалось создать категорию");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Modal title="Новая категория" onClose={onClose}>
      <form onSubmit={handleSubmit} className="flex flex-col gap-3">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Название</label>
          <input
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            value={name}
            onChange={(e) => setName(e.target.value)}
            autoFocus
            required
          />
        </div>
        <div className="flex gap-2">
          <button
            type="submit"
            disabled={isSaving}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {isSaving ? "Сохранение…" : "Создать"}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            Отмена
          </button>
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
      </form>
    </Modal>
  );
}

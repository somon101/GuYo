import axios from "axios";
import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  createMiniPhrase,
  deleteMiniPhrase,
  fillMiniPhraseStarter,
  getDictionary,
  listMiniPhraseRoles,
  listMiniPhrases,
  listMiniPhraseTemplates,
  listWords,
  suggestMiniPhraseParts,
  updateMiniPhrase,
  type MiniPhraseInput,
  type MiniPhraseStarterReport,
} from "../api/endpoints";
import { LanguageSectionTabs } from "../components/LanguageSectionTabs";
import type { Dictionary, MiniPhrase, MiniPhraseRole, MiniPhraseTemplate, Word } from "../types";

function errorText(e: unknown, fallback: string): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return fallback;
}

interface PartDraft {
  text: string;
  word_id: number | null;
  word_form_id: number | null;
  role: string | null;
}

interface Draft {
  id: number | null;
  template_id: number | null;
  text: string;
  translation_tg: string;
  translation_uz: string;
  translation_en: string;
  enabled: boolean;
  parts: PartDraft[];
}

const EMPTY: Draft = {
  id: null,
  template_id: null,
  text: "",
  translation_tg: "",
  translation_uz: "",
  translation_en: "",
  enabled: true,
  parts: [],
};

/** A language's mini-phrases ("Я иду"): each one is its ready text, its
 * translations, a template, and its parts in order -- every part linked to
 * an existing word (and the exact form when the phrase uses one). */
export function MiniPhrasesPage() {
  const { id } = useParams<{ id: string }>();
  const dictionaryId = Number(id);
  const [dictionary, setDictionary] = useState<Dictionary | null>(null);
  const [items, setItems] = useState<MiniPhrase[]>([]);
  const [templates, setTemplates] = useState<MiniPhraseTemplate[]>([]);
  const [roles, setRoles] = useState<MiniPhraseRole[]>([]);
  const [words, setWords] = useState<Word[]>([]);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [report, setReport] = useState<MiniPhraseStarterReport | null>(null);
  const [isFilling, setIsFilling] = useState(false);

  async function fillStarter() {
    setIsFilling(true);
    try {
      setReport(await fillMiniPhraseStarter(dictionaryId));
      reload();
    } catch (e) {
      alert(errorText(e, "Не удалось заполнить"));
    } finally {
      setIsFilling(false);
    }
  }

  async function reload() {
    try {
      const [d, list, t, r, w] = await Promise.all([
        getDictionary(dictionaryId),
        listMiniPhrases(dictionaryId),
        listMiniPhraseTemplates(),
        listMiniPhraseRoles(),
        listWords(dictionaryId),
      ]);
      setDictionary(d);
      setItems(list);
      setTemplates(t);
      setRoles(r);
      setWords(w);
    } catch {
      setLoadError("Не удалось загрузить мини-фразы");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dictionaryId]);

  const roleLabel = useMemo(() => Object.fromEntries(roles.map((r) => [r.id, r.label])), [roles]);

  async function remove(mp: MiniPhrase) {
    if (!confirm(`Удалить «${mp.text}»?`)) return;
    await deleteMiniPhrase(mp.id);
    reload();
  }

  function edit(mp: MiniPhrase) {
    setDraft({
      id: mp.id,
      template_id: mp.template_id,
      text: mp.text,
      translation_tg: mp.translation_tg,
      translation_uz: mp.translation_uz ?? "",
      translation_en: mp.translation_en ?? "",
      enabled: mp.enabled,
      parts: mp.parts.map((p) => ({ text: p.text, word_id: p.word_id, word_form_id: p.word_form_id, role: p.role })),
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  if (isLoading) return <p className="text-sm text-slate-500">Загрузка…</p>;
  if (loadError || !dictionary) return <p className="text-sm text-red-600">{loadError ?? "Язык не найден"}</p>;

  return (
    <div className="mx-auto max-w-3xl">
      <nav className="mb-4 flex flex-wrap items-center gap-1 text-sm text-slate-500">
        <Link to="/dictionaries" className="text-indigo-600 hover:underline">
          Языки
        </Link>
        <span>→</span>
        <span className="text-slate-700" translate="no">
          {dictionary.name} · Мини-фразы
        </span>
      </nav>
      <LanguageSectionTabs dictionaryId={dictionaryId} active="mini-phrases" />

      <div className="mb-6 flex items-center justify-between gap-4">
        <div>
          <h1 className="text-[26px] font-bold tracking-tight text-slate-900">Мини-фразы</h1>
          <p className="text-sm text-slate-500">
            {items.length} шт. · Шаблоны и очки —{" "}
            <Link to="/mini-phrase-templates" className="text-indigo-600 hover:underline">
              здесь
            </Link>
          </p>
        </div>
        <div className="flex shrink-0 flex-wrap justify-end gap-2">
          <button
            onClick={fillStarter}
            disabled={isFilling}
            className="rounded-md bg-[var(--fill)] px-4 py-2 text-sm font-medium text-slate-800 hover:bg-[var(--fill-strong)] disabled:opacity-50"
          >
            {isFilling ? "Заполнение…" : "Заполнить стартовым набором"}
          </button>
          <button
            onClick={() => setDraft({ ...EMPTY, template_id: templates[0]?.id ?? null })}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
          >
            + Мини-фраза
          </button>
        </div>
      </div>

      {report && (
        <div className="card mb-6 p-4 text-sm text-slate-700">
          <div className="mb-2 flex items-start justify-between gap-3">
            <p className="font-medium text-slate-900">
              Создано: {report.created.length} · уже были: {report.already.length} · пропущено: {report.skipped.length}
              {report.forms_added.length > 0 && ` · добавлено форм слов: ${report.forms_added.length}`}
            </p>
            <button onClick={() => setReport(null)} className="text-slate-400 hover:text-slate-700">
              ✕
            </button>
          </div>
          {report.skipped.length > 0 && (
            <>
              <p className="mb-1 text-slate-500">
                Пропущены — в словаре нет слов (добавьте их и нажмите кнопку ещё раз):
              </p>
              <ul className="max-h-48 list-disc overflow-auto pl-5 text-slate-600" translate="no">
                {report.skipped.map((s) => (
                  <li key={s.text}>
                    {s.text} — нет: {s.missing_words.join(", ")}
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      )}

      {draft && (
        <Editor
          dictionaryId={dictionaryId}
          draft={draft}
          setDraft={setDraft}
          templates={templates}
          roles={roles}
          words={words}
          language={dictionary.language}
          onSaved={() => {
            setDraft(null);
            reload();
          }}
        />
      )}

      {items.length === 0 ? (
        <p className="text-sm text-slate-500">Пока нет мини-фраз</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {items.map((mp) => (
            <li key={mp.id} className="card flex flex-wrap items-start justify-between gap-3 p-4">
              <div className="min-w-0 flex-1" translate="no">
                <p className="font-serif text-[17px] font-medium text-slate-900">
                  {mp.text}
                  {!mp.enabled && <span className="ml-2 font-sans text-xs text-slate-400">выключена</span>}
                </p>
                <p className="font-serif text-[15px] text-slate-600">{mp.translation_tg}</p>
                <div className="mt-2 flex flex-wrap items-center gap-1.5">
                  {mp.parts.map((p, i) => (
                    <span key={p.position} className="inline-flex items-center gap-1">
                      {i > 0 && <span className="text-slate-400">+</span>}
                      <span className="rounded-full bg-[var(--fill)] px-2.5 py-0.5 text-xs text-slate-700">
                        {p.text}
                        <span className="text-slate-400">
                          {" "}
                          · {p.word}
                          {(p.role ?? p.word_role) && ` · ${roleLabel[(p.role ?? p.word_role)!] ?? ""}`}
                        </span>
                      </span>
                    </span>
                  ))}
                </div>
                <p className="mt-1 text-xs text-slate-400">Шаблон: {mp.template_name ?? "стандартный"}</p>
              </div>
              <div className="flex shrink-0 items-center gap-4">
                <button onClick={() => edit(mp)} className="text-sm font-medium text-indigo-600 hover:underline">
                  Редактировать
                </button>
                <button onClick={() => remove(mp)} className="text-sm text-slate-400 hover:text-red-600">
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

function Editor({
  dictionaryId,
  draft,
  setDraft,
  templates,
  roles,
  words,
  language,
  onSaved,
}: {
  dictionaryId: number;
  draft: Draft;
  setDraft: (d: Draft | null) => void;
  templates: MiniPhraseTemplate[];
  roles: MiniPhraseRole[];
  words: Word[];
  language: string;
  onSaved: () => void;
}) {
  const [error, setError] = useState<string | null>(null);
  const [isBusy, setIsBusy] = useState(false);
  const wordById = useMemo(() => new Map(words.map((w) => [w.id, w])), [words]);
  const sortedWords = useMemo(() => [...words].sort((a, b) => a.word.localeCompare(b.word)), [words]);

  async function split() {
    if (!draft.text.trim()) return;
    setError(null);
    setIsBusy(true);
    try {
      const parts = await suggestMiniPhraseParts(dictionaryId, draft.text);
      setDraft({
        ...draft,
        parts: parts.map((p) => ({ text: p.text, word_id: p.word_id, word_form_id: p.word_form_id, role: null })),
      });
      if (parts.some((p) => p.word_id == null)) {
        setError("Не для всех частей нашлось слово в словаре — выберите вручную");
      }
    } catch (e) {
      setError(errorText(e, "Не удалось разбить фразу"));
    } finally {
      setIsBusy(false);
    }
  }

  function setPart(i: number, patch: Partial<PartDraft>) {
    setDraft({ ...draft, parts: draft.parts.map((p, j) => (j === i ? { ...p, ...patch } : p)) });
  }

  async function save() {
    setError(null);
    if (draft.parts.length === 0 || draft.parts.some((p) => p.word_id == null)) {
      setError("У каждой части должно быть слово из словаря");
      return;
    }
    const input: MiniPhraseInput = {
      template_id: draft.template_id,
      text: draft.text,
      translation_tg: draft.translation_tg,
      translation_uz: draft.translation_uz || null,
      translation_en: draft.translation_en || null,
      enabled: draft.enabled,
      parts: draft.parts.map((p) => ({ text: p.text, word_id: p.word_id!, word_form_id: p.word_form_id, role: p.role })),
    };
    setIsBusy(true);
    try {
      if (draft.id === null) await createMiniPhrase(dictionaryId, input);
      else await updateMiniPhrase(draft.id, input);
      onSaved();
    } catch (e) {
      setError(errorText(e, "Не удалось сохранить"));
    } finally {
      setIsBusy(false);
    }
  }

  const input = (key: "translation_tg" | "translation_uz" | "translation_en", label: string) => (
    <label className="block text-sm text-slate-700">
      <span className="mb-1 block text-xs text-slate-500">{label}</span>
      <input className="field w-full px-3 py-2 text-sm" value={draft[key]} onChange={(e) => setDraft({ ...draft, [key]: e.target.value })} />
    </label>
  );

  return (
    <div className="card mb-6 flex flex-col gap-4 p-4">
      <h2 className="text-lg font-semibold text-slate-900">{draft.id === null ? "Новая мини-фраза" : "Мини-фраза"}</h2>
      <div className="flex flex-wrap items-end gap-3">
        <label className="min-w-0 flex-1 text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Фраза — правильный вариант</span>
          <input
            className="field w-full px-3 py-2 text-sm"
            placeholder="Я покушал"
            value={draft.text}
            onChange={(e) => setDraft({ ...draft, text: e.target.value })}
          />
        </label>
        <button
          onClick={split}
          disabled={isBusy || !draft.text.trim()}
          className="rounded-md bg-[var(--fill)] px-4 py-2 text-sm font-medium text-slate-800 hover:bg-[var(--fill-strong)] disabled:opacity-50"
        >
          Разбить на части
        </button>
      </div>

      {draft.parts.length > 0 && (
        <div className="flex flex-col gap-2">
          <p className="text-xs text-slate-500">Части по порядку — проверьте слово, форму и роль</p>
          {draft.parts.map((p, i) => {
            const word = p.word_id != null ? wordById.get(p.word_id) : undefined;
            const forms = word?.forms.filter((f) => f.language === language) ?? [];
            return (
              <div key={i} className="flex flex-wrap items-center gap-2 rounded-lg bg-[var(--fill)] p-2">
                <span className="w-6 text-center text-xs font-semibold text-slate-500">{i + 1}</span>
                <span className="min-w-[80px] font-medium text-slate-900" translate="no">
                  {p.text}
                </span>
                <select
                  className="field px-2 py-1.5 text-sm"
                  value={p.word_id ?? ""}
                  onChange={(e) => setPart(i, { word_id: e.target.value ? Number(e.target.value) : null, word_form_id: null })}
                >
                  <option value="">— слово —</option>
                  {sortedWords.map((w) => (
                    <option key={w.id} value={w.id}>
                      {w.word}
                      {w.translation ? ` — ${w.translation}` : ""}
                    </option>
                  ))}
                </select>
                <select
                  className="field px-2 py-1.5 text-sm"
                  value={p.word_form_id ?? ""}
                  onChange={(e) => setPart(i, { word_form_id: e.target.value ? Number(e.target.value) : null })}
                  disabled={forms.length === 0}
                >
                  <option value="">основная форма</option>
                  {forms.map((f) => (
                    <option key={f.id} value={f.id}>
                      {f.text}
                    </option>
                  ))}
                </select>
                <select
                  className="field px-2 py-1.5 text-sm"
                  value={p.role ?? ""}
                  onChange={(e) => setPart(i, { role: e.target.value || null })}
                >
                  <option value="">
                    роль из слова{word?.role ? `: ${roles.find((r) => r.id === word.role)?.label ?? word.role}` : " (не задана)"}
                  </option>
                  {roles.map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.label}
                    </option>
                  ))}
                </select>
              </div>
            );
          })}
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-3">
        {input("translation_tg", "Перевод — таджикский *")}
        {input("translation_uz", "Перевод — узбекский")}
        {input("translation_en", "Перевод — английский")}
      </div>

      <div className="flex flex-wrap items-end gap-5">
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Шаблон</span>
          <select
            className="field px-3 py-2 text-sm"
            value={draft.template_id ?? ""}
            onChange={(e) => setDraft({ ...draft, template_id: e.target.value ? Number(e.target.value) : null })}
          >
            <option value="">Стандартное объяснение</option>
            {templates.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={draft.enabled} onChange={(e) => setDraft({ ...draft, enabled: e.target.checked })} />
          Включена
        </label>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}
      <div className="flex gap-3">
        <button
          onClick={save}
          disabled={isBusy || !draft.text.trim() || !draft.translation_tg.trim()}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {isBusy ? "Сохранение…" : "Сохранить"}
        </button>
        <button onClick={() => setDraft(null)} className="rounded-md px-4 py-2 text-sm text-slate-600 hover:bg-[var(--fill)]">
          Отмена
        </button>
      </div>
    </div>
  );
}

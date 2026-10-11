import axios from "axios";
import { useEffect, useState } from "react";
import {
  addMissingWords,
  generateMiniPhrases,
  getMiniPhraseAnalysis,
  listCategories,
  rephraseMiniPhrases,
  saveGeneratedMiniPhrases,
  type GeneratedMiniPhrase,
  type MiniPhraseAnalysis,
} from "../api/endpoints";
import type { Category } from "../types";

function errorText(e: unknown, fallback: string): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return fallback;
}

const ROLE_LABEL: Record<string, string> = {
  pronoun: "кто",
  verb: "действие",
  noun: "что",
  adjective: "какой",
  adverb: "как",
  preposition: "предлог",
  number: "сколько",
  other: "слово",
};

const ROLE_CLASS: Record<string, string> = {
  pronoun: "bg-violet-100 text-violet-800",
  verb: "bg-orange-100 text-orange-800",
  noun: "bg-teal-100 text-teal-800",
  adjective: "bg-pink-100 text-pink-800",
  adverb: "bg-blue-100 text-blue-800",
};

const SOURCE_LABEL: Record<string, string> = { mini: "мини-фраза", phrase: "«Мои фразы»", batch: "эта пачка" };

/** AI generation of mini-phrases: script analysis and «не хватает слов»
 * (no tokens), then a preview to check, rephrase too-similar ones and save
 * what the admin picks. Nothing is saved without the admin's choice. */
export function MiniPhraseGenerator({ dictionaryId, onSaved }: { dictionaryId: number; onSaved: () => void }) {
  const [analysis, setAnalysis] = useState<MiniPhraseAnalysis | null>(null);
  const [chosenWords, setChosenWords] = useState<Set<string>>(new Set());
  const [count, setCount] = useState(20);
  const [categories, setCategories] = useState<Category[]>([]);
  const [categoryId, setCategoryId] = useState<number | null>(null);
  const [items, setItems] = useState<GeneratedMiniPhrase[]>([]);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tokens, setTokens] = useState(0);

  async function loadAnalysis() {
    try {
      setAnalysis(await getMiniPhraseAnalysis(dictionaryId));
    } catch (e) {
      setError(errorText(e, "Не удалось выполнить анализ"));
    }
  }

  useEffect(() => {
    listCategories(dictionaryId).then(setCategories).catch(() => setCategories([]));
    loadAnalysis();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dictionaryId]);

  async function run<T>(label: string, fn: () => Promise<T>): Promise<T | undefined> {
    setBusy(label);
    setError(null);
    setMessage(null);
    try {
      return await fn();
    } catch (e) {
      setError(errorText(e, "Не получилось, попробуйте ещё раз"));
      return undefined;
    } finally {
      setBusy(null);
    }
  }

  async function addWords() {
    const res = await run("words", () => addMissingWords(dictionaryId, [...chosenWords]));
    if (!res) return;
    setTokens((t) => t + res.tokens);
    setChosenWords(new Set());
    setMessage(
      `Добавлено слов: ${res.created.length}` +
        (res.updated.length ? ` · дополнены формами: ${res.updated.length}` : "") +
        ` · токенов: ${res.tokens}`,
    );
    loadAnalysis();
  }

  function accept(newItems: GeneratedMiniPhrase[], replaceKeys?: Set<string>) {
    setItems((prev) => {
      const kept = replaceKeys ? prev.filter((i) => !replaceKeys.has(i.key)) : prev;
      return [...kept, ...newItems.map((i) => ({ ...i, key: `${i.key}-${Math.random().toString(36).slice(2, 7)}` }))];
    });
    setPicked((prev) => {
      const next = new Set(replaceKeys ? [...prev].filter((k) => !replaceKeys.has(k)) : prev);
      return next;
    });
  }

  useEffect(() => {
    // Valid and not too similar are picked by default.
    setPicked((prev) => {
      const next = new Set(prev);
      for (const i of items) if (i.valid && !i.too_similar && !next.has(i.key)) next.add(i.key);
      return next;
    });
  }, [items]);

  async function generate() {
    const res = await run("generate", () => generateMiniPhrases(dictionaryId, count, categoryId));
    if (!res) return;
    setTokens((t) => t + res.tokens);
    accept(res.items);
  }

  async function rephrase() {
    const targets = items.filter((i) => i.too_similar && picked.has(i.key));
    if (targets.length === 0) return;
    const res = await run("rephrase", () => rephraseMiniPhrases(dictionaryId, targets, categoryId));
    if (!res) return;
    setTokens((t) => t + res.tokens);
    accept(res.items, new Set(targets.map((t) => t.key)));
  }

  async function save() {
    const chosen = items.filter((i) => i.valid && picked.has(i.key));
    const res = await run("save", () => saveGeneratedMiniPhrases(dictionaryId, chosen));
    if (!res) return;
    setItems((prev) => prev.filter((i) => !picked.has(i.key)));
    setPicked(new Set());
    setMessage(
      `Сохранено: ${res.created.length}` +
        (res.forms_added.length ? ` · добавлено форм: ${res.forms_added.length}` : "") +
        (res.templates_created.length ? ` · новых шаблонов: ${res.templates_created.length}` : "") +
        (res.skipped.length ? ` · пропущено: ${res.skipped.length}` : ""),
    );
    onSaved();
    loadAnalysis();
  }

  function toggle(set: Set<string>, key: string, update: (s: Set<string>) => void) {
    const next = new Set(set);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    update(next);
  }

  const similar = items.filter((i) => i.valid && i.too_similar);
  const normal = items.filter((i) => i.valid && !i.too_similar);
  const invalid = items.filter((i) => !i.valid);
  const toSave = items.filter((i) => i.valid && picked.has(i.key)).length;
  const toRephrase = similar.filter((i) => picked.has(i.key)).length;

  return (
    <div className="card mb-6 flex flex-col gap-5 p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-lg font-semibold text-slate-900">ИИ-генерация мини-фраз</h2>
        {tokens > 0 && <span className="text-xs text-slate-500">потрачено токенов: {tokens}</span>}
      </div>

      {analysis && (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-slate-600">
            Слов: <b>{analysis.words}</b> · мини-фраз сейчас: <b>{analysis.existing_mini_phrases}</b> · возможных
            сочетаний: <b>{analysis.possible_combinations}</b>
            {analysis.phrases_short_of_words > 0 && <> · фраз «Мои фразы» без нужных слов: <b>{analysis.phrases_short_of_words}</b></>}
          </p>
          {analysis.missing_words.length > 0 && (
            <div className="rounded-lg bg-[var(--fill)] p-3">
              <p className="mb-2 text-sm font-medium text-slate-800">Не хватает слов</p>
              <div className="flex max-h-44 flex-wrap gap-2 overflow-auto" translate="no">
                {analysis.missing_words.map((m) => {
                  const on = chosenWords.has(m.text);
                  return (
                    <button
                      key={m.text}
                      type="button"
                      onClick={() => toggle(chosenWords, m.text, setChosenWords)}
                      className={`rounded-full px-3 py-1 text-sm transition-colors ${
                        on ? "bg-indigo-600 text-white" : "bg-[var(--card)] text-slate-700 hover:bg-indigo-50"
                      }`}
                      title={m.source === "phrases" ? `встречается в ${m.appears} фразах` : "ключевое слово для мини-фраз"}
                    >
                      {m.text}{" "}
                      <span className={on ? "text-indigo-100" : "text-slate-400"}>
                        {m.source === "phrases"
                          ? m.unlocks > 0
                            ? `откроет ${m.unlocks} фраз`
                            : `в ${m.appears} фразах`
                          : `+${m.unlocks} сочет.`}
                      </span>
                    </button>
                  );
                })}
              </div>
              <button
                onClick={addWords}
                disabled={chosenWords.size === 0 || busy !== null}
                className="mt-3 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
              >
                {busy === "words" ? "ИИ создаёт карточки…" : `Добавить слова полной карточкой (${chosenWords.size})`}
              </button>
              <p className="mt-1 text-xs text-slate-500">
                ИИ создаст карточку: переводы, транскрипция, роль, категория, важность и все формы слова.
              </p>
            </div>
          )}
        </div>
      )}

      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Сколько фраз (10–50)</span>
          <input
            type="number"
            min={10}
            max={50}
            className="field w-24 px-3 py-2 text-sm"
            value={count}
            onChange={(e) => setCount(Math.max(10, Math.min(50, Number(e.target.value) || 20)))}
          />
        </label>
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Тема</span>
          <select
            className="field px-3 py-2 text-sm"
            value={categoryId ?? ""}
            onChange={(e) => setCategoryId(e.target.value ? Number(e.target.value) : null)}
          >
            <option value="">Все темы</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
        <button
          onClick={generate}
          disabled={busy !== null}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {busy === "generate" ? "ИИ составляет фразы… (до минуты)" : "Сгенерировать"}
        </button>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {message && <p className="text-sm text-emerald-700">{message}</p>}

      {similar.length > 0 && (
        <Section
          title={`Слишком похожие (≥60%) — ${similar.length}`}
          hint="Отметьте и отправьте на перефразирование, или уберите галочку, чтобы не добавлять."
          tone="amber"
        >
          {similar.map((i) => (
            <Card key={i.key} item={i} checked={picked.has(i.key)} onToggle={() => toggle(picked, i.key, setPicked)} />
          ))}
          <button
            onClick={rephrase}
            disabled={toRephrase === 0 || busy !== null}
            className="self-start rounded-md bg-amber-500 px-4 py-2 text-sm font-medium text-white hover:bg-amber-600 disabled:opacity-50"
          >
            {busy === "rephrase" ? "ИИ перефразирует…" : `Отправить на перефразирование (${toRephrase})`}
          </button>
        </Section>
      )}

      {normal.length > 0 && (
        <Section title={`Готовы к добавлению — ${normal.length}`}>
          {normal.map((i) => (
            <Card key={i.key} item={i} checked={picked.has(i.key)} onToggle={() => toggle(picked, i.key, setPicked)} />
          ))}
        </Section>
      )}

      {invalid.length > 0 && (
        <Section title={`Не прошли проверку — ${invalid.length}`}>
          {invalid.map((i) => (
            <Card key={i.key} item={i} checked={false} onToggle={() => {}} />
          ))}
        </Section>
      )}

      {items.some((i) => i.valid) && (
        <div className="flex flex-wrap gap-3">
          <button
            onClick={save}
            disabled={toSave === 0 || busy !== null}
            className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-50"
          >
            {busy === "save" ? "Сохранение…" : `Сохранить выбранные (${toSave})`}
          </button>
          <button
            onClick={() => {
              setItems([]);
              setPicked(new Set());
            }}
            className="rounded-md px-4 py-2 text-sm text-slate-600 hover:bg-[var(--fill)]"
          >
            Очистить
          </button>
        </div>
      )}
    </div>
  );
}

function Section({
  title,
  hint,
  tone,
  children,
}: {
  title: string;
  hint?: string;
  tone?: "amber";
  children: React.ReactNode;
}) {
  return (
    <div className={`flex flex-col gap-2 rounded-lg p-3 ${tone === "amber" ? "bg-amber-50" : "bg-[var(--fill)]"}`}>
      <p className="text-sm font-semibold text-slate-800">{title}</p>
      {hint && <p className="-mt-1 text-xs text-slate-500">{hint}</p>}
      {children}
    </div>
  );
}

function Card({ item, checked, onToggle }: { item: GeneratedMiniPhrase; checked: boolean; onToggle: () => void }) {
  return (
    <label
      className={`flex cursor-pointer items-start gap-3 rounded-xl bg-[var(--card)] p-3.5 ${item.valid ? "" : "cursor-default opacity-60"}`}
      translate="no"
    >
      <input
        type="checkbox"
        className="switch mt-0.5"
        aria-label="Добавить эту мини-фразу"
        checked={checked}
        disabled={!item.valid}
        onChange={onToggle}
      />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-2">
          <span className="text-[16px] font-semibold text-slate-900">{item.text}</span>
          <span className="text-sm text-slate-500">{item.translation_tg}</span>
          {item.situation && <span className="text-xs text-slate-400">· {item.situation}</span>}
          {item.usefulness != null && (
            <span className="text-xs text-amber-600" title="полезность для начинающего по оценке ИИ">
              {"★".repeat(Math.max(0, Math.min(5, item.usefulness)))}
            </span>
          )}
          {item.similarity > 0 && (
            <span
              className={`rounded-full px-2 py-0.5 text-xs ${
                item.too_similar ? "bg-amber-200 text-amber-900" : "bg-slate-100 text-slate-500"
              }`}
              title={item.similar_to ? `похоже на «${item.similar_to}» (${SOURCE_LABEL[item.similar_source ?? ""] ?? ""})` : ""}
            >
              {item.similarity}%{item.similar_to ? ` ≈ «${item.similar_to}»` : ""}
            </span>
          )}
        </div>
        <div className="mt-1.5 flex flex-wrap items-center gap-1">
          {item.parts.map((p, idx) => (
            <span key={idx} className="inline-flex items-center gap-1">
              {idx > 0 && <span className="text-slate-400">+</span>}
              <span className={`rounded-full px-2 py-0.5 text-xs ${ROLE_CLASS[p.role] ?? "bg-slate-100 text-slate-700"}`}>
                {p.text} · {ROLE_LABEL[p.role] ?? p.role}
                {p.new_form && <b> · новая форма слова «{p.word}»</b>}
              </span>
            </span>
          ))}
        </div>
        <p className="mt-1.5 text-xs text-slate-500">
          Шаблон: {item.template_name || "—"}
          {item.template_name && !item.template_exists && " (будет создан)"}
          {item.translation_uz && ` · uz: ${item.translation_uz}`}
          {item.translation_en && ` · en: ${item.translation_en}`}
        </p>
        {item.reason && <p className="mt-1 text-xs font-medium text-red-600">{item.reason}</p>}
      </div>
    </label>
  );
}

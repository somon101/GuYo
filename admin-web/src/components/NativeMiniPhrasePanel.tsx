import { useState } from "react";
import {
  manualCheck,
  manualTemplate,
  nativeGenerate,
  nativeSave,
  type ManualCheck,
  type ManualTemplate,
  type NativeItem,
} from "../api/endpoints";
import { errorText } from "../api/errors";
import { PerLanguageFields } from "./PerLanguageFields";

/** Мини-фразы ОДНОГО языка: генерация сразу на нём и своя фраза вручную.
 * Слова проверяются по словарю этого языка, шаблон — только этого языка. */
export function NativeMiniPhrasePanel({
  dictionaryId,
  language,
  languageName,
  onSaved,
}: {
  dictionaryId: number;
  language: string;
  languageName: string;
  onSaved: () => void;
}) {
  const [mode, setMode] = useState<"none" | "generate" | "manual">("none");
  return (
    <div className="card mb-6 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="mr-2 text-sm font-semibold text-slate-800">Новые мини-фразы — {languageName}</span>
        <button
          onClick={() => setMode(mode === "generate" ? "none" : "generate")}
          className={`rounded-full px-3 py-1.5 text-sm font-medium ${mode === "generate" ? "bg-indigo-600 text-white" : "btn-tinted"}`}
        >
          Сгенерировать
        </button>
        <button
          onClick={() => setMode(mode === "manual" ? "none" : "manual")}
          className={`rounded-full px-3 py-1.5 text-sm font-medium ${mode === "manual" ? "bg-indigo-600 text-white" : "btn-tinted"}`}
        >
          Написать свою
        </button>
      </div>
      {mode === "generate" && (
        <GeneratePanel dictionaryId={dictionaryId} language={language} onSaved={onSaved} />
      )}
      {mode === "manual" && (
        <ManualPanel
          dictionaryId={dictionaryId}
          language={language}
          onSaved={() => {
            setMode("none");
            onSaved();
          }}
        />
      )}
    </div>
  );
}

function GeneratePanel({ dictionaryId, language, onSaved }: { dictionaryId: number; language: string; onSaved: () => void }) {
  const [count, setCount] = useState(10);
  const [topic, setTopic] = useState("");
  const [items, setItems] = useState<NativeItem[]>([]);
  const [picked, setPicked] = useState<Set<number>>(new Set());
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function generate() {
    setBusy(true);
    setMessage(null);
    try {
      const r = await nativeGenerate(dictionaryId, language, count, topic);
      setItems(r.items);
      setPicked(new Set(r.items.map((it, i) => (it.valid ? i : -1)).filter((i) => i >= 0)));
      if (r.reason) setMessage(r.reason);
    } catch (e) {
      setMessage(errorText(e, "Не удалось сгенерировать"));
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    setBusy(true);
    try {
      const r = await nativeSave(dictionaryId, language, items.filter((_, i) => picked.has(i)));
      setMessage(
        `Сохранено: ${r.created.length}` +
          (r.skipped.length ? ` · пропущено: ${r.skipped.map((s) => `${s.text} (${s.reason})`).join("; ")}` : ""),
      );
      setItems([]);
      onSaved();
    } catch (e) {
      setMessage(errorText(e, "Не удалось сохранить"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-4 flex flex-col gap-3">
      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Сколько</span>
          <select className="field px-3 py-2 text-sm" value={count} onChange={(e) => setCount(Number(e.target.value))}>
            {[5, 10, 15, 20, 25].map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </label>
        <label className="flex-1 text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Тема (необязательно)</span>
          <input className="field w-full px-3 py-2 text-sm" value={topic} onChange={(e) => setTopic(e.target.value)} />
        </label>
        <button
          onClick={generate}
          disabled={busy}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {busy ? "Генерируем…" : "Сгенерировать"}
        </button>
      </div>
      {message && <p className="text-sm text-slate-600">{message}</p>}
      {items.length > 0 && (
        <>
          <ul className="flex flex-col gap-2">
            {items.map((it, i) => (
              <li key={i} className={`rounded-lg border p-3 ${it.valid ? "border-slate-200" : "border-red-200 bg-red-50"}`}>
                <label className="flex items-start gap-2">
                  <input
                    type="checkbox"
                    disabled={!it.valid}
                    checked={picked.has(i)}
                    onChange={(e) => {
                      const next = new Set(picked);
                      if (e.target.checked) next.add(i);
                      else next.delete(i);
                      setPicked(next);
                    }}
                    className="mt-1"
                  />
                  <span className="min-w-0" translate="no">
                    <span className="font-medium text-slate-900">{it.text}</span>
                    <span className="ml-2 text-xs text-slate-500">
                      {it.parts.map((p) => p.text).join(" + ")} · шаблон: {it.template_name}
                      {it.template_name && !it.template_exists && " (будет создан)"}
                    </span>
                    <span className="block text-xs text-slate-500">
                      {Object.entries(it.translations)
                        .map(([code, text]) => `${code}: ${text}`)
                        .join(" · ")}
                    </span>
                    {it.reason && <span className="block text-xs text-red-600">{it.reason}</span>}
                  </span>
                </label>
              </li>
            ))}
          </ul>
          <button
            onClick={save}
            disabled={busy || picked.size === 0}
            className="self-start rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            Сохранить выбранные ({picked.size})
          </button>
        </>
      )}
    </div>
  );
}

function ManualPanel({ dictionaryId, language, onSaved }: { dictionaryId: number; language: string; onSaved: () => void }) {
  const [text, setText] = useState("");
  const [check, setCheck] = useState<ManualCheck | null>(null);
  const [tpl, setTpl] = useState<ManualTemplate | null>(null);
  const [translations, setTranslations] = useState<Record<string, string>>({});
  const [explanations, setExplanations] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (e) {
      setError(errorText(e, "Не удалось выполнить"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-4 flex flex-col gap-3">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex-1 text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Фраза на этом языке</span>
          <input
            className="field w-full px-3 py-2 text-sm"
            value={text}
            onChange={(e) => {
              setText(e.target.value);
              setCheck(null);
              setTpl(null);
            }}
          />
        </label>
        <button
          onClick={() => run(async () => setCheck(await manualCheck(dictionaryId, language, text)))}
          disabled={busy || !text.trim()}
          className="btn-tinted rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Проверить слова
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
      {check && (
        <div className="rounded-lg bg-[var(--fill)] p-3 text-sm" translate="no">
          <p>
            Части:{" "}
            {check.parts.map((p, i) => (
              <span key={i} className="mr-2 rounded bg-white px-1.5 py-0.5">
                {p.text}
                {p.base && p.base.toLowerCase() !== p.text.toLowerCase() && (
                  <span className="text-slate-400"> ({p.base})</span>
                )}
                <span className="ml-1 text-xs text-slate-400">{p.role}</span>
              </span>
            ))}
          </p>
          {check.missing.length > 0 && (
            <p className="mt-1 text-red-600">Нет в словаре этого языка: {check.missing.join(", ")}</p>
          )}
          {check.duplicate && <p className="mt-1 text-red-600">Такая мини-фраза уже есть</p>}
          {check.ok && !tpl && (
            <button
              onClick={() =>
                run(async () => {
                  const r = await manualTemplate(dictionaryId, language, check.text, check.parts);
                  setTpl(r);
                  setTranslations(r.translations);
                  setExplanations(r.template.explanations ?? {});
                })
              }
              disabled={busy}
              className="mt-2 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
            >
              {busy ? "ИИ подбирает шаблон…" : "Подобрать шаблон (ИИ)"}
            </button>
          )}
        </div>
      )}
      {check?.ok && tpl && (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-slate-700">
            Шаблон: <b>{tpl.template.name}</b>{" "}
            {tpl.template.new ? (
              <span className="text-amber-700">— новый, будет создан для этого языка</span>
            ) : (
              <span className="text-emerald-700">— уже есть</span>
            )}
            {tpl.why && <span className="block text-xs text-slate-500">{tpl.why}</span>}
          </p>
          {tpl.template.new && (
            <div>
              <p className="mb-2 text-xs text-slate-500">Объяснение нового шаблона</p>
              <PerLanguageFields
                multiline
                values={explanations}
                onChange={setExplanations}
                label={(l) => `Для читающих на языке: ${l.name}`}
              />
            </div>
          )}
          <div>
            <p className="mb-2 text-xs text-slate-500">Подсказки-переводы</p>
            <PerLanguageFields
              values={translations}
              onChange={setTranslations}
              label={(l) => `Перевод — ${l.name}`}
              exclude={language}
            />
          </div>
          <button
            onClick={() =>
              run(async () => {
                const r = await nativeSave(dictionaryId, language, [
                  {
                    text: check.text,
                    parts: check.parts,
                    translations,
                    template_name: tpl.template.name,
                    template_id: tpl.template.id,
                    explanations: tpl.template.new ? explanations : undefined,
                  },
                ]);
                if (r.created.length) onSaved();
                else setError(r.skipped.map((s) => s.reason).join("; ") || "Не сохранено");
              })
            }
            disabled={busy}
            className="self-start rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            Сохранить мини-фразу
          </button>
        </div>
      )}
    </div>
  );
}

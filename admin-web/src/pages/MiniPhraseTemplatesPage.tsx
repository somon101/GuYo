import axios from "axios";
import { useEffect, useState } from "react";
import {
  createMiniPhraseTemplate,
  deleteMiniPhraseTemplate,
  getMiniPhraseSettings,
  listDictionaries,
  listMiniPhrases,
  listMiniPhraseTemplates,
  updateMiniPhraseSettings,
  updateMiniPhraseTemplate,
  type MiniPhraseTemplateInput,
} from "../api/endpoints";
import { MiniPhrasePhonePreview } from "../components/MiniPhrasePhonePreview";
import { PerLanguageFields } from "../components/PerLanguageFields";
import type {
  Dictionary,
  MiniPhrase,
  MiniPhraseSettings,
  MiniPhraseTemplate,
} from "../types";

function errorText(e: unknown, fallback: string): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string")
    return e.response.data.detail;
  return fallback;
}

const PLACEHOLDERS: [string, string][] = [
  ["{phrase}", "вся мини-фраза («Я покушал»)"],
  ["{translation}", "перевод фразы на язык ученика"],
  ["{parts}", "все части по порядку через «+»"],
  ["{1}, {2}…", "часть по номеру"],
  ["{1.tr}", "перевод слова этой части"],
  ["{pronoun}, {verb}, {noun}…", "первая часть с этой ролью"],
  ["{pronoun.tr}…", "перевод слова этой роли"],
];

const EMPTY: MiniPhraseTemplateInput = {
  name: "",
  kind: "ordered_parts",
  explanation_ru: "",
  explanation_tg: "",
  explanation_uz: "",
  distractor_count: 2,
  enabled: true,
};

/** Templates explain whole groups of mini-phrases at once (one text with
 * placeholders per interface language), plus the mini-phrase settings. */
export function MiniPhraseTemplatesPage() {
  const [templates, setTemplates] = useState<MiniPhraseTemplate[]>([]);
  const [settings, setSettings] = useState<MiniPhraseSettings | null>(null);
  const [editing, setEditing] = useState<{
    id: number | null;
    input: MiniPhraseTemplateInput;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [dictionaryId, setDictionaryId] = useState<number | null>(null);
  const [phrases, setPhrases] = useState<MiniPhrase[]>([]);
  const [openId, setOpenId] = useState<number | "none" | null>(null);
  const [previewId, setPreviewId] = useState<number | null>(null);

  useEffect(() => {
    listDictionaries()
      .then((list) => {
        setDictionaries(list);
        const ru = list.find((d) => d.language === "ru") ?? list[0];
        if (ru) setDictionaryId(ru.id);
      })
      .catch(() => setDictionaries([]));
  }, []);

  useEffect(() => {
    if (dictionaryId == null) return;
    listMiniPhrases(dictionaryId)
      .then(setPhrases)
      .catch(() => setPhrases([]));
  }, [dictionaryId]);

  const phrasesOf = (id: number | "none") =>
    phrases.filter((m) =>
      id === "none" ? m.template_id === null : m.template_id === id,
    );

  async function reload() {
    try {
      const [t, s] = await Promise.all([
        listMiniPhraseTemplates(),
        getMiniPhraseSettings(),
      ]);
      setTemplates(t);
      setSettings(s);
    } catch {
      setError("Не удалось загрузить шаблоны");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function remove(t: MiniPhraseTemplate) {
    if (!confirm(`Удалить шаблон «${t.name}»?`)) return;
    try {
      await deleteMiniPhraseTemplate(t.id);
      reload();
    } catch (e) {
      alert(errorText(e, "Не удалось удалить"));
    }
  }

  if (isLoading) return <p className="text-sm text-slate-500">Загрузка…</p>;

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex items-center justify-between gap-4">
        <div>
          <h1 className="text-[26px] font-bold tracking-tight text-slate-900">
            Мини-фразы
          </h1>
          <p className="text-sm text-slate-500">
            Шаблоны объяснений и настройки. Нажмите на шаблон — увидите его
            фразы.
          </p>
        </div>
        <button
          onClick={() => setEditing({ id: null, input: { ...EMPTY } })}
          className="shrink-0 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + Шаблон
        </button>
      </div>

      {error && <p className="mb-4 text-sm text-red-600">{error}</p>}

      {settings && <SettingsCard settings={settings} onSaved={setSettings} />}

      {editing && (
        <TemplateEditor
          initial={editing.input}
          isNew={editing.id === null}
          onCancel={() => setEditing(null)}
          onSave={async (input) => {
            if (editing.id === null) await createMiniPhraseTemplate(input);
            else await updateMiniPhraseTemplate(editing.id, input);
            setEditing(null);
            reload();
          }}
        />
      )}

      {previewId !== null && (
        <MiniPhrasePhonePreview
          id={previewId}
          onClose={() => setPreviewId(null)}
        />
      )}

      <div className="mb-3 mt-8 flex flex-wrap items-end justify-between gap-3">
        <h2 className="text-lg font-semibold text-slate-900">
          {openId === null ? (
            "Шаблоны"
          ) : (
            <>
              <button
                onClick={() => setOpenId(null)}
                className="mr-2 text-sm font-medium text-indigo-600 hover:underline"
              >
                ← Все шаблоны
              </button>
              {openId === "none"
                ? "Стандартный"
                : templates.find((t) => t.id === openId)?.name}
            </>
          )}
        </h2>
        {dictionaries.length > 1 && (
          <label className="text-sm text-slate-700">
            <span className="mb-1 block text-xs text-slate-500">Язык</span>
            <select
              className="field px-3 py-2 text-sm"
              value={dictionaryId ?? ""}
              onChange={(e) => setDictionaryId(Number(e.target.value))}
            >
              {dictionaries.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>

      {openId === null ? (
        templates.length === 0 ? (
          <p className="text-sm text-slate-500">
            Шаблонов пока нет. Без шаблона используется стандартное объяснение.
          </p>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {[
              ...templates.map((t) => ({ t, key: t.id as number | "none" })),
              ...(phrasesOf("none").length
                ? [{ t: null, key: "none" as const }]
                : []),
            ].map(({ t, key }) => {
              const list = phrasesOf(key);
              return (
                <div
                  key={String(key)}
                  role="button"
                  tabIndex={0}
                  onClick={() => setOpenId(key)}
                  onKeyDown={(e) => e.key === "Enter" && setOpenId(key)}
                  className="card flex cursor-pointer flex-col gap-2 p-4 transition hover:ring-2 hover:ring-indigo-300"
                >
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-[16px] font-semibold text-slate-900">
                      {t ? t.name : "Стандартный"}
                      {t && !t.enabled && (
                        <span className="ml-2 text-xs font-normal text-slate-400">
                          выключен
                        </span>
                      )}
                    </span>
                    <span className="rounded-full bg-indigo-50 px-2.5 py-0.5 text-sm font-semibold text-indigo-700">
                      {list.length}
                    </span>
                  </div>
                  <span className="line-clamp-2 text-xs text-slate-500">
                    {t
                      ? t.explanation_ru || t.explanation_tg
                      : "Без шаблона — общее объяснение"}
                  </span>
                  <span
                    className="truncate text-sm text-slate-600"
                    translate="no"
                  >
                    {list.length
                      ? list
                          .slice(0, 4)
                          .map((m) => m.text)
                          .join(" · ") + (list.length > 4 ? " …" : "")
                      : "Фраз пока нет"}
                  </span>
                  {t && (
                    <div
                      className="mt-1 flex gap-4"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <button
                        onClick={() => {
                          const { id, usage_count, ...input } = t;
                          void usage_count;
                          setEditing({ id, input });
                          window.scrollTo({ top: 0, behavior: "smooth" });
                        }}
                        className="text-sm font-medium text-indigo-600 hover:underline"
                      >
                        Редактировать
                      </button>
                      <button
                        onClick={() => remove(t)}
                        className="text-sm text-slate-400 hover:text-red-600"
                      >
                        Удалить
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )
      ) : (
        <>
          <p className="mb-3 text-xs text-slate-500">
            Нажмите на фразу — покажу, как она выглядит в телефоне.
          </p>
          {phrasesOf(openId).length === 0 ? (
            <p className="text-sm text-slate-500">
              В этом языке фраз с этим шаблоном нет
            </p>
          ) : (
            <ul className="flex flex-col gap-2">
              {phrasesOf(openId).map((m) => (
                <li key={m.id}>
                  <button
                    onClick={() => setPreviewId(m.id)}
                    className="card flex w-full flex-wrap items-baseline gap-x-3 gap-y-1 p-3.5 text-left transition hover:ring-2 hover:ring-indigo-300"
                    translate="no"
                  >
                    <span className="text-[16px] font-semibold text-slate-900">
                      {m.text}
                    </span>
                    <span className="text-sm text-slate-500">
                      {m.translation_tg}
                    </span>
                    {!m.enabled && (
                      <span className="text-xs text-slate-400">выключена</span>
                    )}
                    <span className="ml-auto text-sm text-indigo-600">📱</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </div>
  );
}

function SettingsCard({
  settings,
  onSaved,
}: {
  settings: MiniPhraseSettings;
  onSaved: (s: MiniPhraseSettings) => void;
}) {
  const [draft, setDraft] = useState(settings);
  const [status, setStatus] = useState<string | null>(null);
  const dirty =
    draft.points_enabled !== settings.points_enabled ||
    draft.points_per_correct !== settings.points_per_correct ||
    draft.max_per_lesson !== settings.max_per_lesson;

  async function save() {
    try {
      onSaved(await updateMiniPhraseSettings(draft));
      setStatus("Сохранено");
    } catch (e) {
      setStatus(errorText(e, "Не удалось сохранить"));
    }
  }

  return (
    <div className="card p-4">
      <h2 className="mb-3 text-lg font-semibold text-slate-900">Настройки</h2>
      <div className="flex flex-wrap items-end gap-5">
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            checked={draft.points_enabled}
            onChange={(e) =>
              setDraft({ ...draft, points_enabled: e.target.checked })
            }
          />
          Очки за верную сборку
        </label>
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">
            Очков за мини-фразу (один раз)
          </span>
          <input
            type="number"
            min={0}
            max={1000}
            className="field w-28 px-3 py-2 text-sm"
            value={draft.points_per_correct}
            onChange={(e) =>
              setDraft({ ...draft, points_per_correct: Number(e.target.value) })
            }
          />
        </label>
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">
            Максимум на урок
          </span>
          <input
            type="number"
            min={0}
            max={10}
            className="field w-28 px-3 py-2 text-sm"
            value={draft.max_per_lesson}
            onChange={(e) =>
              setDraft({ ...draft, max_per_lesson: Number(e.target.value) })
            }
          />
        </label>
        <button
          onClick={save}
          disabled={!dirty}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          Сохранить
        </button>
        {status && <span className="text-sm text-slate-500">{status}</span>}
      </div>
    </div>
  );
}

function TemplateEditor({
  initial,
  isNew,
  onSave,
  onCancel,
}: {
  initial: MiniPhraseTemplateInput;
  isNew: boolean;
  onSave: (input: MiniPhraseTemplateInput) => Promise<void>;
  onCancel: () => void;
}) {
  // Texts live by language now; the old three fields fill in what is missing.
  const [input, setInput] = useState<MiniPhraseTemplateInput>(() => ({
    ...initial,
    explanations: {
      ...Object.fromEntries(
        (["ru", "tg", "uz"] as const)
          .map((code) => [code, initial[`explanation_${code}`] ?? ""])
          .filter(([, text]) => text),
      ),
      ...(initial.explanations ?? {}),
    },
  }));
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  async function submit() {
    setError(null);
    setIsSaving(true);
    try {
      // Only the per-language texts are sent: the old fields are derived from them.
      const { explanation_ru: _ru, explanation_tg: _tg, explanation_uz: _uz, ...rest } = input;
      void _ru;
      void _tg;
      void _uz;
      await onSave(rest as MiniPhraseTemplateInput);
    } catch (e) {
      setError(errorText(e, "Не удалось сохранить"));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="card mt-4 flex flex-col gap-4 p-4">
      <h2 className="text-lg font-semibold text-slate-900">
        {isNew ? "Новый шаблон" : "Шаблон"}
      </h2>
      <label className="block text-sm text-slate-700">
        <span className="mb-1 block text-xs text-slate-500">
          Название (для админки)
        </span>
        <input
          className="field w-full max-w-md px-3 py-2 text-sm"
          value={input.name}
          placeholder="Кто + действие"
          onChange={(e) => setInput({ ...input, name: e.target.value })}
        />
      </label>
      <div className="rounded-lg bg-[var(--fill)] p-3 text-xs text-slate-600">
        <p className="mb-1 font-medium text-slate-700">
          Подстановки в тексте объяснения
        </p>
        <ul className="grid gap-x-4 gap-y-0.5 sm:grid-cols-2">
          {PLACEHOLDERS.map(([k, v]) => (
            <li key={k}>
              <code className="font-semibold text-indigo-700">{k}</code> — {v}
            </li>
          ))}
        </ul>
        <p className="mt-2">
          Пример: Барои гуфтани «{"{translation}"}» аввал {"{pronoun}"} (
          {"{pronoun.tr}"}), баъд {"{verb}"}. Натиҷа: {"{phrase}"}
        </p>
      </div>
      <PerLanguageFields
        multiline
        values={input.explanations ?? {}}
        onChange={(explanations) => setInput({ ...input, explanations })}
        label={(l) => `Объяснение — для читающих на языке: ${l.name}${l.code === "ru" ? " (и запасной вариант)" : ""}`}
      />
      <div className="flex flex-wrap items-end gap-5">
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">
            Лишних слов в «Собери фразу»
          </span>
          <select
            className="field px-3 py-2 text-sm"
            value={input.distractor_count}
            onChange={(e) =>
              setInput({ ...input, distractor_count: Number(e.target.value) })
            }
          >
            {[0, 1, 2, 3, 4].map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            checked={input.enabled}
            onChange={(e) => setInput({ ...input, enabled: e.target.checked })}
          />
          Включён
        </label>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <div className="flex gap-3">
        <button
          onClick={submit}
          disabled={isSaving || !input.name.trim()}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {isSaving ? "Сохранение…" : "Сохранить"}
        </button>
        <button
          onClick={onCancel}
          className="rounded-md px-4 py-2 text-sm text-slate-600 hover:bg-[var(--fill)]"
        >
          Отмена
        </button>
      </div>
    </div>
  );
}

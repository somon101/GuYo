import axios from "axios";
import { useEffect, useState } from "react";
import {
  createMiniPhraseTemplate,
  deleteMiniPhraseTemplate,
  getMiniPhraseSettings,
  listMiniPhraseTemplates,
  updateMiniPhraseSettings,
  updateMiniPhraseTemplate,
  type MiniPhraseTemplateInput,
} from "../api/endpoints";
import type { MiniPhraseSettings, MiniPhraseTemplate } from "../types";

function errorText(e: unknown, fallback: string): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
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
  const [editing, setEditing] = useState<{ id: number | null; input: MiniPhraseTemplateInput } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  async function reload() {
    try {
      const [t, s] = await Promise.all([listMiniPhraseTemplates(), getMiniPhraseSettings()]);
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
          <h1 className="text-[26px] font-bold tracking-tight text-slate-900">Мини-фразы</h1>
          <p className="text-sm text-slate-500">
            Шаблоны объяснений и настройки. Сами мини-фразы — в каждом языке, вкладка «Мини-фразы».
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

      <h2 className="mb-3 mt-8 text-lg font-semibold text-slate-900">Шаблоны</h2>
      {templates.length === 0 ? (
        <p className="text-sm text-slate-500">Шаблонов пока нет. Без шаблона используется стандартное объяснение.</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {templates.map((t) => (
            <li key={t.id} className="card flex flex-wrap items-start justify-between gap-3 p-4">
              <div className="min-w-0 flex-1">
                <p className="font-medium text-slate-900">
                  {t.name}
                  {!t.enabled && <span className="ml-2 text-xs text-slate-400">выключен</span>}
                </p>
                <p className="mt-1 text-sm text-slate-500">
                  Мини-фраз: {t.usage_count} · лишних слов в «Собери фразу»: {t.distractor_count}
                </p>
                {t.explanation_tg && <p className="mt-2 text-sm text-slate-600">{t.explanation_tg}</p>}
              </div>
              <div className="flex shrink-0 items-center gap-4">
                <button
                  onClick={() => {
                    const { id, usage_count, ...input } = t;
                    void usage_count;
                    setEditing({ id, input });
                  }}
                  className="text-sm font-medium text-indigo-600 hover:underline"
                >
                  Редактировать
                </button>
                <button onClick={() => remove(t)} className="text-sm text-slate-400 hover:text-red-600">
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

function SettingsCard({ settings, onSaved }: { settings: MiniPhraseSettings; onSaved: (s: MiniPhraseSettings) => void }) {
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
            onChange={(e) => setDraft({ ...draft, points_enabled: e.target.checked })}
          />
          Очки за верную сборку
        </label>
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Очков за мини-фразу (один раз)</span>
          <input
            type="number"
            min={0}
            max={1000}
            className="field w-28 px-3 py-2 text-sm"
            value={draft.points_per_correct}
            onChange={(e) => setDraft({ ...draft, points_per_correct: Number(e.target.value) })}
          />
        </label>
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Максимум на урок</span>
          <input
            type="number"
            min={0}
            max={10}
            className="field w-28 px-3 py-2 text-sm"
            value={draft.max_per_lesson}
            onChange={(e) => setDraft({ ...draft, max_per_lesson: Number(e.target.value) })}
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
  const [input, setInput] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  async function submit() {
    setError(null);
    setIsSaving(true);
    try {
      await onSave(input);
    } catch (e) {
      setError(errorText(e, "Не удалось сохранить"));
    } finally {
      setIsSaving(false);
    }
  }

  const area = (key: "explanation_tg" | "explanation_uz" | "explanation_ru", label: string) => (
    <label className="block text-sm text-slate-700">
      <span className="mb-1 block text-xs text-slate-500">{label}</span>
      <textarea
        rows={3}
        className="field w-full px-3 py-2 text-sm"
        value={input[key] ?? ""}
        onChange={(e) => setInput({ ...input, [key]: e.target.value })}
      />
    </label>
  );

  return (
    <div className="card mt-4 flex flex-col gap-4 p-4">
      <h2 className="text-lg font-semibold text-slate-900">{isNew ? "Новый шаблон" : "Шаблон"}</h2>
      <label className="block text-sm text-slate-700">
        <span className="mb-1 block text-xs text-slate-500">Название (для админки)</span>
        <input
          className="field w-full max-w-md px-3 py-2 text-sm"
          value={input.name}
          placeholder="Кто + действие"
          onChange={(e) => setInput({ ...input, name: e.target.value })}
        />
      </label>
      <div className="rounded-lg bg-[var(--fill)] p-3 text-xs text-slate-600">
        <p className="mb-1 font-medium text-slate-700">Подстановки в тексте объяснения</p>
        <ul className="grid gap-x-4 gap-y-0.5 sm:grid-cols-2">
          {PLACEHOLDERS.map(([k, v]) => (
            <li key={k}>
              <code className="font-semibold text-indigo-700">{k}</code> — {v}
            </li>
          ))}
        </ul>
        <p className="mt-2">
          Пример: Барои гуфтани «{"{translation}"}» аввал {"{pronoun}"} ({"{pronoun.tr}"}), баъд {"{verb}"}. Натиҷа:{" "}
          {"{phrase}"}
        </p>
      </div>
      {area("explanation_tg", "Объяснение — таджикский интерфейс")}
      {area("explanation_uz", "Объяснение — узбекский интерфейс")}
      {area("explanation_ru", "Объяснение — русский интерфейс (и запасной вариант)")}
      <div className="flex flex-wrap items-end gap-5">
        <label className="text-sm text-slate-700">
          <span className="mb-1 block text-xs text-slate-500">Лишних слов в «Собери фразу»</span>
          <select
            className="field px-3 py-2 text-sm"
            value={input.distractor_count}
            onChange={(e) => setInput({ ...input, distractor_count: Number(e.target.value) })}
          >
            {[0, 1, 2, 3, 4].map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={input.enabled} onChange={(e) => setInput({ ...input, enabled: e.target.checked })} />
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
        <button onClick={onCancel} className="rounded-md px-4 py-2 text-sm text-slate-600 hover:bg-[var(--fill)]">
          Отмена
        </button>
      </div>
    </div>
  );
}

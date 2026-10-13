import axios from "axios";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import { getAiState, listDictionaries, setAiKey, type AiKeyState } from "../api/endpoints";
import { SegmentedControl } from "../components/SegmentedControl";
import type { Dictionary } from "../types";
import { MiniPhraseGenerator } from "./MiniPhraseGenerator";
import { TextCheckPage } from "./TextCheckPage";
import { TranslationPage } from "./TranslationPage";

type Tool = "translate" | "text" | "mini";

const TOOLS: Tool[] = ["translate", "text", "mini"];

function errorText(e: unknown): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return "Не удалось выполнить запрос";
}

/** «ИИ»: everything that runs on DeepSeek in one place -- translation of words
 * and phrases, «Проверка текста», and mini-phrase generation.
 *
 * The DeepSeek key is shared by all of them (one account, one key), so it is
 * edited here ONCE, above the tools, instead of on every tool's own page. */
export function AiToolsPage() {
  const [tool, setTool] = useState<Tool>(() => {
    try {
      const saved = localStorage.getItem("ai-tool") as Tool;
      return TOOLS.includes(saved) ? saved : "translate";
    } catch {
      return "translate";
    }
  });
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [dictionaryId, setDictionaryId] = useState<number | null>(null);

  const [key, setKey] = useState<AiKeyState | null>(null);
  const [keyInput, setKeyInput] = useState("");
  const [keyBusy, setKeyBusy] = useState(false);
  const [keyError, setKeyError] = useState<string | null>(null);
  const [keySaved, setKeySaved] = useState(false);
  // Bumped when the key changes: the translation tab reads the key state once,
  // so it is remounted to pick the new one up immediately.
  const [keyRevision, setKeyRevision] = useState(0);

  useEffect(() => {
    listDictionaries()
      .then((list) => {
        setDictionaries(list);
        const ru = list.find((d) => d.language === "ru") ?? list[0];
        if (ru) setDictionaryId((id) => id ?? ru.id);
      })
      .catch(() => setDictionaries([]));
  }, []);

  const loadKey = useCallback(() => {
    getAiState()
      .then((s) => setKey(s.key))
      .catch(() => setKey(null));
  }, []);
  useEffect(loadKey, [loadKey]);

  function choose(t: Tool) {
    setTool(t);
    try {
      localStorage.setItem("ai-tool", t);
    } catch {
      /* not essential */
    }
  }

  async function saveKey(e: FormEvent) {
    e.preventDefault();
    if (!keyInput.trim()) return;
    setKeyBusy(true);
    setKeyError(null);
    try {
      setKey(await setAiKey(keyInput));
      setKeyInput("");
      setKeySaved(true);
      setKeyRevision((r) => r + 1);
      window.setTimeout(() => setKeySaved(false), 3000);
    } catch (e) {
      setKeyError(errorText(e));
    } finally {
      setKeyBusy(false);
    }
  }

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-[26px] font-bold tracking-tight text-slate-900">ИИ</h1>
        <p className="mt-1 text-sm text-slate-500">
          Перевод, проверка текста и генерация мини-фраз через DeepSeek. Ключ — один на все инструменты.
        </p>
      </div>

      <section className="card p-4 space-y-3 max-w-3xl">
        <h2 className="font-medium">Ключ DeepSeek</h2>
        <p className="text-sm">
          {key === null ? (
            "Не удалось узнать состояние ключа"
          ) : key.key_set ? (
            <>
              Сохранён: <code>{key.key_masked}</code>
            </>
          ) : (
            "Ключ ещё не сохранён — без него ни один инструмент не работает"
          )}
        </p>
        <form onSubmit={saveKey} className="flex flex-wrap gap-2">
          <input
            type="password"
            className="flex-1 field px-3 py-2 text-sm"
            placeholder={key?.key_set ? "Новый ключ, чтобы заменить" : "sk-…"}
            value={keyInput}
            onChange={(e) => setKeyInput(e.target.value)}
            autoComplete="off"
          />
          <button
            type="submit"
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
            disabled={keyBusy || !keyInput.trim()}
          >
            {keyBusy ? "Сохранение…" : "Сохранить"}
          </button>
          {keySaved && <span className="self-center text-sm text-emerald-600">Сохранено</span>}
        </form>
        {keyError && <p className="text-sm text-red-600">{keyError}</p>}
      </section>

      <SegmentedControl<Tool>
        ariaLabel="Инструмент"
        value={tool}
        onChange={choose}
        segments={[
          { value: "translate", label: "Перевод" },
          { value: "text", label: "Проверка текста" },
          { value: "mini", label: "Генерация мини-фраз" },
        ]}
      />

      {tool === "translate" ? (
        <TranslationPage key={`translate-${keyRevision}`} />
      ) : tool === "text" ? (
        <TextCheckPage />
      ) : (
        <div className="max-w-3xl space-y-4">
          <label className="block text-sm text-slate-700">
            <span className="mb-1 block text-xs text-slate-500">Язык (словарь)</span>
            <select
              className="field px-3 py-2 text-sm"
              value={dictionaryId ?? ""}
              onChange={(e) => setDictionaryId(e.target.value ? Number(e.target.value) : null)}
            >
              {dictionaries.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name}
                </option>
              ))}
            </select>
          </label>
          {dictionaryId != null && (
            <MiniPhraseGenerator key={dictionaryId} dictionaryId={dictionaryId} onSaved={() => {}} />
          )}
        </div>
      )}
    </div>
  );
}

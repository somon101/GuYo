import { useEffect, useState } from "react";
import { listDictionaries } from "../api/endpoints";
import { SegmentedControl } from "../components/SegmentedControl";
import type { Dictionary } from "../types";
import { MiniPhraseGenerator } from "./MiniPhraseGenerator";
import { TranslationPage } from "./TranslationPage";

type Tool = "translate" | "mini";

/** «ИИ-инструменты»: everything that runs on DeepSeek in one place --
 * translation of words and phrases, and mini-phrase generation. */
export function AiToolsPage() {
  const [tool, setTool] = useState<Tool>(() => {
    try {
      return (localStorage.getItem("ai-tool") as Tool) || "translate";
    } catch {
      return "translate";
    }
  });
  const [dictionaries, setDictionaries] = useState<Dictionary[]>([]);
  const [dictionaryId, setDictionaryId] = useState<number | null>(null);

  useEffect(() => {
    listDictionaries()
      .then((list) => {
        setDictionaries(list);
        const ru = list.find((d) => d.language === "ru") ?? list[0];
        if (ru) setDictionaryId((id) => id ?? ru.id);
      })
      .catch(() => setDictionaries([]));
  }, []);

  function choose(t: Tool) {
    setTool(t);
    try {
      localStorage.setItem("ai-tool", t);
    } catch {
      /* not essential */
    }
  }

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-[26px] font-bold tracking-tight text-slate-900">ИИ-инструменты</h1>
        <p className="mt-1 text-sm text-slate-500">Перевод и генерация мини-фраз через DeepSeek. Ключ — во вкладке «Перевод».</p>
      </div>
      <SegmentedControl<Tool>
        ariaLabel="Инструмент"
        value={tool}
        onChange={choose}
        segments={[
          { value: "translate", label: "Перевод" },
          { value: "mini", label: "Генерация мини-фраз" },
        ]}
      />
      {tool === "translate" ? (
        <TranslationPage />
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

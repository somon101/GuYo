import axios from "axios";
import { useState } from "react";
import {
  addMissingWords,
  fillMiniPhraseStarter500,
  type Starter500Report,
} from "../api/endpoints";

/** «Набор 500»: hand-written everyday mini-phrases. Fills what the
 * dictionary's words allow, lists the missing words (how many phrases each
 * would unlock), adds the chosen ones as full cards (AI) and fills again. */
export function Starter500Panel({
  dictionaryId,
  onFilled,
}: {
  dictionaryId: number;
  onFilled: () => void;
}) {
  const [report, setReport] = useState<Starter500Report | null>(null);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState<"fill" | "words" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [wordsMessage, setWordsMessage] = useState<string | null>(null);

  function errText(e: unknown, fallback: string) {
    return axios.isAxiosError(e) && typeof e.response?.data?.detail === "string"
      ? e.response.data.detail
      : fallback;
  }

  async function fill() {
    setBusy("fill");
    setError(null);
    try {
      const r = await fillMiniPhraseStarter500(dictionaryId);
      setReport(r);
      setChosen(new Set(r.missing_words.map((m) => m.word)));
      onFilled();
    } catch (e) {
      setError(errText(e, "Не удалось заполнить"));
    } finally {
      setBusy(null);
    }
  }

  async function addWords() {
    setBusy("words");
    setError(null);
    try {
      const r = await addMissingWords(dictionaryId, [...chosen]);
      setWordsMessage(
        `Добавлено слов: ${r.created.length}` +
          (r.updated.length
            ? ` · дополнены формами: ${r.updated.length}`
            : "") +
          ` · токенов: ${r.tokens}. Теперь нажмите «Заполнить ещё раз».`,
      );
    } catch (e) {
      setError(errText(e, "Не удалось добавить слова"));
    } finally {
      setBusy(null);
    }
  }

  const done = report ? report.created.length + report.already.length : 0;

  return (
    <div className="card mb-6 flex flex-col gap-3 p-4">
      <div>
        <p className="text-[16px] font-semibold text-slate-900">Набор 500</p>
        <p className="text-sm text-slate-600">
          {report?.total ?? "500+"} живых фраз для общения (знакомство, магазин,
          работа, врач, транспорт, документы…) с переводами на таджикский,
          узбекский и английский. Создаются фразы, все слова которых есть в
          словаре; формы слов добавляются сами. Повторный запуск ничего не
          дублирует.
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        <button
          onClick={fill}
          disabled={busy !== null}
          className="rounded-md bg-violet-600 px-4 py-2 text-sm font-medium text-white hover:bg-violet-700 disabled:opacity-50"
        >
          {busy === "fill"
            ? "Заполнение…"
            : report
              ? "Заполнить ещё раз"
              : "Заполнить набором 500"}
        </button>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}

      {report && (
        <>
          <div className="h-2.5 overflow-hidden rounded-full bg-[var(--fill)]">
            <div
              className="h-full rounded-full bg-violet-600"
              style={{ width: `${(100 * done) / report.total}%` }}
            />
          </div>
          <p className="text-sm text-slate-800">
            В словаре уже <b>{done}</b> из {report.total} · создано сейчас:{" "}
            <b>{report.created.length}</b> · ждут слов: {report.skipped.length}
            {report.forms_added.length > 0 &&
              ` · добавлено форм: ${report.forms_added.length}`}
            {report.templates_created.length > 0 &&
              ` · новых шаблонов: ${report.templates_created.length}`}
          </p>
          {report.missing_words.length > 0 && (
            <div className="rounded-lg bg-[var(--fill)] p-3">
              <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                <p className="text-sm font-medium text-slate-800">
                  Не хватает слов: {report.missing_words.length} (число —
                  сколько фраз откроет слово)
                </p>
                <div className="flex gap-2 text-sm">
                  <button
                    onClick={() =>
                      setChosen(
                        new Set(report.missing_words.map((m) => m.word)),
                      )
                    }
                    className="text-indigo-600 hover:underline"
                  >
                    Выбрать все
                  </button>
                  <button
                    onClick={() => setChosen(new Set())}
                    className="text-slate-500 hover:underline"
                  >
                    Снять
                  </button>
                </div>
              </div>
              <div
                className="flex max-h-72 flex-wrap gap-1.5 overflow-auto"
                translate="no"
              >
                {report.missing_words.map((m) => {
                  const on = chosen.has(m.word);
                  return (
                    <button
                      key={m.word}
                      onClick={() => {
                        const next = new Set(chosen);
                        if (on) next.delete(m.word);
                        else next.add(m.word);
                        setChosen(next);
                      }}
                      className={`rounded-full px-2.5 py-0.5 text-sm ${
                        on
                          ? "bg-indigo-600 text-white"
                          : "bg-[var(--card)] text-slate-700 hover:bg-indigo-50"
                      }`}
                    >
                      {m.word}{" "}
                      <span
                        className={on ? "text-indigo-100" : "text-slate-400"}
                      >
                        {m.phrases}
                      </span>
                    </button>
                  );
                })}
              </div>
              <button
                onClick={addWords}
                disabled={chosen.size === 0 || busy !== null}
                className="mt-3 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
              >
                {busy === "words"
                  ? "ИИ создаёт карточки… (порциями по 8)"
                  : `Добавить слова полной карточкой (${chosen.size})`}
              </button>
              {wordsMessage && (
                <p className="mt-2 text-sm text-emerald-700">{wordsMessage}</p>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}

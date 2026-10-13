import axios from "axios";
import { useCallback, useEffect, useState } from "react";
import {
  clearTextCheckCache,
  deleteTextCheckCacheEntry,
  getAiState,
  listTextCheckCache,
  setTextCheckSettings,
  type AiState,
  type TextCheckCacheEntry,
} from "../api/endpoints";

function errorText(e: unknown): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return "Не удалось выполнить запрос";
}

const PARAM_LABELS: Record<string, string> = {
  user_gender: "автор",
  addressee_gender: "собеседник",
  formality: "формальность",
  check_punctuation: "пунктуация",
  explanation_language: "объяснения",
};

const VALUE_LABELS: Record<string, string> = {
  male: "мужчина",
  female: "женщина",
  unknown: "не выбран",
  formal: "формально",
  informal: "неформально",
  ru: "русский",
  tg: "таджикский",
  uz: "узбекский",
  en: "английский",
};

function paramSummary(params: Record<string, unknown>): string {
  return Object.entries(params)
    .map(([key, value]) => {
      const label = PARAM_LABELS[key] ?? key;
      const shown =
        value === true
          ? "вкл"
          : value === false
            ? "выкл"
            : value === null || value === undefined
              ? "нет"
              : (VALUE_LABELS[String(value)] ?? String(value));
      return `${label}: ${shown}`;
    })
    .join(" · ");
}

/** «Проверка текста»: the checker's own switches, what it has actually done,
 * and the answers it has already cached. The DeepSeek key itself lives one
 * level up, in «ИИ» — it is shared by every AI feature. */
export function TextCheckPage() {
  const [state, setState] = useState<AiState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  // The editable copy of the switches. An empty limit field means "no limit
  // at all" (which is what Premium gets by default).
  const [enabled, setEnabled] = useState(true);
  const [maxChars, setMaxChars] = useState("500");
  const [freeLimit, setFreeLimit] = useState("");
  const [premiumLimit, setPremiumLimit] = useState("");

  const [cache, setCache] = useState<{ total: number; entries: TextCheckCacheEntry[] } | null>(null);

  const load = useCallback(async () => {
    try {
      const s = await getAiState();
      setState(s);
      setEnabled(s.text_check.enabled);
      setMaxChars(String(s.text_check.max_chars));
      setFreeLimit(s.text_check.free_daily_limit === null ? "" : String(s.text_check.free_daily_limit));
      setPremiumLimit(s.text_check.premium_daily_limit === null ? "" : String(s.text_check.premium_daily_limit));
      setError(null);
    } catch (e) {
      setError(errorText(e));
    }
  }, []);

  const loadCache = useCallback(async () => {
    try {
      setCache(await listTextCheckCache(50, 0));
    } catch (e) {
      setError(errorText(e));
    }
  }, []);

  useEffect(() => {
    load().then(loadCache);
  }, [load, loadCache]);

  /** "" -> null (no limit); otherwise the number as typed. */
  function limitValue(raw: string): number | null {
    const trimmed = raw.trim();
    return trimmed === "" ? null : Number(trimmed);
  }

  async function save() {
    setBusy(true);
    setSaved(false);
    setError(null);
    try {
      const result = await setTextCheckSettings({
        enabled,
        max_chars: Number(maxChars),
        free_daily_limit: limitValue(freeLimit),
        premium_daily_limit: limitValue(premiumLimit),
      });
      setState((prev) => (prev ? { ...prev, text_check: result.text_check, stats: result.stats } : prev));
      setSaved(true);
      window.setTimeout(() => setSaved(false), 3000);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  async function removeEntry(id: number) {
    setBusy(true);
    try {
      await deleteTextCheckCacheEntry(id);
      await Promise.all([load(), loadCache()]);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  async function clearAll() {
    if (!window.confirm("Очистить весь кеш проверок? Следующий такой же текст будет заново отправлен в DeepSeek.")) {
      return;
    }
    setBusy(true);
    try {
      await clearTextCheckCache();
      await Promise.all([load(), loadCache()]);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  if (!state) return <p className="text-sm text-slate-500">{error ?? "Загрузка…"}</p>;
  const stats = state.stats;

  return (
    <div className="space-y-5 max-w-3xl">
      <div>
        <h2 className="text-xl font-semibold">Проверка текста</h2>
        <p className="text-sm text-slate-500 mt-1">
          Пользователь пишет сообщение по-русски, DeepSeek находит ошибки, объясняет их и показывает исправленный текст.
          Ключ DeepSeek — общий для всех ИИ-функций, он сохраняется на вкладке «ИИ».
        </p>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <section className="card p-4 space-y-4">
        <h3 className="font-medium">Настройки</h3>

        <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
          <input type="checkbox" className="switch" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
          Проверка текста включена
        </label>
        <p className="-mt-2 text-xs text-slate-400">
          Если выключить, приложение скажет «Проверка текста сейчас недоступна» и не будет обращаться к DeepSeek.
        </p>

        <div className="flex flex-wrap items-center gap-3">
          <label className="text-sm font-medium text-slate-700" htmlFor="tc-max">
            Максимум символов в сообщении
          </label>
          <input
            id="tc-max"
            type="number"
            min={1}
            max={2000}
            className="w-24 field px-3 py-1.5 text-sm"
            value={maxChars}
            onChange={(e) => setMaxChars(e.target.value)}
          />
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <label className="text-sm font-medium text-slate-700" htmlFor="tc-free">
            Бесплатно: проверок в день
          </label>
          <input
            id="tc-free"
            type="number"
            min={0}
            className="w-24 field px-3 py-1.5 text-sm"
            placeholder="без лимита"
            value={freeLimit}
            onChange={(e) => setFreeLimit(e.target.value)}
          />
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <label className="text-sm font-medium text-slate-700" htmlFor="tc-premium">
            Premium: проверок в день
          </label>
          <input
            id="tc-premium"
            type="number"
            min={0}
            className="w-24 field px-3 py-1.5 text-sm"
            placeholder="без лимита"
            value={premiumLimit}
            onChange={(e) => setPremiumLimit(e.target.value)}
          />
        </div>
        <p className="-mt-2 text-xs text-slate-400">
          Пустое поле = без ограничений, 0 = проверять нельзя. Отдельным пользователям безлимит выдаётся галочкой в их
          карточке — независимо от Premium.
        </p>

        <div className="flex items-center gap-3">
          <button
            onClick={save}
            disabled={busy}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {busy ? "Сохранение…" : "Сохранить"}
          </button>
          {saved && <span className="text-sm text-emerald-600">Сохранено</span>}
        </div>
      </section>

      <section className="card p-4 space-y-3">
        <h3 className="font-medium">Что уже проверено</h3>
        <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
          <Stat label="Сегодня проверок" value={stats.today_checks} />
          <Stat label="Сегодня из кеша" value={stats.today_cached} />
          <Stat label="Сегодня сбоев" value={stats.today_failed} />
          <Stat label="Всего проверок" value={stats.total_checks} />
          <Stat label="Всего из кеша" value={stats.total_cached} />
          <Stat label="Записей в кеше" value={stats.cache_entries} />
        </div>
        <p className="text-xs text-slate-400">
          «Сбои» — DeepSeek не ответил; такие проверки пользователю не засчитываются в лимит. «Из кеша» — повторный текст:
          он отдаётся мгновенно и лимит тоже не тратит.
        </p>
      </section>

      <section className="card p-4 space-y-3">
        <div className="flex items-center justify-between gap-3">
          <h3 className="font-medium">
            Кеш ответов {cache ? <span className="text-slate-400">— {cache.total}</span> : null}
          </h3>
          <button
            onClick={clearAll}
            disabled={busy || !cache || cache.total === 0}
            className="btn-tinted rounded-md px-3 py-1.5 text-sm font-medium disabled:opacity-60"
          >
            Очистить кеш
          </button>
        </div>
        <p className="text-xs text-slate-400">
          Одинаковый текст с одинаковыми настройками отдаётся из кеша: мгновенно и без оплаты. Если ответ оказался
          неверным — удалите строку, и в следующий раз модель спросят заново.
        </p>

        {!cache || cache.entries.length === 0 ? (
          <p className="text-sm text-slate-500">Пока пусто.</p>
        ) : (
          <div className="divide-y divide-slate-100">
            {cache.entries.map((entry) => (
              <div key={entry.id} className="flex items-start gap-3 py-2">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm text-slate-800">{entry.text}</p>
                  <p className="truncate text-xs text-slate-400">{paramSummary(entry.params)}</p>
                </div>
                <div className="shrink-0 text-right text-xs text-slate-500">
                  <p>
                    {entry.hits}× · {entry.errors === 0 ? "без ошибок" : `${entry.errors} ошиб.`}
                  </p>
                  <p className="text-slate-400">{new Date(entry.created_at).toLocaleString("ru-RU")}</p>
                </div>
                <button
                  onClick={() => removeEntry(entry.id)}
                  disabled={busy}
                  title="Удалить эту запись"
                  className="shrink-0 rounded-md px-2 py-1 text-xs font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                >
                  Удалить
                </button>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-md bg-slate-50 px-3 py-2">
      <div className="text-lg font-semibold text-slate-900">{value}</div>
      <div className="text-xs text-slate-500">{label}</div>
    </div>
  );
}

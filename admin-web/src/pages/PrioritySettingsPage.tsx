import axios from "axios";
import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import {
  createPriorityLevelBand,
  createRecencyBand,
  createStabilityBand,
  deletePriorityLevelBand,
  deleteRecencyBand,
  deleteStabilityBand,
  getPrioritySettings,
  listPriorityLevelBands,
  listRecencyBands,
  listStabilityBands,
  listWordLevels,
  updatePriorityLevelBand,
  updatePrioritySettings,
  updateRecencyBand,
  updateStabilityBand,
  type PriorityLevelBandInput,
  type RecencyBandInput,
  type StabilityBandInput,
} from "../api/endpoints";
import { InfoTooltip } from "../components/InfoTooltip";
import { formatScoreRange, PRIORITY_ROLE_EFFECTS, priorityRoleBands } from "../lib/priorityRoles";
import type { PriorityLevelBand, PriorityRecencyBand, PriorityStabilityBand, PrioritySettings, WordLevel } from "../types";

const inputClass =
  "rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500";

/** Every number app/priority/calculate.py reads on the backend, in one
 * place: the 4 factor weights + the 3 recent-error window weights (one
 * settings row), then the three range-based band lists (давность,
 * стабильность, итоговый Priority Level) -- same range+contribution+order
 * shape WordLevelsSettingsPage already uses for word levels, whose own
 * "вклад в Priority" field lives on that page instead of here (one admin
 * decision, one place to make it). Nothing here is business math anyone
 * has signed off on -- every value shown was seeded as a starting example
 * and is meant to be tuned. */
export function PrioritySettingsPage() {
  return (
    <div className="mx-auto max-w-3xl">
      <Link to="/exercises" className="text-sm font-medium text-indigo-600 hover:text-indigo-700">
        ← Упражнения
      </Link>
      <h1 className="mb-1 mt-3 text-xl font-semibold text-slate-900">Приоритет</h1>
      <p className="mb-6 text-sm text-slate-500">
        Насколько срочно слову нужно повторение -- считается на лету из истории попыток (см. «Диагностика слова» в
        Аналитике), а не хранится. Вклад по уровню слова редактируется на странице «Уровни слов»; здесь -- всё
        остальное.
      </p>

      <WeightsSection />
      <RecencySection />
      <StabilitySection />
      <LevelBandsSection />
    </div>
  );
}

function Section({
  title,
  hint,
  titleExtra,
  children,
}: {
  title: string;
  hint?: string;
  titleExtra?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-8">
      <h2 className="flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-slate-500">
        {title}
        {titleExtra}
      </h2>
      {hint && <p className="mb-3 mt-1 text-xs text-slate-400">{hint}</p>}
      <div className={hint ? "" : "mt-3"}>{children}</div>
    </section>
  );
}

/** Compact key/value list for inside an InfoTooltip -- the same "current
 * setting, in plain numbers" shape every tooltip in this file uses. */
function TooltipFacts({ rows }: { rows: { label: string; value: React.ReactNode }[] }) {
  return (
    <dl className="flex flex-col gap-1">
      {rows.map((r, i) => (
        <div key={i} className="flex items-baseline justify-between gap-3">
          <dt className="text-slate-500">{r.label}</dt>
          <dd className="font-medium text-slate-900">{r.value}</dd>
        </div>
      ))}
    </dl>
  );
}

// --- Веса факторов -----------------------------------------------------

function WeightsSection() {
  const [settings, setSettings] = useState<PrioritySettings | null>(null);
  const [wordLevels, setWordLevels] = useState<WordLevel[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    Promise.all([getPrioritySettings(), listWordLevels()])
      .then(([s, levels]) => {
        setSettings(s);
        setWordLevels(levels);
      })
      .catch(() => setError("Не удалось загрузить настройки"))
      .finally(() => setIsLoading(false));
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!settings) return;
    setIsSaving(true);
    setError(null);
    setSaved(false);
    try {
      setSettings(await updatePrioritySettings(settings));
      setSaved(true);
    } catch {
      setError("Не удалось сохранить");
    } finally {
      setIsSaving(false);
    }
  }

  function field(key: keyof PrioritySettings, label: string, hint?: string, tooltip?: React.ReactNode) {
    if (!settings) return null;
    return (
      <div key={key}>
        <label className="mb-1 flex items-center gap-1.5 text-sm font-medium text-slate-700">
          {label}
          {tooltip}
        </label>
        <input
          type="number"
          step="any"
          className={`w-32 ${inputClass}`}
          value={settings[key]}
          onChange={(e) => setSettings({ ...settings, [key]: Number(e.target.value) })}
        />
        {hint && <p className="mt-1 text-xs text-slate-400">{hint}</p>}
      </div>
    );
  }

  const sortedLevels = [...wordLevels].sort((a, b) => a.min_points - b.min_points);

  return (
    <Section
      title="Веса факторов"
      hint="Итог = сумма (значение фактора × его вес). Каждый фактор сам по себе — 0-100."
      titleExtra={
        settings && (
          <InfoTooltip label="Что такое Priority Score">
            <p className="mb-2 font-medium text-slate-900">Priority Score</p>
            <p className="mb-2">
              Сумма 4 факторов, каждый умножен на свой вес ниже. Чем выше итог — тем срочнее слову нужно повторение.
            </p>
            <TooltipFacts
              rows={[
                { label: "Уровень слова", value: `× ${settings.weight_level}` },
                { label: "Недавние ошибки", value: `× ${settings.weight_recent_errors}` },
                { label: "Давность контакта", value: `× ${settings.weight_recency}` },
                { label: "Стабильность", value: `× ${settings.weight_stability}` },
              ]}
            />
            <p className="mt-2 text-slate-400">
              Не хранится — пересчитывается заново при каждом обращении (например, при открытии диагностики слова).
            </p>
          </InfoTooltip>
        )
      }
    >
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : !settings ? (
        <p className="text-sm text-red-600">{error}</p>
      ) : (
        <form onSubmit={handleSubmit} className="flex flex-col gap-4 rounded-lg border border-slate-200 bg-white p-4">
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            {field(
              "weight_level",
              "Уровень слова",
              undefined,
              <InfoTooltip label="Как влияет уровень слова">
                <p className="mb-2 font-medium text-slate-900">Фактор «Уровень слова»</p>
                <p className="mb-2">
                  У каждого уровня слова свой вклад (настраивается на странице «Уровни слов») — чем менее выучено слово,
                  тем выше вклад:
                </p>
                {sortedLevels.length > 0 ? (
                  <TooltipFacts
                    rows={sortedLevels.map((l) => ({
                      label: `${l.name} (${l.min_points}–${l.max_points ?? "∞"})`,
                      value: l.priority_weight,
                    }))}
                  />
                ) : (
                  <p className="text-slate-400">Уровни слов пока не настроены.</p>
                )}
                <p className="mt-2 text-slate-400">Итоговый вклад в Priority = вклад уровня × этот вес.</p>
              </InfoTooltip>,
            )}
            {field(
              "weight_recent_errors",
              "Недавние ошибки",
              undefined,
              <InfoTooltip label="Как влияют недавние ошибки">
                <p className="mb-2 font-medium text-slate-900">Фактор «Недавние ошибки»</p>
                <p className="mb-2">
                  Считаем долю ошибок отдельно среди последних 5, 10 и 20 попыток, затем берём их взвешенное среднее с
                  весами окон ниже. Чем больше вес у меньшего окна относительно большего, тем сильнее свежие результаты
                  перевешивают старые.
                </p>
                <TooltipFacts
                  rows={[
                    { label: "Последние 5", value: settings.window5_weight },
                    { label: "Последние 10", value: settings.window10_weight },
                    { label: "Последние 20", value: settings.window20_weight },
                  ]}
                />
                <p className="mt-2 text-slate-400">Итоговый вклад в Priority = (взвешенная доля ошибок × 100) × этот вес.</p>
              </InfoTooltip>,
            )}
            {field(
              "weight_recency",
              "Давность",
              undefined,
              <InfoTooltip label="Как влияет давность контакта">
                Насколько сильно диапазоны давности (раздел «Давность последнего контакта» ниже) сказываются на итоговом
                Priority Score. Сам механизм и текущие диапазоны — в подсказке у того раздела.
              </InfoTooltip>,
            )}
            {field(
              "weight_stability",
              "Стабильность",
              undefined,
              <InfoTooltip label="Как влияет стабильность">
                Насколько сильно диапазоны стабильности (раздел «Стабильность» ниже) сказываются на итоговом Priority
                Score. Сам механизм и текущие диапазоны — в подсказке у того раздела.
              </InfoTooltip>,
            )}
          </div>
          <div className="border-t border-slate-100 pt-4">
            <p className="mb-3 text-xs font-medium uppercase tracking-wide text-slate-400">
              Окна «недавних ошибок» — вес каждого окна между собой
            </p>
            <div className="grid grid-cols-3 gap-4 sm:w-2/3">
              {field("window5_weight", "Последние 5")}
              {field("window10_weight", "Последние 10")}
              {field("window20_weight", "Последние 20")}
            </div>
          </div>
          <div className="border-t border-slate-100 pt-4">
            {field(
              "stability_window",
              "Окно стабильности (попыток)",
              "Сколько последних попыток учитывается при расчёте стабильности.",
            )}
          </div>
          <div className="flex items-center gap-3">
            <button
              type="submit"
              disabled={isSaving}
              className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
            >
              {isSaving ? "Сохранение…" : "Сохранить"}
            </button>
            {saved && <span className="text-sm text-emerald-600">Сохранено</span>}
            {error && <span className="text-sm text-red-600">{error}</span>}
          </div>
        </form>
      )}
    </Section>
  );
}

// --- Давность ------------------------------------------------------------

function RecencySection() {
  const [bands, setBands] = useState<PriorityRecencyBand[]>([]);
  const [weight, setWeight] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [editing, setEditing] = useState<PriorityRecencyBand | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function reload() {
    setIsLoading(true);
    try {
      setBands(await listRecencyBands());
    } catch {
      setError("Не удалось загрузить");
    } finally {
      setIsLoading(false);
    }
  }
  useEffect(() => {
    reload();
    getPrioritySettings()
      .then((s) => setWeight(s.weight_recency))
      .catch(() => {});
  }, []);

  async function handleDelete(band: PriorityRecencyBand) {
    if (!confirm(`Удалить «${band.name}»?`)) return;
    try {
      await deleteRecencyBand(band.id);
      setBands((prev) => prev.filter((b) => b.id !== band.id));
    } catch {
      setError("Не удалось удалить");
    }
  }

  return (
    <Section
      title="Давность последнего контакта"
      hint="Сколько дней слово не трогали → сколько это добавляет к Priority."
      titleExtra={
        <InfoTooltip label="Как считается давность">
          <p className="mb-2 font-medium text-slate-900">Фактор «Давность последнего контакта»</p>
          <p className="mb-2">
            Считаем, сколько дней прошло с последней попытки по слову (0 = сегодня), и смотрим, в какой диапазон ниже
            это попадает. Слово, которое давно не трогали, «дорожает» само по себе — даже без единой новой попытки,
            просто потому что при каждом пересчёте проходит больше времени.
          </p>
          {bands.length > 0 && (
            <TooltipFacts
              rows={[...bands]
                .sort((a, b) => a.min_days - b.min_days)
                .map((b) => ({ label: `${b.name} (${b.min_days}–${b.max_days ?? "∞"} дн.)`, value: `+${b.contribution}` }))}
            />
          )}
          {weight != null && <p className="mt-2 text-slate-400">Итоговый вклад в Priority = вклад диапазона × {weight}.</p>}
        </InfoTooltip>
      }
    >
      <button onClick={() => setEditing("new")} className="mb-3 text-sm font-medium text-indigo-600 hover:text-indigo-700">
        + Добавить диапазон
      </button>
      {editing !== null && (
        <RecencyForm
          band={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            setBands((prev) => (editing === "new" ? [...prev, saved] : prev.map((b) => (b.id === saved.id ? saved : b))));
          }}
          onCancel={() => setEditing(null)}
        />
      )}
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {[...bands]
            .sort((a, b) => a.order - b.order)
            .map((band) => (
              <li key={band.id} className={`flex items-center gap-3 rounded-lg border border-slate-200 bg-white p-3 ${band.enabled ? "" : "opacity-50"}`}>
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-slate-900">{band.name}</p>
                  <p className="text-xs text-slate-500">
                    {band.min_days}–{band.max_days ?? "∞"} дней · вклад {band.contribution}
                    {!band.enabled && " · отключён"}
                  </p>
                </div>
                <button onClick={() => setEditing(band)} className="shrink-0 text-sm font-medium text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button onClick={() => handleDelete(band)} className="shrink-0 text-sm text-slate-400 hover:text-red-600">
                  Удалить
                </button>
              </li>
            ))}
        </ul>
      )}
    </Section>
  );
}

function RecencyForm({ band, onSaved, onCancel }: { band: PriorityRecencyBand | null; onSaved: (b: PriorityRecencyBand) => void; onCancel: () => void }) {
  const [name, setName] = useState(band?.name ?? "");
  const [minDays, setMinDays] = useState(band?.min_days ?? 0);
  const [hasMax, setHasMax] = useState(band ? band.max_days !== null : false);
  const [maxDays, setMaxDays] = useState(band?.max_days ?? 10);
  const [contribution, setContribution] = useState(band?.contribution ?? 0);
  const [enabled, setEnabled] = useState(band?.enabled ?? true);
  const [order, setOrder] = useState(band?.order ?? 0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return setError("Заполните название");
    const input: RecencyBandInput = { name: name.trim(), minDays, maxDays: hasMax ? maxDays : null, contribution, enabled, order };
    setIsSubmitting(true);
    setError(null);
    try {
      onSaved(band ? await updateRecencyBand(band.id, input) : await createRecencyBand(input));
    } catch (err) {
      setError(axios.isAxiosError(err) ? (err.response?.data?.detail as string) : "Не удалось сохранить");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-3 flex flex-col gap-3 rounded-lg border border-slate-200 bg-slate-50 p-4">
      <div className="flex flex-wrap gap-3">
        <input className={`w-40 ${inputClass}`} value={name} onChange={(e) => setName(e.target.value)} placeholder="Название" autoFocus />
        <input type="number" min={0} className={`w-24 ${inputClass}`} value={minDays} onChange={(e) => setMinDays(Number(e.target.value))} placeholder="Мин. дней" />
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={hasMax} onChange={(e) => setHasMax(e.target.checked)} className="h-4 w-4 rounded border-slate-300" />
          <input type="number" min={0} disabled={!hasMax} className={`w-24 ${inputClass} disabled:bg-slate-100`} value={maxDays} onChange={(e) => setMaxDays(Number(e.target.value))} placeholder="Макс. дней" />
        </label>
        <input type="number" step="any" className={`w-24 ${inputClass}`} value={contribution} onChange={(e) => setContribution(Number(e.target.value))} placeholder="Вклад" />
        <input type="number" className={`w-20 ${inputClass}`} value={order} onChange={(e) => setOrder(Number(e.target.value))} placeholder="Порядок" />
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} className="h-4 w-4 rounded border-slate-300" /> Включён
        </label>
      </div>
      <div className="flex items-center gap-3">
        <button type="submit" disabled={isSubmitting} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60">
          {isSubmitting ? "…" : "Сохранить"}
        </button>
        <button type="button" onClick={onCancel} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50">
          Отмена
        </button>
        {error && <span className="text-sm text-red-600">{error}</span>}
      </div>
    </form>
  );
}

// --- Стабильность --------------------------------------------------------

function StabilitySection() {
  const [bands, setBands] = useState<PriorityStabilityBand[]>([]);
  const [settings, setSettings] = useState<PrioritySettings | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [editing, setEditing] = useState<PriorityStabilityBand | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function reload() {
    setIsLoading(true);
    try {
      setBands(await listStabilityBands());
    } catch {
      setError("Не удалось загрузить");
    } finally {
      setIsLoading(false);
    }
  }
  useEffect(() => {
    reload();
    getPrioritySettings()
      .then(setSettings)
      .catch(() => {});
  }, []);

  async function handleDelete(band: PriorityStabilityBand) {
    if (!confirm(`Удалить «${band.name}»?`)) return;
    try {
      await deleteStabilityBand(band.id);
      setBands((prev) => prev.filter((b) => b.id !== band.id));
    } catch {
      setError("Не удалось удалить");
    }
  }

  return (
    <Section
      title="Стабильность"
      hint="Доля правильных ответов среди последних попыток (окно задаётся выше) → уровень стабильности → вклад."
      titleExtra={
        <InfoTooltip label="Как считается стабильность">
          <p className="mb-2 font-medium text-slate-900">Фактор «Стабильность»</p>
          <p className="mb-2">
            Отдельный от «Недавних ошибок» фактор — не дублирует их, а спрашивает про другое: не «сколько ошибок», а
            «насколько ровно» отвечает пользователь. Берём % правильных ответов среди последних{" "}
            {settings ? settings.stability_window : "N"} попыток (окно настраивается в разделе весов выше) и смотрим, в
            какой диапазон ниже это попадает. Чем ниже процент — тем менее стабильно слово помнится, и тем выше вклад.
          </p>
          {bands.length > 0 && (
            <TooltipFacts
              rows={[...bands]
                .sort((a, b) => a.min_percent - b.min_percent)
                .map((b) => ({ label: `${b.name} (${b.min_percent}–${b.max_percent}%)`, value: `+${b.contribution}` }))}
            />
          )}
          {settings && <p className="mt-2 text-slate-400">Итоговый вклад в Priority = вклад диапазона × {settings.weight_stability}.</p>}
        </InfoTooltip>
      }
    >
      <button onClick={() => setEditing("new")} className="mb-3 text-sm font-medium text-indigo-600 hover:text-indigo-700">
        + Добавить диапазон
      </button>
      {editing !== null && (
        <StabilityForm
          band={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            setBands((prev) => (editing === "new" ? [...prev, saved] : prev.map((b) => (b.id === saved.id ? saved : b))));
          }}
          onCancel={() => setEditing(null)}
        />
      )}
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {[...bands]
            .sort((a, b) => a.order - b.order)
            .map((band) => (
              <li key={band.id} className={`flex items-center gap-3 rounded-lg border border-slate-200 bg-white p-3 ${band.enabled ? "" : "opacity-50"}`}>
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-slate-900">{band.name}</p>
                  <p className="text-xs text-slate-500">
                    {band.min_percent}–{band.max_percent}% · вклад {band.contribution}
                    {!band.enabled && " · отключён"}
                  </p>
                </div>
                <button onClick={() => setEditing(band)} className="shrink-0 text-sm font-medium text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button onClick={() => handleDelete(band)} className="shrink-0 text-sm text-slate-400 hover:text-red-600">
                  Удалить
                </button>
              </li>
            ))}
        </ul>
      )}
    </Section>
  );
}

function StabilityForm({ band, onSaved, onCancel }: { band: PriorityStabilityBand | null; onSaved: (b: PriorityStabilityBand) => void; onCancel: () => void }) {
  const [name, setName] = useState(band?.name ?? "");
  const [minPercent, setMinPercent] = useState(band?.min_percent ?? 0);
  const [maxPercent, setMaxPercent] = useState(band?.max_percent ?? 100);
  const [contribution, setContribution] = useState(band?.contribution ?? 0);
  const [enabled, setEnabled] = useState(band?.enabled ?? true);
  const [order, setOrder] = useState(band?.order ?? 0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return setError("Заполните название");
    const input: StabilityBandInput = { name: name.trim(), minPercent, maxPercent, contribution, enabled, order };
    setIsSubmitting(true);
    setError(null);
    try {
      onSaved(band ? await updateStabilityBand(band.id, input) : await createStabilityBand(input));
    } catch (err) {
      setError(axios.isAxiosError(err) ? (err.response?.data?.detail as string) : "Не удалось сохранить");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-3 flex flex-col gap-3 rounded-lg border border-slate-200 bg-slate-50 p-4">
      <div className="flex flex-wrap gap-3">
        <input className={`w-40 ${inputClass}`} value={name} onChange={(e) => setName(e.target.value)} placeholder="Название" autoFocus />
        <input type="number" min={0} max={100} className={`w-24 ${inputClass}`} value={minPercent} onChange={(e) => setMinPercent(Number(e.target.value))} placeholder="Мин. %" />
        <input type="number" min={0} max={100} className={`w-24 ${inputClass}`} value={maxPercent} onChange={(e) => setMaxPercent(Number(e.target.value))} placeholder="Макс. %" />
        <input type="number" step="any" className={`w-24 ${inputClass}`} value={contribution} onChange={(e) => setContribution(Number(e.target.value))} placeholder="Вклад" />
        <input type="number" className={`w-20 ${inputClass}`} value={order} onChange={(e) => setOrder(Number(e.target.value))} placeholder="Порядок" />
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} className="h-4 w-4 rounded border-slate-300" /> Включён
        </label>
      </div>
      <div className="flex items-center gap-3">
        <button type="submit" disabled={isSubmitting} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60">
          {isSubmitting ? "…" : "Сохранить"}
        </button>
        <button type="button" onClick={onCancel} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50">
          Отмена
        </button>
        {error && <span className="text-sm text-red-600">{error}</span>}
      </div>
    </form>
  );
}

// --- Priority Level --------------------------------------------------------

function LevelBandsSection() {
  const [bands, setBands] = useState<PriorityLevelBand[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [editing, setEditing] = useState<PriorityLevelBand | "new" | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function reload() {
    setIsLoading(true);
    try {
      setBands(await listPriorityLevelBands());
    } catch {
      setError("Не удалось загрузить");
    } finally {
      setIsLoading(false);
    }
  }
  useEffect(() => {
    reload();
  }, []);

  async function handleDelete(band: PriorityLevelBand) {
    if (!confirm(`Удалить «${band.name}»?`)) return;
    try {
      await deletePriorityLevelBand(band.id);
      setBands((prev) => prev.filter((b) => b.id !== band.id));
    } catch {
      setError("Не удалось удалить");
    }
  }

  return (
    <Section
      title="Итоговый Priority Level"
      hint={
        'Диапазоны финального Priority Score → Критический/Высокий/Средний/Низкий/Минимальный. Роль каждого уровня ' +
        "(автоурок, приоритет в квестах, отвлекающие варианты) определяется РАНГОМ среди этих диапазонов (самый верхний " +
        "= Критический, самый нижний = Минимальный), а не названием -- переименовать можно свободно."
      }
      titleExtra={
        <InfoTooltip label="Что означают уровни приоритета">
          <p className="mb-2 font-medium text-slate-900">Priority Level и где он используется</p>
          <p className="mb-2">
            У каждого диапазона ниже есть системная роль. Она назначается по РАНГУ (позиции по итоговому Score) —
            переименование диапазона роль не меняет:
          </p>
          <ul className="mb-2 flex flex-col gap-1.5">
            {PRIORITY_ROLE_EFFECTS.map(({ key, label, effect }) => {
              const roles = priorityRoleBands(bands);
              const band = roles[key];
              return (
                <li key={key}>
                  <span className="font-medium text-slate-900">{label}</span>
                  {band && (
                    <span className="text-slate-400"> — сейчас «{band.name}» ({formatScoreRange(band.min_score, band.max_score)})</span>
                  )}
                  <div className="text-slate-500">{effect}</div>
                </li>
              );
            })}
          </ul>
          <p className="text-slate-400">
            При меньше чем 5 включённых диапазонах некоторые роли указывают на один и тот же диапазон или ни на какой.
          </p>
        </InfoTooltip>
      }
    >
      <button onClick={() => setEditing("new")} className="mb-3 text-sm font-medium text-indigo-600 hover:text-indigo-700">
        + Добавить диапазон
      </button>
      {editing !== null && (
        <LevelBandForm
          band={editing === "new" ? null : editing}
          onSaved={(saved) => {
            setEditing(null);
            setBands((prev) => (editing === "new" ? [...prev, saved] : prev.map((b) => (b.id === saved.id ? saved : b))));
          }}
          onCancel={() => setEditing(null)}
        />
      )}
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {[...bands]
            .sort((a, b) => b.min_score - a.min_score)
            .map((band) => (
              <li key={band.id} className={`flex items-center gap-3 rounded-lg border border-slate-200 bg-white p-3 ${band.enabled ? "" : "opacity-50"}`}>
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-slate-900">{band.name}</p>
                  <p className="text-xs text-slate-500">
                    {band.min_score}–{band.max_score ?? "∞"}
                    {!band.enabled && " · отключён"}
                  </p>
                </div>
                <button onClick={() => setEditing(band)} className="shrink-0 text-sm font-medium text-indigo-600 hover:text-indigo-700">
                  Изменить
                </button>
                <button onClick={() => handleDelete(band)} className="shrink-0 text-sm text-slate-400 hover:text-red-600">
                  Удалить
                </button>
              </li>
            ))}
        </ul>
      )}
    </Section>
  );
}

function LevelBandForm({ band, onSaved, onCancel }: { band: PriorityLevelBand | null; onSaved: (b: PriorityLevelBand) => void; onCancel: () => void }) {
  const [name, setName] = useState(band?.name ?? "");
  const [minScore, setMinScore] = useState(band?.min_score ?? 0);
  const [hasMax, setHasMax] = useState(band ? band.max_score !== null : false);
  const [maxScore, setMaxScore] = useState(band?.max_score ?? 100);
  const [enabled, setEnabled] = useState(band?.enabled ?? true);
  const [order, setOrder] = useState(band?.order ?? 0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return setError("Заполните название");
    const input: PriorityLevelBandInput = { name: name.trim(), minScore, maxScore: hasMax ? maxScore : null, enabled, order };
    setIsSubmitting(true);
    setError(null);
    try {
      onSaved(band ? await updatePriorityLevelBand(band.id, input) : await createPriorityLevelBand(input));
    } catch (err) {
      setError(axios.isAxiosError(err) ? (err.response?.data?.detail as string) : "Не удалось сохранить");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mb-3 flex flex-col gap-3 rounded-lg border border-slate-200 bg-slate-50 p-4">
      <div className="flex flex-wrap gap-3">
        <input className={`w-40 ${inputClass}`} value={name} onChange={(e) => setName(e.target.value)} placeholder="Название" autoFocus />
        <input type="number" step="any" className={`w-24 ${inputClass}`} value={minScore} onChange={(e) => setMinScore(Number(e.target.value))} placeholder="Мин. очков" />
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={hasMax} onChange={(e) => setHasMax(e.target.checked)} className="h-4 w-4 rounded border-slate-300" />
          <input type="number" step="any" disabled={!hasMax} className={`w-24 ${inputClass} disabled:bg-slate-100`} value={maxScore} onChange={(e) => setMaxScore(Number(e.target.value))} placeholder="Макс. очков" />
        </label>
        <input type="number" className={`w-20 ${inputClass}`} value={order} onChange={(e) => setOrder(Number(e.target.value))} placeholder="Порядок" />
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} className="h-4 w-4 rounded border-slate-300" /> Включён
        </label>
      </div>
      <div className="flex items-center gap-3">
        <button type="submit" disabled={isSubmitting} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60">
          {isSubmitting ? "…" : "Сохранить"}
        </button>
        <button type="button" onClick={onCancel} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50">
          Отмена
        </button>
        {error && <span className="text-sm text-red-600">{error}</span>}
      </div>
    </form>
  );
}

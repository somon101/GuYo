import axios from "axios";
import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import { Link } from "react-router-dom";
import {
  createPriorityLevelBand,
  deletePriorityLevelBand,
  getPrioritySettings,
  listPriorityLevelBands,
  updatePriorityLevelBand,
  updatePrioritySettings,
  type PriorityLevelBandInput,
} from "../api/endpoints";
import { InfoTooltip } from "../components/InfoTooltip";
import { formatScoreRange, PRIORITY_ROLE_EFFECTS, priorityRoleBands } from "../lib/priorityRoles";
import type { PriorityLevelBand, PrioritySettings } from "../types";

const inputClass =
  "field px-3 py-2 text-sm";

/** Priority settings: the memory model's cut-offs, auto-quests and
 * auto-lessons (one settings row), then the named Priority levels. */
export function PrioritySettingsPage() {
  return (
    <div className="mx-auto max-w-3xl">
      <Link to="/exercises" className="text-sm font-medium text-indigo-600 hover:text-indigo-700">
        ← Упражнения
      </Link>
      <h1 className="mb-1 mt-3 text-[26px] font-bold tracking-tight text-slate-900">Приоритет</h1>
      <p className="mb-6 text-sm text-slate-500">
        Насколько срочно слову нужно повторение — считается моделью памяти: по шансу вспомнить слово сейчас. На этом
        приоритете работают авто-уроки, персональные квесты и порядок слов в уроках.
      </p>

      <WeightsSection />
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

// --- Веса факторов -----------------------------------------------------

function WeightsSection() {
  const [settings, setSettings] = useState<PrioritySettings | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    getPrioritySettings()
      .then(setSettings)
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
          className={`w-full max-w-[8rem] ${inputClass}`}
          value={settings[key] as number}
          onChange={(e) => setSettings({ ...settings, [key]: Number(e.target.value) })}
        />
        {hint && <p className="mt-1 text-xs text-slate-400">{hint}</p>}
      </div>
    );
  }

  return (
    <Section
      title="Настройки"
      hint="Авто-уроки, персональные квесты и границы модели памяти."
    >
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : !settings ? (
        <p className="text-sm text-red-600">{error}</p>
      ) : (
        <form onSubmit={handleSubmit} className="flex flex-col gap-4 card p-4">
          <div className="pt-1">
            <p className="mb-3 flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-slate-400">
              Персональные квесты
              <InfoTooltip label="Как создаются персональные квесты">
                <p className="mb-2 font-medium text-slate-900">Персональный авто-квест</p>
                <p className="mb-2">
                  Backend сам создаёт квест для пользователя, когда одновременно выполняются 2 условия:
                </p>
                <p className="mb-2">
                  1) слово сейчас на приоритете Высокий или Средний;
                  <br />
                  2) среди таких слов есть упражнение, где они массово ошибаются — оно и становится упражнением квеста.
                </p>
                <p className="mb-2">
                  Слово «слабое» в упражнении, если попыток в нём ≥ {settings.personal_quest_min_attempts} и доля
                  ошибок ≥ {Math.round(settings.personal_quest_weak_error_rate * 100)}%.
                </p>
                <p>
                  Квест создаётся, если таких слов набралось от {settings.personal_quest_min_words} до{" "}
                  {settings.personal_quest_max_words} (самые срочные по Priority Score — первыми). Пока текущий не
                  пройден полностью — новый для этого пользователя не создаётся.
                </p>
              </InfoTooltip>
            </p>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
              {field("personal_quest_min_words", "Мин. слов")}
              {field("personal_quest_max_words", "Макс. слов")}
              {field("personal_quest_reward_points", "Награда (очки рейтинга)")}
              {field("personal_quest_min_attempts", "Мин. попыток для «слабости»")}
              {field(
                "personal_quest_weak_error_rate",
                "Порог доли ошибок (0–1)",
                "0.5 значит: половина или больше попыток в упражнении — ошибки.",
              )}
            </div>
          </div>
          <div className="border-t border-slate-100 pt-4">
            <p className="mb-3 flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-slate-400">
              Авто-уроки
              <InfoTooltip label="Что такое авто-урок">
                Урок, который сервер собирает сам из слов с самым высоким приоритетом («критические»: начатые, но ещё
                не выученные). Создаётся тихо, уже после того как человек вышел из программы. Число ниже — сколько
                таких слов должно накопиться, прежде чем урок появится: больше — реже, меньше — чаще.
              </InfoTooltip>
            </p>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
              {field("adaptive_lesson_min_words", "Критических слов для авто-урока")}
            </div>
          </div>
          <div className="border-t border-slate-100 pt-4">
            <p className="mb-3 flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-slate-400">
              Модель памяти
              <InfoTooltip label="Что такое модель памяти">
                Для каждого слова считается R — вероятность, что человек вспомнит его сейчас. Она растёт от правильных
                ответов в разные дни и падает со временем. По R считаются уровни приоритета; изученное слово с R ниже
                цели попадает в «Повторить сегодня».
              </InfoTooltip>
            </p>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              {field("memory_target_retention", "Цель (повторять ниже)", "0.9 = повторять, когда шанс вспомнить ниже 90%.")}
              {field("memory_critical_below", "Критический ниже", "Слова с R ниже — критические (автоурок).")}
              {field("memory_high_below", "Высокий ниже", "Между критическим и этим — высокий; дальше до цели — средний.")}
              {field("memory_minimal_above", "Минимальный от", "Слова с R выше — точно помнит (отвлекающие варианты).")}
            </div>
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

// --- Уровни Priority -----------------------------------------------------

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
        "= Критический, самый нижний = Минимальный), а не названием — переименовать можно свободно."
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
              <li key={band.id} className={`flex items-center gap-3 card p-3 ${band.enabled ? "" : "opacity-50"}`}>
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
    <form onSubmit={handleSubmit} className="mb-3 flex flex-col gap-3 rounded-[14px] bg-slate-50 p-4">
      <div className="flex flex-wrap gap-3">
        <Labeled label="Название">
          <input className={`w-40 ${inputClass}`} value={name} onChange={(e) => setName(e.target.value)} placeholder="Высокий" autoFocus />
        </Labeled>
        <Labeled label="От, баллов приоритета">
          <input type="number" step="any" className={`w-24 ${inputClass}`} value={minScore} onChange={(e) => setMinScore(Number(e.target.value))} />
        </Labeled>
        <MaxField label="До, баллов приоритета" hasMax={hasMax} onHasMax={setHasMax}>
          <input type="number" step="any" disabled={!hasMax} className={`w-24 ${inputClass} disabled:bg-slate-100`} value={maxScore} onChange={(e) => setMaxScore(Number(e.target.value))} />
        </MaxField>
        <OrderField value={order} onChange={setOrder} />
        <EnabledField checked={enabled} onChange={setEnabled} />
      </div>
      <div className="flex items-center gap-3">
        <button type="submit" disabled={isSubmitting} className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60">
          {isSubmitting ? "…" : "Сохранить"}
        </button>
        <button type="button" onClick={onCancel} className="btn-tinted rounded-md px-4 py-2 text-sm font-medium">
          Отмена
        </button>
        {error && <span className="text-sm text-red-600">{error}</span>}
      </div>
    </form>
  );
}

/** A band form's field with a label that stays visible — a placeholder
 * alone disappears as soon as the field holds a number. */
function Labeled({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="flex items-center gap-1.5 text-xs font-medium text-slate-500">
        {label}
        {hint && <InfoTooltip>{hint}</InfoTooltip>}
      </span>
      {children}
    </div>
  );
}

/** The upper bound, with the switch that turns it off ("и выше"). */
function MaxField({
  label,
  hasMax,
  onHasMax,
  children,
}: {
  label: string;
  hasMax: boolean;
  onHasMax: (value: boolean) => void;
  children: ReactNode;
}) {
  return (
    <Labeled label={label} hint="Выключите переключатель, чтобы у диапазона не было верхней границы («и выше»).">
      <div className="flex h-[38px] items-center gap-2">
        <input
          type="checkbox"
          aria-label="Есть верхняя граница"
          checked={hasMax}
          onChange={(e) => onHasMax(e.target.checked)}
          className="switch"
        />
        {hasMax ? children : <span className="w-24 text-sm text-slate-500">и выше</span>}
      </div>
    </Labeled>
  );
}

function OrderField({ value, onChange }: { value: number; onChange: (value: number) => void }) {
  return (
    <Labeled label="Порядок" hint="Только место строки в этом списке. На расчёт приоритета не влияет.">
      <input type="number" className={`w-20 ${inputClass}`} value={value} onChange={(e) => onChange(Number(e.target.value))} />
    </Labeled>
  );
}

function EnabledField({ checked, onChange }: { checked: boolean; onChange: (value: boolean) => void }) {
  return (
    <Labeled label="Включён" hint="Выключенный диапазон не используется в расчёте.">
      <label className="flex h-[38px] items-center">
        <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="switch" />
      </label>
    </Labeled>
  );
}

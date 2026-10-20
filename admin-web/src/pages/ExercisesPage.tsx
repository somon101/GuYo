import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getLearningSettings, updateLearningSettings } from "../api/endpoints";
import { NavIcon } from "../components/NavIcon";

// Just an index of exercises — each one's settings live on their own page
// (pages/exercises/*SettingsPage.tsx) so a future exercise's settings never
// have to be squeezed into a shared form alongside every other exercise's.
const EXERCISES: { to: string; label: string; hint: string; icon: string }[] = [
  { to: "/exercises/true_or_false", label: "Правда или ложь", hint: "Верный ли перевод", icon: "truefalse" },
  { to: "/exercises/matching", label: "Сопоставление", hint: "Пары слово — перевод", icon: "link" },
  { to: "/exercises/build_word", label: "Собери слово", hint: "Слово из букв", icon: "letters" },
  { to: "/exercises/speaking_word", label: "Произнеси слово", hint: "Распознавание речи", icon: "mic" },
  { to: "/exercises/listen_word", label: "Услышь слово", hint: "Выбор по звуку", icon: "speaker" },
];

const WORD_SETTINGS: typeof EXERCISES = [
  { to: "/exercises/word-levels", label: "Уровни слов", hint: "Шкала изученности", icon: "layers" },
  { to: "/exercises/priority", label: "Приоритет", hint: "Какие слова чаще", icon: "flag" },
];

function Tiles({ items }: { items: typeof EXERCISES }) {
  return (
    <ul className="grid grid-cols-2 gap-3 lg:grid-cols-3">
      {items.map((item) => (
        <li key={item.to}>
          <Link to={item.to} className="flex h-full items-center gap-3 card card-link p-4">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-indigo-50 text-indigo-600">
              <NavIcon name={item.icon} />
            </span>
            <span className="min-w-0">
              <span className="block truncate text-[15px] font-semibold text-slate-900">{item.label}</span>
              <span className="block truncate text-[13px] text-slate-500">{item.hint}</span>
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export function ExercisesPage() {
  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="mb-6 text-[26px] font-bold tracking-tight text-slate-900">Упражнения</h1>
      <Tiles items={EXERCISES} />
      <h2 className="mb-3 mt-8 text-sm font-semibold uppercase tracking-wide text-slate-500">Настройки слов</h2>
      <Tiles items={WORD_SETTINGS} />
      <h2 className="mb-3 mt-8 text-sm font-semibold uppercase tracking-wide text-slate-500">Уроки</h2>
      <MaxLessonWords />
      <h2 className="mb-3 mt-8 text-sm font-semibold uppercase tracking-wide text-slate-500">Проверка слов перед уроком</h2>
      <WordCheckSettings />
    </div>
  );
}

/** The most words a person can pick for one lesson (random count or by hand). */
function MaxLessonWords() {
  const [value, setValue] = useState<number | null>(null);
  const [saved, setSaved] = useState<number | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    getLearningSettings()
      .then((s) => {
        setValue(s.max_lesson_words);
        setSaved(s.max_lesson_words);
      })
      .catch(() => setMessage("Не удалось загрузить"));
  }, []);

  async function save() {
    if (value == null) return;
    setMessage(null);
    try {
      const s = await updateLearningSettings({ max_lesson_words: value });
      setSaved(s.max_lesson_words);
      setMessage("Сохранено");
    } catch {
      setMessage("Не удалось сохранить: от 4 до 50");
    }
  }

  return (
    <div className="card flex flex-wrap items-end gap-3 p-4">
      <label className="text-sm text-slate-700">
        <span className="mb-1 block text-xs text-slate-500">Максимум слов в одном уроке (4–50)</span>
        <input
          type="number"
          min={4}
          max={50}
          className="field w-28 px-3 py-2 text-sm"
          value={value ?? ""}
          onChange={(e) => setValue(e.target.value === "" ? null : Number(e.target.value))}
        />
      </label>
      <button
        onClick={save}
        disabled={value == null || value === saved || value < 4 || value > 50}
        className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
      >
        Сохранить
      </button>
      {message && <span className="text-sm text-slate-500">{message}</span>}
      <p className="w-full text-xs text-slate-400">
        Столько слов человек сможет выбрать для нового урока — случайно или вручную. Новое число сразу
        видно в приложении.
      </p>
    </div>
  );
}

/** The card check before a lesson: a card per word, then "how easy was it". */
function WordCheckSettings() {
  const [enabled, setEnabled] = useState<boolean | null>(null);
  const [skipAllowed, setSkipAllowed] = useState<boolean | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    getLearningSettings()
      .then((s) => {
        setEnabled(s.check_enabled);
        setSkipAllowed(s.check_skip_allowed);
      })
      .catch(() => setMessage("Не удалось загрузить"));
  }, []);

  async function change(patch: { check_enabled?: boolean; check_skip_allowed?: boolean }) {
    setMessage(null);
    try {
      const s = await updateLearningSettings(patch);
      setEnabled(s.check_enabled);
      setSkipAllowed(s.check_skip_allowed);
      setMessage("Сохранено");
    } catch {
      setMessage("Не удалось сохранить");
    }
  }

  return (
    <div className="card flex flex-col gap-3 p-4">
      <label className="flex items-center gap-2 text-sm text-slate-700">
        <input
          type="checkbox"
          checked={enabled ?? false}
          disabled={enabled == null}
          onChange={(e) => change({ check_enabled: e.target.checked })}
        />
        Показывать проверку перед первым прохождением урока
      </label>
      <label className="flex items-center gap-2 text-sm text-slate-700">
        <input
          type="checkbox"
          checked={skipAllowed ?? false}
          disabled={skipAllowed == null || !enabled}
          onChange={(e) => change({ check_skip_allowed: e.target.checked })}
        />
        Разрешить кнопку «Пропустить»
      </label>
      {message && <span className="text-sm text-slate-500">{message}</span>}
      <p className="text-xs text-slate-400">
        Человек видит карточку слова с четырьмя вариантами перевода и оценивает, насколько ему было легко
        (угадал / трудно / нормально / легко). Это только подсказка модели памяти: слово не становится изученным,
        а «легко» делает повторение реже. Пропуск ничего не записывает.
      </p>
    </div>
  );
}

import { Link } from "react-router-dom";
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
    </div>
  );
}

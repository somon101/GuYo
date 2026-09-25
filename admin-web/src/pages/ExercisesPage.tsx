import { Link } from "react-router-dom";

// Just an index of exercises -- each one's settings live on their own page
// (pages/exercises/*SettingsPage.tsx) so a future exercise's settings never
// have to be squeezed into a shared form alongside every other exercise's.
const EXERCISES: { key: string; label: string }[] = [
  { key: "true_or_false", label: "Правда или ложь" },
  { key: "matching", label: "Сопоставление" },
  { key: "build_word", label: "Собери слово" },
  { key: "speaking_word", label: "Произнеси слово 🎙️" },
  { key: "listen_word", label: "Услышь слово 🔊" },
];

export function ExercisesPage() {
  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-6 text-xl font-semibold text-slate-900">Упражнения</h1>
      <ul className="flex flex-col gap-3">
        {EXERCISES.map((ex) => (
          <li key={ex.key}>
            <Link
              to={`/exercises/${ex.key}`}
              className="flex items-center justify-between rounded-lg border border-slate-200 bg-white p-5 hover:border-indigo-300 hover:bg-indigo-50/40"
            >
              <span className="text-base font-medium text-slate-900">{ex.label}</span>
              <span className="text-slate-400">→</span>
            </Link>
          </li>
        ))}
        <li>
          <Link
            to="/exercises/word-levels"
            className="flex items-center justify-between rounded-lg border border-slate-200 bg-white p-5 hover:border-indigo-300 hover:bg-indigo-50/40"
          >
            <span className="text-base font-medium text-slate-900">Уровни слов</span>
            <span className="text-slate-400">→</span>
          </Link>
        </li>
        <li>
          <Link
            to="/exercises/priority"
            className="flex items-center justify-between rounded-lg border border-slate-200 bg-white p-5 hover:border-indigo-300 hover:bg-indigo-50/40"
          >
            <span className="text-base font-medium text-slate-900">Приоритет</span>
            <span className="text-slate-400">→</span>
          </Link>
        </li>
      </ul>
    </div>
  );
}

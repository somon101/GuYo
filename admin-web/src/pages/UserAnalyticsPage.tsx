import { useEffect, useState } from "react";
import {
  getUserPhraseAnalytics,
  listAnalyticsDictionaries,
  listUsers,
} from "../api/endpoints";
import type {
  AdminUser,
  AnalyticsDictionary,
  NearPhrase,
  UserPhraseAnalytics,
  WordImpact,
} from "../types";

const PAGE_SIZE = 10;

/** Read-only report over data that already exists (Word/WordForm/
 * WordProgress/Phrase), built on the exact same "is this phrase available"
 * definition the app's own "Мои фразы" uses -- every number here comes
 * straight from the backend (see GET /admin/analytics/users/{id}), this
 * page only renders it. Nothing is computed client-side from raw
 * word/phrase lists. */
export function UserAnalyticsPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [dictionaries, setDictionaries] = useState<AnalyticsDictionary[]>([]);
  const [isLoadingOptions, setIsLoadingOptions] = useState(true);
  const [optionsError, setOptionsError] = useState<string | null>(null);

  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [selectedDictionaryId, setSelectedDictionaryId] = useState<number | null>(null);

  const [analytics, setAnalytics] = useState<UserPhraseAnalytics | null>(null);
  const [isLoadingAnalytics, setIsLoadingAnalytics] = useState(false);
  const [analyticsError, setAnalyticsError] = useState<string | null>(null);

  useEffect(() => {
    setIsLoadingOptions(true);
    setOptionsError(null);
    Promise.all([listUsers(), listAnalyticsDictionaries()])
      .then(([userList, dictList]) => {
        setUsers(userList);
        setDictionaries(dictList);
        if (dictList.length > 0) setSelectedDictionaryId(dictList[0].id);
      })
      .catch(() => setOptionsError("Не удалось загрузить список пользователей и языков"))
      .finally(() => setIsLoadingOptions(false));
  }, []);

  useEffect(() => {
    if (selectedUserId == null || selectedDictionaryId == null) {
      setAnalytics(null);
      return;
    }
    setIsLoadingAnalytics(true);
    setAnalyticsError(null);
    getUserPhraseAnalytics(selectedUserId, selectedDictionaryId)
      .then(setAnalytics)
      .catch(() => setAnalyticsError("Не удалось загрузить аналитику для этого пользователя"))
      .finally(() => setIsLoadingAnalytics(false));
  }, [selectedUserId, selectedDictionaryId]);

  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="mb-1 text-xl font-semibold text-slate-900">Аналитика пользователей</h1>
      <p className="mb-6 text-sm text-slate-500">
        Изучение слов и открытие фраз конкретного пользователя.
      </p>

      {isLoadingOptions ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : optionsError ? (
        <p className="text-sm text-red-600">{optionsError}</p>
      ) : dictionaries.length === 0 ? (
        <p className="text-sm text-slate-500">Пока нет ни одного языка с фразами — аналитике не из чего строиться.</p>
      ) : (
        <>
          <div className="mb-6 flex flex-wrap items-center gap-3">
            <select
              className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
              value={selectedUserId ?? ""}
              onChange={(e) => setSelectedUserId(e.target.value ? Number(e.target.value) : null)}
            >
              <option value="">Выберите пользователя…</option>
              {users.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.login}
                </option>
              ))}
            </select>

            {dictionaries.length > 1 && (
              <select
                className="rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
                value={selectedDictionaryId ?? ""}
                onChange={(e) => setSelectedDictionaryId(e.target.value ? Number(e.target.value) : null)}
              >
                {dictionaries.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.name}
                  </option>
                ))}
              </select>
            )}
          </div>

          {selectedUserId == null ? (
            <p className="text-sm text-slate-500">Выберите пользователя, чтобы увидеть аналитику.</p>
          ) : isLoadingAnalytics ? (
            <p className="text-sm text-slate-500">Загрузка аналитики…</p>
          ) : analyticsError ? (
            <p className="text-sm text-red-600">{analyticsError}</p>
          ) : analytics ? (
            <AnalyticsReport data={analytics} />
          ) : null}
        </>
      )}
    </div>
  );
}

function AnalyticsReport({ data }: { data: UserPhraseAnalytics }) {
  return (
    <div className="flex flex-col gap-6">
      <StatCards data={data} />
      <NearPhrasesSection phrases={data.near_phrases} />
      <TopWordsSection words={data.top_words} />
      <OpenPhrasesSection phrases={data.open_phrases} />
    </div>
  );
}

function StatCards({ data }: { data: UserPhraseAnalytics }) {
  const cards: { label: string; value: string }[] = [
    { label: "Слов изучено", value: `${data.learned_word_count} / ${data.total_word_count}` },
    { label: "Фраз открыто", value: `${data.open_phrase_count} / ${data.total_phrase_count}` },
    { label: "Осталось открыть", value: `${data.remaining_phrase_count}` },
    { label: "Порог изучения слова", value: `${data.threshold}` },
  ];
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
      {cards.map((c) => (
        <div key={c.label} className="rounded-lg border border-slate-200 bg-white p-4">
          <div className="text-2xl font-semibold text-slate-900">{c.value}</div>
          <div className="text-xs text-slate-500">{c.label}</div>
        </div>
      ))}
    </div>
  );
}

function tierFor(missing: number): { label: string; className: string } {
  if (missing <= 1) return { label: "Почти открыта", className: "bg-emerald-50 text-emerald-700 border-emerald-200" };
  if (missing === 2) return { label: "Близкая", className: "bg-amber-50 text-amber-700 border-amber-200" };
  return { label: "В перспективе", className: "bg-slate-100 text-slate-600 border-slate-200" };
}

function NearPhrasesSection({ phrases }: { phrases: NearPhrase[] }) {
  const [showAll, setShowAll] = useState(false);
  if (phrases.length === 0) {
    return (
      <Section title="Ближайшие фразы к открытию">
        <p className="text-sm text-slate-500">
          Для этого пользователя нет фраз, ожидающих открытия — либо всё уже открыто, либо ещё нет ни одного
          изученного слова, приближающего к какой-либо фразе.
        </p>
      </Section>
    );
  }
  const visible = showAll ? phrases : phrases.slice(0, PAGE_SIZE);
  return (
    <Section title="Ближайшие фразы к открытию">
      <ul className="flex flex-col gap-2">
        {visible.map((p) => {
          const missing = p.total_count - p.learned_count;
          const tier = tierFor(missing);
          return (
            <li key={p.phrase_id} className="rounded-lg border border-slate-200 bg-white p-3">
              <div className="mb-1.5 flex items-center justify-between gap-2">
                <span className="font-medium text-slate-900" translate="no">
                  {p.original}
                </span>
                <span className={`shrink-0 rounded-full border px-2 py-0.5 text-xs font-medium ${tier.className}`}>
                  {tier.label}
                </span>
              </div>
              <div className="mb-1.5 h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
                <div
                  className="h-full rounded-full bg-indigo-500"
                  style={{ width: `${(p.learned_count / p.total_count) * 100}%` }}
                />
              </div>
              <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 text-xs text-slate-500">
                <span>
                  {p.learned_count} / {p.total_count} слов
                </span>
                <span>
                  Осталось изучить:{" "}
                  <span className="font-medium text-slate-700" translate="no">
                    {p.missing_words.map((m) => m.text).join(", ")}
                  </span>
                </span>
              </div>
            </li>
          );
        })}
      </ul>
      {phrases.length > PAGE_SIZE && (
        <ShowAllButton expanded={showAll} onClick={() => setShowAll((v) => !v)} total={phrases.length} />
      )}
    </Section>
  );
}

function TopWordsSection({ words }: { words: WordImpact[] }) {
  const [showAll, setShowAll] = useState(false);
  const [expandedWordId, setExpandedWordId] = useState<number | null>(null);
  if (words.length === 0) {
    return (
      <Section title="Какие слова дадут больше фраз">
        <p className="text-sm text-slate-500">
          Пока ни одно ещё не изученное слово не является единственным недостающим словом для какой-либо фразы.
        </p>
      </Section>
    );
  }
  const visible = showAll ? words : words.slice(0, PAGE_SIZE);
  return (
    <Section title="Какие слова дадут больше фраз">
      <ul className="flex flex-col gap-1.5">
        {visible.map((w) => {
          const isExpanded = expandedWordId === w.word_id;
          return (
            <li key={w.word_id} className="rounded-lg border border-slate-200 bg-white">
              <button
                type="button"
                onClick={() => setExpandedWordId(isExpanded ? null : w.word_id)}
                className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left"
              >
                <span className="font-medium text-slate-900" translate="no">
                  {w.word}
                </span>
                <span className="flex items-center gap-2 text-sm">
                  <span className="rounded-full bg-indigo-50 px-2 py-0.5 font-medium text-indigo-700">
                    +{w.new_phrase_count} {phraseWord(w.new_phrase_count)}
                  </span>
                  <span className="text-slate-400">{isExpanded ? "▲" : "▼"}</span>
                </span>
              </button>
              {isExpanded && <SamplePhrasesList phrases={w.sample_phrases} />}
            </li>
          );
        })}
      </ul>
      {words.length > PAGE_SIZE && (
        <ShowAllButton expanded={showAll} onClick={() => setShowAll((v) => !v)} total={words.length} />
      )}
    </Section>
  );
}

function SamplePhrasesList({ phrases }: { phrases: string[] }) {
  const [showAll, setShowAll] = useState(false);
  const visible = showAll ? phrases : phrases.slice(0, PAGE_SIZE);
  return (
    <div className="border-t border-slate-100 px-3 py-2">
      <ul className="flex flex-col gap-1 text-sm text-slate-600">
        {visible.map((p, i) => (
          <li key={i} translate="no">
            {p}
          </li>
        ))}
      </ul>
      {phrases.length > PAGE_SIZE && (
        <ShowAllButton expanded={showAll} onClick={() => setShowAll((v) => !v)} total={phrases.length} />
      )}
    </div>
  );
}

function OpenPhrasesSection({ phrases }: { phrases: { phrase_id: number; original: string; translation_tg: string; category_name: string | null }[] }) {
  const [showAll, setShowAll] = useState(false);
  if (phrases.length === 0) {
    return (
      <Section title="Открытые фразы">
        <p className="text-sm text-slate-500">У этого пользователя пока нет открытых фраз.</p>
      </Section>
    );
  }
  const visible = showAll ? phrases : phrases.slice(0, PAGE_SIZE);
  return (
    <Section title="Открытые фразы">
      <ul className="flex flex-col gap-2">
        {visible.map((p) => (
          <li
            key={p.phrase_id}
            className="flex items-center justify-between gap-3 rounded-lg border border-slate-200 bg-white p-3"
          >
            <div>
              <div className="font-medium text-slate-900" translate="no">
                {p.original}
              </div>
              <div className="text-sm text-slate-500" translate="no">
                {p.translation_tg}
              </div>
              {p.category_name && <div className="mt-0.5 text-xs text-slate-400">{p.category_name}</div>}
            </div>
            <span className="shrink-0 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700">
              Открыта
            </span>
          </li>
        ))}
      </ul>
      {phrases.length > PAGE_SIZE && (
        <ShowAllButton expanded={showAll} onClick={() => setShowAll((v) => !v)} total={phrases.length} />
      )}
    </Section>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h2>
      {children}
    </section>
  );
}

function ShowAllButton({ expanded, onClick, total }: { expanded: boolean; onClick: () => void; total: number }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="mt-2 text-sm font-medium text-indigo-600 hover:text-indigo-700"
    >
      {expanded ? "Свернуть" : `Показать все (${total})`}
    </button>
  );
}

function phraseWord(count: number): string {
  const mod10 = count % 10;
  const mod100 = count % 100;
  if (mod10 === 1 && mod100 !== 11) return "фраза";
  if ([2, 3, 4].includes(mod10) && ![12, 13, 14].includes(mod100)) return "фразы";
  return "фраз";
}

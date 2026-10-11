import { useEffect, useState } from "react";
import { getUserMiniPhraseAnalytics } from "../api/endpoints";
import type { MiniPhraseNear, UserMiniPhraseAnalytics } from "../types";

const PAGE_SIZE = 10;

/** «Мини-фразы» on a user's analytics: the phrase report's twin. A
 * mini-phrase opens once every part's word is learned, and is done once
 * the user has gone through it in a lesson. */
export function MiniPhraseAnalytics({ userId, dictionaryId }: { userId: number; dictionaryId: number }) {
  const [data, setData] = useState<UserMiniPhraseAnalytics | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setData(null);
    setError(null);
    getUserMiniPhraseAnalytics(userId, dictionaryId)
      .then(setData)
      .catch(() => setError("Не удалось загрузить аналитику мини-фраз"));
  }, [userId, dictionaryId]);

  return (
    <div className="mt-10 flex flex-col gap-6">
      <h2 className="text-[22px] font-bold tracking-tight text-slate-900">Мини-фразы</h2>
      {error ? (
        <p className="text-sm text-red-600">{error}</p>
      ) : !data ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : data.total_count === 0 ? (
        <p className="text-sm text-slate-500">В этом языке пока нет мини-фраз.</p>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              { label: "Пройдено", value: `${data.done_count} / ${data.total_count}` },
              { label: "Доступно сейчас", value: `${data.available_count}` },
              { label: "Почти доступны", value: `${data.near.length}` },
              { label: "Очков за мини-фразы", value: `${data.points_total}` },
            ].map((c) => (
              <div key={c.label} className="card p-4">
                <div className="text-2xl font-semibold text-slate-900">{c.value}</div>
                <div className="text-xs text-slate-500">{c.label}</div>
              </div>
            ))}
          </div>

          <Block title="Доступны сейчас (все слова выучены, ещё не пройдены)" empty="Нет доступных — все открытые уже пройдены.">
            {data.available.map((m) => (
              <Row key={m.mini_phrase_id} m={m} />
            ))}
          </Block>

          <Block title="Ближайшие к открытию" empty="Нет мини-фраз, которым не хватает слов.">
            {data.near.map((m) => (
              <Row key={m.mini_phrase_id} m={m} />
            ))}
          </Block>

          <Block title="Какие слова откроют больше мини-фраз" empty="Ни одно слово пока не открывает мини-фразу в одиночку.">
            {data.top_words.map((w) => (
              <li key={w.word_id} className="card flex items-center justify-between gap-3 px-3 py-2">
                <span className="font-medium text-slate-900" translate="no">
                  {w.word}
                </span>
                <span className="truncate text-sm text-slate-500" translate="no">
                  {w.sample_phrases.join(" · ")}
                </span>
                <span className="shrink-0 rounded-full bg-indigo-50 px-2 py-0.5 text-sm font-medium text-indigo-700">
                  +{w.new_phrase_count}
                </span>
              </li>
            ))}
          </Block>

          <Block title="Пройденные" empty="Пользователь ещё не прошёл ни одной мини-фразы.">
            {data.done.map((m) => (
              <li key={m.mini_phrase_id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                <span className="font-medium text-slate-900" translate="no">
                  {m.text}
                </span>
                <span className="text-sm text-slate-500" translate="no">
                  {m.translation_tg}
                </span>
                {m.template_name && <span className="text-xs text-slate-400">{m.template_name}</span>}
                <span className="ml-auto text-xs text-slate-500">
                  {new Date(m.done_at).toLocaleDateString("ru-RU")}
                  {m.points != null && <span className="ml-2 font-medium text-emerald-700">+{m.points}</span>}
                </span>
              </li>
            ))}
          </Block>
        </>
      )}
    </div>
  );
}

function Row({ m }: { m: MiniPhraseNear }) {
  return (
    <li className="card p-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <span className="font-medium text-slate-900" translate="no">
          {m.text}
        </span>
        <span className="text-sm text-slate-500" translate="no">
          {m.translation_tg}
        </span>
        {m.template_name && <span className="text-xs text-slate-400">{m.template_name}</span>}
        <span className="ml-auto text-xs font-medium text-slate-500">
          {m.learned_count} из {m.total_count} слов
        </span>
      </div>
      {m.missing_words.length > 0 && (
        <p className="mt-1 text-sm text-amber-700" translate="no">
          Не хватает: {m.missing_words.map((w) => w.text).join(", ")}
        </p>
      )}
    </li>
  );
}

function Block({ title, empty, children }: { title: string; empty: string; children: React.ReactNode[] }) {
  const [showAll, setShowAll] = useState(false);
  const visible = showAll ? children : children.slice(0, PAGE_SIZE);
  return (
    <section>
      <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h3>
      {children.length === 0 ? (
        <p className="text-sm text-slate-500">{empty}</p>
      ) : (
        <ul className="flex flex-col gap-1.5">{visible}</ul>
      )}
      {children.length > PAGE_SIZE && (
        <button type="button" onClick={() => setShowAll((v) => !v)} className="mt-2 text-sm font-medium text-indigo-600">
          {showAll ? "Свернуть" : `Показать все (${children.length})`}
        </button>
      )}
    </section>
  );
}

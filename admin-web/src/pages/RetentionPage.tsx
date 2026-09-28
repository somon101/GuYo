import { useEffect, useState, type ReactNode } from "react";
import { getRetention } from "../api/endpoints";
import { InfoTooltip } from "../components/InfoTooltip";
import { DailyColumnChart } from "../components/MiniCharts";
import { SegmentedControl } from "../components/SegmentedControl";
import type { Retention, RetentionGroup, RetentionRate } from "../types";

type Audience = "all" | "self";

// Same wording the app's own sign-up shows (mobile/lib/screens/register_screen.dart).
const SOURCE_LABELS: Record<string, string> = {
  social: "Социальные сети",
  youtube: "YouTube",
  telegram: "Telegram",
  search: "Поисковик",
  friends: "От друзей или знакомых",
  ads: "Реклама",
  other: "Другое",
};

const WINDOWS: { key: "next_day" | "week_later" | "month_later"; title: string; short: string; help: string }[] = [
  {
    key: "next_day",
    title: "Вернулись на следующий день",
    short: "След. день",
    help: "Доля людей, которые открыли приложение на следующий день после регистрации. Считаются только те, кто зарегистрировался не позже вчерашнего дня.",
  },
  {
    key: "week_later",
    title: "Вернулись через неделю и позже",
    short: "Через неделю",
    help: "Доля людей, которые открыли приложение через 7 дней после регистрации или позже. Считаются только те, кто зарегистрировался хотя бы 7 дней назад.",
  },
  {
    key: "month_later",
    title: "Вернулись через месяц и позже",
    short: "Через месяц",
    help: "Доля людей, которые открыли приложение через 30 дней после регистрации или позже. Считаются только те, кто зарегистрировался хотя бы 30 дней назад.",
  },
];

// Server dates are UTC calendar days -- format them in UTC so a day never
// shifts by one in the admin's own timezone.
const dayFormat = new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short", timeZone: "UTC" });
const percentFormat = new Intl.NumberFormat("ru-RU", { maximumFractionDigits: 1 });

function formatDay(iso: string): string {
  return dayFormat.format(new Date(`${iso}T00:00:00Z`));
}

function formatWeek(weekStart: string): string {
  const end = new Date(`${weekStart}T00:00:00Z`);
  end.setUTCDate(end.getUTCDate() + 6);
  return `${formatDay(weekStart)} – ${dayFormat.format(end)}`;
}

/** Everything here is computed by GET /admin/analytics/retention; this page
 * only renders it. */
export function RetentionPage() {
  const [audience, setAudience] = useState<Audience>("all");
  const [data, setData] = useState<Retention | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  function changeAudience(value: Audience) {
    setAudience(value);
    setIsLoading(true);
    setError(null);
  }

  useEffect(() => {
    let cancelled = false;
    getRetention(audience === "self")
      .then((result) => {
        if (!cancelled) setData(result);
      })
      .catch(() => {
        if (!cancelled) setError("Не удалось загрузить данные об удержании");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [audience]);

  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">Удержание</h1>
      <p className="mb-5 text-sm text-slate-500">Сколько людей возвращаются в приложение после регистрации.</p>

      <div className="mb-6 flex flex-wrap items-center gap-3">
        <SegmentedControl<Audience>
          ariaLabel="Какие аккаунты считать"
          segments={[
            { value: "all", label: "Все аккаунты" },
            { value: "self", label: "Из приложения" },
          ]}
          value={audience}
          onChange={changeAudience}
        />
        <InfoTooltip>
          «Из приложения» — только аккаунты, созданные через регистрацию в приложении. Аккаунты, созданные в админке
          (тестовые, боты), сюда не входят.
        </InfoTooltip>
      </div>

      {error ? (
        <p className="text-sm text-red-600">{error}</p>
      ) : !data ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : (
        <div className={`flex flex-col gap-6 transition-opacity ${isLoading ? "opacity-60" : ""}`}>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <StatTile label="Всего аккаунтов" value={data.signups} />
            <StatTile label="Открывали сегодня" value={data.active_today} />
            <StatTile label="За 7 дней" value={data.active_7d} />
            <StatTile label="За 30 дней" value={data.active_30d} />
          </div>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            {WINDOWS.map((w) => (
              <RateTile key={w.key} title={w.title} help={w.help} rate={data[w.key]} />
            ))}
          </div>

          <Section title="Регистрации по дням">
            <DailyColumnChart
              summary={`За 30 дней: ${data.days.reduce((sum, d) => sum + d.signups, 0)}`}
              points={data.days.map((d) => ({ key: d.day, label: formatDay(d.day), value: d.signups }))}
            />
          </Section>

          <Section title="Открывали приложение по дням">
            <DailyColumnChart
              summary={`Сегодня: ${data.days[data.days.length - 1]?.active ?? 0}`}
              points={data.days.map((d) => ({ key: d.day, label: formatDay(d.day), value: d.active }))}
            />
          </Section>

          <Section title="По неделям регистрации">
            <GroupTable
              firstColumn="Неделя"
              rows={data.cohorts.map((c) => ({ key: c.week_start, label: formatWeek(c.week_start), group: c }))}
            />
          </Section>

          <Section title="По источникам">
            <GroupTable
              firstColumn="Откуда узнали"
              rows={data.sources.map((s) => ({
                key: s.source ?? "none",
                label: s.source ? (SOURCE_LABELS[s.source] ?? s.source) : "Созданы в админке",
                group: s,
              }))}
            />
          </Section>

          {data.activity_tracked_since && (
            <p className="text-xs text-slate-400">
              Возвраты до {formatDay(data.activity_tracked_since)} не учтены: открытия приложения записываются только с
              этого дня.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="card p-5">
      <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h2>
      {children}
    </div>
  );
}

function StatTile({ label, value }: { label: string; value: number }) {
  return (
    <div className="card p-4">
      <div className="text-2xl font-semibold text-slate-900">{value}</div>
      <div className="text-xs text-slate-500">{label}</div>
    </div>
  );
}

function RateTile({ title, help, rate }: { title: string; help: string; rate: RetentionRate }) {
  return (
    <div className="card p-4">
      <div className="text-2xl font-semibold text-slate-900">
        {rate.percent == null ? "—" : `${percentFormat.format(rate.percent)}%`}
      </div>
      <div className="flex items-center gap-1.5 text-xs text-slate-500">
        {title}
        <InfoTooltip>{help}</InfoTooltip>
      </div>
      <div className="mt-1 text-xs text-slate-400">
        {rate.eligible === 0 ? "пока некого считать" : `${rate.returned} из ${rate.eligible}`}
      </div>
    </div>
  );
}

function RateCell({ rate }: { rate: RetentionRate }) {
  if (rate.percent == null) return <span className="text-slate-400">—</span>;
  return (
    <>
      <span className="font-medium text-slate-900">{percentFormat.format(rate.percent)}%</span>{" "}
      <span className="text-xs text-slate-400">
        {rate.returned}/{rate.eligible}
      </span>
    </>
  );
}

function GroupTable({
  firstColumn,
  rows,
}: {
  firstColumn: string;
  rows: { key: string; label: string; group: RetentionGroup }[];
}) {
  if (rows.length === 0) return <p className="text-sm text-slate-500">Пока нет регистраций.</p>;
  return (
    <div className="-mx-5 overflow-x-auto px-5">
      <table className="w-full min-w-[520px] text-left text-sm">
        <thead>
          <tr className="text-xs text-slate-500">
            <th className="pb-2 pr-3 font-medium">{firstColumn}</th>
            <th className="pb-2 pr-3 text-right font-medium">Регистраций</th>
            {WINDOWS.map((w) => (
              <th key={w.key} className="pb-2 pr-3 text-right font-medium last:pr-0">
                {w.short}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="tabular-nums">
          {rows.map((r) => (
            <tr key={r.key} className="border-t border-[var(--separator)]">
              <td className="py-2 pr-3 text-slate-900">{r.label}</td>
              <td className="py-2 pr-3 text-right text-slate-900">{r.group.signups}</td>
              {WINDOWS.map((w) => (
                <td key={w.key} className="py-2 pr-3 text-right last:pr-0">
                  <RateCell rate={r.group[w.key]} />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

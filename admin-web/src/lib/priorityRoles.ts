import type { PriorityLevelBand } from "../types";

/** Mirrors backend/app/priority/settings.py::priority_role_bands exactly
 * -- ranks enabled Priority Level bands by score (highest first) and
 * assigns each rank a fixed SYSTEM role, independent of the band's own
 * admin-given name. Display-only: explanatory tooltips read this to say
 * which band currently plays which role; no real behavior is decided
 * here (the backend already decided it before this page ever loads). */
export interface PriorityRoleBands {
  critical: PriorityLevelBand | null;
  high: PriorityLevelBand | null;
  medium: PriorityLevelBand | null;
  low: PriorityLevelBand | null;
  minimal: PriorityLevelBand | null;
}

function at<T>(arr: T[], index: number): T | null {
  const i = index < 0 ? arr.length + index : index;
  return arr[i] ?? null;
}

export function priorityRoleBands(bands: PriorityLevelBand[]): PriorityRoleBands {
  const sorted = [...bands].sort((a, b) => b.min_score - a.min_score);
  return {
    critical: at(sorted, 0),
    high: at(sorted, 1),
    medium: at(sorted, 2),
    low: sorted.length >= 2 ? at(sorted, -2) : null,
    minimal: sorted.length >= 1 ? at(sorted, -1) : null,
  };
}

export const PRIORITY_ROLE_EFFECTS: { key: keyof PriorityRoleBands; label: string; effect: string }[] = [
  { key: "critical", label: "Критический", effect: "при 5 одновременно накопленных словах — автоматически создаётся урок" },
  { key: "high", label: "Высокий", effect: "слово предпочитается при выборе слова для квеста" },
  { key: "medium", label: "Средний", effect: "то же самое, но во вторую очередь (если нет слов с «Высоким»)" },
  { key: "low", label: "Низкий", effect: "слово предпочитается как отвлекающий/неправильный вариант в упражнениях" },
  { key: "minimal", label: "Минимальный", effect: "то же самое, в первую очередь" },
];

export function formatScoreRange(min: number, max: number | null): string {
  return `${min}–${max ?? "∞"}`;
}

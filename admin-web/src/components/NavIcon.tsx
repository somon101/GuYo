/** Small line icons for the side menu: one 20px grid, one 1.75 stroke. */
const PATHS: Record<string, string> = {
  users: "M16 19v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 17.5V19M10 10.5a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM20 19v-1.3a3.3 3.3 0 0 0-2.5-3.2M15 4.6a3 3 0 0 1 0 5.8",
  chart: "M4 19h16M7 16V11M12 16V6M17 16v-3",
  retention: "M4 12a8 8 0 1 0 2.3-5.6M4 4v4h4",
  bell: "M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16ZM10 20.5a2 2 0 0 0 4 0",
  globe: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9c-2.5-2.6-3.7-5.6-3.7-9S9.5 5.6 12 3Z",
  dumbbell: "M6 8v8M3.5 10v4M18 8v8M20.5 10v4M6 12h12",
  blocks: "M4 4h7v7H4zM13 13h7v7h-7zM13 4h7v7h-7zM4 13h7v7H4z",
  sparkles: "M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8L12 3ZM18.5 15l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8.8-2Z",
  quote: "M5 17h4l1-5V6H4v6h3M15 17h4l1-5V6h-6v6h3",
  message: "M4 5h16v11H9l-5 4V5Z",
  trophy: "M8 4h8v5a4 4 0 0 1-8 0V4ZM8 6H5v1a3 3 0 0 0 3 3M16 6h3v1a3 3 0 0 1-3 3M12 13v4M8.5 20h7M10 17h4",
  podium: "M9 20V9h6v11M3 20v-7h6M15 20v-5h6v5M3 20h18",
  repeat: "M17 3l3 3-3 3M20 6H8a4 4 0 0 0-4 4v1M7 21l-3-3 3-3M4 18h12a4 4 0 0 0 4-4v-1",
  target: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM12 12h.01",
  crown: "M4 18h16M5 15 3.5 7l5 4L12 5l3.5 6 5-4L19 15H5Z",
  ticket: "M4 8V6h16v2a2 2 0 0 0 0 4v2a2 2 0 0 0 0 4v2H4v-2a2 2 0 0 0 0-4v-2a2 2 0 0 0 0-4ZM14 6v12",
  truefalse: "M5 12l4 4 10-10M5 4l4 4M9 4 5 8",
  link: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1",
  letters: "M4 20V8h6v12M4 14h6M14 20V8h4a3 3 0 0 1 0 6h-4M18 14a3 3 0 0 1 0 6h-4",
  mic: "M12 15a3 3 0 0 0 3-3V6a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3ZM6 11a6 6 0 0 0 12 0M12 17v4M9 21h6",
  speaker: "M4 9h4l5-4v14l-5-4H4V9ZM17 9a4 4 0 0 1 0 6M19.5 6.5a8 8 0 0 1 0 11",
  layers: "M12 3 3 8l9 5 9-5-9-5ZM3 13l9 5 9-5M3 17l9 5 9-5",
  flag: "M5 21V4M5 4h11l-2 4 2 4H5",
  bug:"M8 9a4 4 0 0 1 8 0v5a4 4 0 0 1-8 0V9ZM12 11v7M4 13h4M16 13h4M5 7l3 2M19 7l-3 2M5 19l3-2M19 19l-3-2",
};

export function NavIcon({ name }: { name: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className="shrink-0"
    >
      <path d={PATHS[name] ?? PATHS.blocks} />
    </svg>
  );
}

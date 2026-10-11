---
version: 1
slug: "src-components-layout-tsx"
primary_target: "src/components/Layout.tsx"
related_targets: ["src/index.css"]
---

## Scope
Admin Web shell and shared system (every page). Mode: Operate. Team of 2-5, desktop and phone equally.

## Direction contract
THESIS: The admin is the GuYo app's back room, wearing the app's own world: indigo ink, violet action, gold rewards, pastel tiles. It refuses the grey SaaS console with one accent (rejected twice: iOS-system, flat white + violet).
OWN-WORLD: Deep indigo #101B63 side rail; canvas #F8F8FD; white soft cards (radius 18, violet-tinted offset shadow); violet #5862DD for action and selection; gold #FFEB3B on #7A5600 only for rewards/Premium; pastel icon tiles per group (orange #FFE3B8, green #C9EFD3, blue #D5E4FF, pink #F6D6F4, yellow #FFF6DD). Onest type. Dark theme mirrors the app's dark palette (#11131C / #1C1F2E / #7C84F0).
STORY: The team sees where they are, what changed, and acts in one click; destructive actions read as dangerous.
FIRST VIEWPORT: Left indigo rail (logo, 5 groups, items with pastel icon tiles, active item a glowing violet pill); content on lavender canvas: page title, then the page's own cards and tables. Phone: rail becomes a top bar + horizontal scrolling pills.
FORM: user-pinned "like the GuYo app, more beautiful, modern, animated" (beats roll); seed key 54a22405 (rerolled twice, then pinned).
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Signature interaction: the active-section pill glides between rail items (ease-out-expo), and each page rises in once on arrival.

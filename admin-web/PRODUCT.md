# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

The GuYo owner and a small content/ops team. They run the GuYo language-learning app (Russian for Tajik and Uzbek speakers) day to day: editing dictionary content, tuning game rules, watching numbers, and handling users. Used as much from a phone as from a computer.

## Product Purpose

The back office of GuYo. Everything the mobile app shows or rewards is configured here: languages, words, phrases and audio, exercises, mini-phrases, lessons and quests, rating and seasons, achievements, statuses, notifications and reminders, Premium and promo codes, AI translation (DeepSeek), and the analytics, retention and app-error views. Success: the team can change the live app quickly and confidently, and spot problems in the numbers early.

## Operating Context

- Frequent work, all equally important: game settings (rating, quests, achievements, reminders), users (search, delete, Premium), numbers (analytics, retention, client errors), content (words, phrases, audio, imports, AI translation).
- Desktop and phone in roughly equal measure; every screen must work well at phone width.
- Changes go live immediately for real learners; destructive actions (deleting users or achievements) are irreversible.
- Content is multilingual (Russian, Tajik, Uzbek, English) and must never be machine-translated by the browser.

## Capabilities and Constraints

- React 19 + Tailwind v4 + Vite, deployed to GitHub Pages; backend FastAPI on Railway.
- Light and dark themes follow the OS.
- Interface language: Russian.

## Brand Commitments

- Name: GuYo. Existing logo mark at `src/assets/logo-mark.png`.
- The owner is highly design-sensitive: one coherent style everywhere, finished dark theme, no loading flashes, compact.
- Rejected directions: the earlier iOS-system look, and a flat "white panels + violet accent + Geist + grouped sidebar" look (commit 7520b7d), judged generic.

## Product Principles

1. Fast to change, safe to change: irreversible actions are clearly marked and confirmed.
2. Numbers first where numbers matter: problems should be visible at a glance.
3. Phone is a first-class place to work, not a fallback.
4. One system for every page; a new page should look right by reusing it.

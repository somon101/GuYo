import { useEffect, useRef } from "react";
import { flushSync } from "react-dom";
import { useLocation, useNavigate, useNavigationType } from "react-router-dom";

// True only while a link-click navigation is being rendered inside a View
// Transition -- the transition already animates that page, so its own
// fallback enter animation must not play on top of it.
let renderingInsideTransition = false;

function pathOf(to: string) {
  return to.split("?")[0].split("#")[0];
}

/** Going up the hierarchy (a word -> its words list) plays as a "back". */
function isUpward(from: string, to: string) {
  const fromPath = pathOf(from);
  const toPath = pathOf(to).replace(/\/$/, "");
  return toPath !== "" && fromPath.startsWith(`${toPath}/`);
}

/** iOS-style push/pop between screens for every in-app link click: the
 * browser's View Transitions API snapshots the old screen, React renders
 * the new one synchronously inside the transition (flushSync -- which is
 * why App's HashRouter runs with useTransitions={false}), and index.css
 * slides the two past each other. Browsers without the API, and users who
 * asked for reduced motion, just navigate normally. */
export function usePageTransitions() {
  const navigate = useNavigate();
  const location = useLocation();
  const currentRef = useRef("");
  currentRef.current = location.pathname + location.search;

  useEffect(() => {
    if (typeof document.startViewTransition !== "function") return;
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    function onClick(e: MouseEvent) {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      if (reducedMotion.matches) return;
      const anchor = (e.target as Element | null)?.closest?.("a[href]");
      if (!anchor) return;
      const target = anchor.getAttribute("target");
      if ((target && target !== "_self") || anchor.hasAttribute("download")) return;
      const href = anchor.getAttribute("href") ?? "";
      if (!href.startsWith("#/")) return;
      const to = href.slice(1);
      const from = currentRef.current;
      if (to === from) return;

      // Captured before React Router's own Link handler, which then sees
      // defaultPrevented and stands down -- the navigation happens once,
      // below, inside the transition.
      e.preventDefault();
      const root = document.documentElement;
      root.dataset.vtDir = isUpward(from, to) ? "back" : "forward";
      const transition = document.startViewTransition(() => {
        renderingInsideTransition = true;
        try {
          flushSync(() => navigate(to));
        } finally {
          renderingInsideTransition = false;
        }
      });
      transition.finished.finally(() => {
        delete root.dataset.vtDir;
      });
    }

    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, [navigate]);
}

/** Which way a freshly shown screen should slide in when it was NOT reached
 * through a link click (a save that redirects, the browser's back button),
 * or null when it shouldn't animate at all -- the very first screen, or one
 * a View Transition is already animating. Decided once per screen. */
export function usePageEnter(key: string): "forward" | "back" | null {
  const navigationType = useNavigationType();
  const decided = useRef<{ key: string; dir: "forward" | "back" | null } | null>(null);
  if (decided.current?.key !== key) {
    const isFirstScreen = decided.current === null;
    decided.current = {
      key,
      dir: isFirstScreen || renderingInsideTransition ? null : navigationType === "POP" ? "back" : "forward",
    };
  }
  return decided.current.dir;
}

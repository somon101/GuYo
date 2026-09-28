import { useState } from "react";

// Negative delays pick up each drift where the wall clock says it should
// be, so the colour fields never jump back to their start positions when
// the login screen hands over to the admin shell.
function phaseDelay(periodSeconds: number) {
  return `-${((Date.now() / 1000) % (periodSeconds * 2)).toFixed(1)}s`;
}

/** Three large, very soft colour fields (blue, purple, green) slowly
 * drifting behind all content -- the admin's "wallpaper". Cards are
 * opaque, so they mostly show in the gutters and through the glass header. */
export function Backdrop() {
  const [delays] = useState(() => [phaseDelay(64), phaseDelay(82), phaseDelay(96)]);
  return (
    <div className="backdrop" aria-hidden="true">
      <span className="blob blob-blue" style={{ animationDelay: delays[0] }} />
      <span className="blob blob-purple" style={{ animationDelay: delays[1] }} />
      <span className="blob blob-green" style={{ animationDelay: delays[2] }} />
    </div>
  );
}

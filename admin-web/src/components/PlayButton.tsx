import { useEffect, useRef, useState } from "react";

/** Round blue ▶, like the play button in Music. Tap to hear the recording,
 * tap again to stop; while it plays, a soft ring keeps spreading out from
 * it (see .play-btn in index.css). */
export function PlayButton({ src, size = 34, label = "Прослушать" }: { src: string; size?: number; label?: string }) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);

  useEffect(() => {
    return () => {
      audioRef.current?.pause();
      audioRef.current = null;
    };
  }, [src]);

  function toggle() {
    const current = audioRef.current;
    if (current && isPlaying) {
      current.pause();
      current.currentTime = 0;
      setIsPlaying(false);
      return;
    }
    const audio = current ?? new Audio(src);
    audioRef.current = audio;
    audio.onended = () => setIsPlaying(false);
    audio.onpause = () => setIsPlaying(false);
    audio.currentTime = 0;
    audio
      .play()
      .then(() => setIsPlaying(true))
      .catch(() => setIsPlaying(false));
  }

  const icon = Math.round(size * 0.38);
  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={isPlaying ? "Остановить" : label}
      title={isPlaying ? "Остановить" : label}
      data-playing={isPlaying}
      className="play-btn inline-flex shrink-0 items-center justify-center rounded-full bg-[var(--sys-blue)] text-white"
      style={{
        width: size,
        height: size,
        boxShadow: "0 2px 8px color-mix(in srgb, var(--sys-blue) 35%, transparent)",
      }}
    >
      {isPlaying ? (
        <svg width={icon} height={icon} viewBox="0 0 10 10" aria-hidden="true">
          <rect x="1.5" y="1.5" width="7" height="7" rx="1.4" fill="currentColor" />
        </svg>
      ) : (
        <svg width={icon} height={icon} viewBox="0 0 10 10" aria-hidden="true" style={{ marginLeft: size * 0.05 }}>
          <path d="M2.2 1.2 L8.8 5 L2.2 8.8 Z" fill="currentColor" stroke="currentColor" strokeWidth="1" strokeLinejoin="round" />
        </svg>
      )}
    </button>
  );
}

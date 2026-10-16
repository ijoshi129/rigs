/**
 * The Switch 2. `Switch2Photo` is the product shot (background removed) for
 * the Connect screen; `Switch2Icon` is a simplified glyph for small sizes.
 */

export function Switch2Photo({ height = 300, dim = false }: { height?: number; dim?: boolean }) {
  return (
    <img
      src={`${import.meta.env.BASE_URL}switch2.png`}
      alt="Switch 2"
      draggable={false}
      style={{ height, width: "auto", filter: dim ? "grayscale(1) brightness(0.6)" : undefined, transition: "filter 400ms ease" }}
    />
  );
}

export function Switch2Icon({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9.5 3.5c0-1 5-1 5 0v1.5c0 1-5 1-5 0z" />
      <rect x="8" y="6" width="8" height="15" rx="3.5" />
      <rect x="10" y="8.5" width="4" height="5" rx="1" fill="currentColor" opacity="0.35" stroke="none" />
      <circle cx="12" cy="16.5" r="1.3" fill="currentColor" stroke="none" />
    </svg>
  );
}


import { useSyncExternalStore } from "react";

/** Hash routes so the browser back button works inside Bluefy and Chrome. */
export type Route =
  | { name: "session" }
  | { name: "presets" }
  | { name: "preset"; index: number }
  | { name: "lights" }
  | { name: "history" }
  | { name: "appearance" }
  | { name: "connect" };

function parse(hash: string): Route {
  const parts = hash.replace(/^#\/?/, "").split("/").filter(Boolean);
  switch (parts[0]) {
    case "presets": return parts[1] ? { name: "preset", index: Number(parts[1]) } : { name: "presets" };
    case "lights": return { name: "lights" };
    case "history": return { name: "history" };
    case "appearance": return { name: "appearance" };
    case "connect": return { name: "connect" };
    default: return { name: "session" };
  }
}

const listeners = new Set<() => void>();
let current = parse(typeof location !== "undefined" ? location.hash : "");
if (typeof window !== "undefined") {
  window.addEventListener("hashchange", () => {
    current = parse(location.hash);
    for (const l of listeners) l();
  });
}

export const navigate = (path: string) => {
  location.hash = path.startsWith("#") ? path : `#/${path.replace(/^\//, "")}`;
};
export const back = () => (history.length > 1 ? history.back() : navigate("/"));

export const useRoute = () =>
  useSyncExternalStore(
    (l) => { listeners.add(l); return () => listeners.delete(l); },
    () => current,
  );

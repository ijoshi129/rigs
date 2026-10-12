import { registerSW } from "virtual:pwa-register";

// Take new builds immediately: when a fresh service worker is ready, reload once.
registerSW({
  immediate: true,
  onNeedRefresh() { location.reload(); },
});

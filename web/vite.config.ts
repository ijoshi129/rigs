import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// GitHub Pages serves the site under /<repo>/; set VITE_BASE=/ for other hosts.
export default defineConfig({
  base: process.env.VITE_BASE ?? "/rigs/",
  plugins: [react(), tailwindcss()],
  test: { environment: "node" },
});

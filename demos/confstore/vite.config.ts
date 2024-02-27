import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig({
  define: {
    global: {},
  },
  resolve: {
    alias: {
      "node-fetch": "isomorphic-fetch",
    },
  },
  plugins: [react()],
});

import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: ".",
  testMatch: "purchase.spec.mjs",
  workers: 1,
  timeout: 45_000,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: process.env.APPLICATION_URL,
    trace: "retain-on-failure",
  },
});

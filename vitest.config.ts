import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
    env: {
      DATABASE_URL:
        process.env.DATABASE_URL ||
        "postgresql://unerp:unerp_password@localhost:5432/unerp_dev?schema=public",
    },
    testTimeout: 30000,
    hookTimeout: 30000,
    pool: "forks",
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html"],
      reportsDirectory: "./coverage",
      // J02 — `all: true` so coverage counts untested source files and can
      // fail; thresholds set at the measured floor (ratchet may only rise).
      all: true,
      include: ["src/**"],
      thresholds: {
        lines: 85,
        functions: 75,
        branches: 70,
        statements: 85,
      },
      exclude: [
        "src/**/*.test.ts",
        "src/**/tests/**",
        "src/**/dto/**",
        "src/main.ts",
        "src/tracing.ts",
        "src/**/*.module.ts",
        "src/idp-client/**",
      ],
    },
  },
});

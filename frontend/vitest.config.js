import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["./tests/setup.js"],
    reporters: ["default", "junit"],
    outputFile: { junit: "test-results/frontend.xml" },
    include: ["tests/**/*.test.{js,jsx}"],
    env: { VITE_API_BASE_URL: "/", VITE_API_PREFIX: "/api", VITE_CURRENCY_LOCALE: "es-CO", VITE_CURRENCY_CODE: "COP" },
    coverage: {
      provider: "v8",
      include: ["src/context/CartContext.jsx", "src/lib/apiError.js", "src/services/*.js", "src/utils/*.js", "src/hooks/useAuth.js", "src/hooks/useCart.js", "src/screens/Login.jsx", "src/screens/CartScreen.jsx", "src/components/ProtectedRoute.jsx"],
      reporter: ["text", "html", "lcov", "json-summary"],
      thresholds: { lines: 80, statements: 80, functions: 80, branches: 80 },
    },
  },
});

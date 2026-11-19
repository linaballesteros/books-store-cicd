import { beforeEach, expect, it, vi } from "vitest";
vi.mock("../src/lib/api.js", () => ({ api: { get: vi.fn(), post: vi.fn() } }));
import { api } from "../src/lib/api.js";
import { authService } from "../src/services/authService.js";
import { bookService } from "../src/services/bookService.js";
import { orderService } from "../src/services/orderService.js";
import { ApiError, normalizeApiError, isRetryableError } from "../src/lib/apiError.js";
import { formatCurrency } from "../src/utils/currency.js";
import { formatDate } from "../src/utils/date.js";
beforeEach(() => vi.resetAllMocks());
it("normaliza identidad y ausencia de sesión", async () => {
  api.post.mockResolvedValue({ data: { user: { customerId: "1", firstName: "Test" } } });
  expect((await authService.login("a@b.co")).id).toBe("1");
  api.get.mockResolvedValue({ data: { user: { customerId: "1" } } });
  expect((await authService.getCurrentUser()).id).toBe("1");
  api.get.mockRejectedValue({ status: 401 }); expect(await authService.getCurrentUser()).toBeNull();
  api.get.mockRejectedValue(new Error("network")); await expect(authService.getCurrentUser()).rejects.toThrow("network");
  await authService.logout(); expect(api.post).toHaveBeenLastCalledWith("/api/auth/logout");
});
it("convierte precio y contratos de catálogo", async () => {
  api.get.mockResolvedValueOnce({ data: [{ book_id: "1", price: "12.50", stock: 2 }] });
  expect((await bookService.list())[0]).toMatchObject({ id: "1", price: 12.5 });
  api.get.mockResolvedValueOnce({ data: { book_id: "1", price: "12.50" } });
  expect((await bookService.getByIsbn("123")).price).toBe(12.5);
});
it("serializa carrito y convierte totales e ítems de pedidos", async () => {
  const order = { orderId: "o", totalAmount: "25", items: [{ orderItemId: "i", unitPrice: "12.50", lineTotal: "25" }] };
  api.post.mockResolvedValue({ data: { order } });
  expect((await orderService.create([{ bookId: "b", quantity: 2, price: 0 }])).totalAmount).toBe(25);
  expect(api.post).toHaveBeenCalledWith("/api/orders", { items: [{ book_id: "b", quantity: 2 }] });
  api.get.mockResolvedValueOnce({ data: { orders: [order] } }); expect(await orderService.list()).toHaveLength(1);
  api.get.mockResolvedValueOnce({ data: { order } }); expect((await orderService.getById("o")).items[0].unitPrice).toBe(12.5);
});
it("presenta errores seguros y decide reintentos", () => {
  const known = new ApiError({ status: 400, code: "INVALID", message: "Corregir" });
  expect(normalizeApiError(known)).toBe(known); expect(isRetryableError(known)).toBe(false);
  expect(normalizeApiError(new Error("network"))).toMatchObject({ status: 0, code: "NETWORK_ERROR" });
  expect(normalizeApiError({ response: { status: 400, data: { error: { code: "BAD", message: "Dato inválido" } } } }).message).toBe("Dato inválido");
  expect(normalizeApiError({ response: { status: 500, data: { error: { message: "password" } } } }).message).not.toContain("password");
  expect(normalizeApiError({ response: { status: 400 } }).code).toBe("UNKNOWN_ERROR");
  expect(isRetryableError(new Error())).toBe(true);
  expect(isRetryableError(new ApiError({ status: 0 }))).toBe(true);
  expect(isRetryableError(new ApiError({ status: 503 }))).toBe(true);
});
it("formatea moneda y fecha configuradas", () => { expect(formatCurrency(12000)).toContain("12"); expect(formatDate("2026-01-01T12:00:00Z")).toContain("2026"); });

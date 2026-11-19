import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { AuthContext } from "../src/context/contexts.js";
import { CartProvider } from "../src/context/CartContext.jsx";
import { useCart } from "../src/hooks/useCart.js";
import { useAuth } from "../src/hooks/useAuth.js";

vi.mock("../src/lib/cartAnalytics.js", () => ({ trackAddToCart: vi.fn(), trackQuantityChanged: vi.fn(), trackRemoveFromCart: vi.fn() }));
const book = { id: "one", isbn: "123", title: "Libro", price: 20, stock: 3 };
const create = (user = { id: "a" }) => renderHook(() => useCart(), { wrapper: ({ children }) => <AuthContext.Provider value={{ user }}><CartProvider>{children}</CartProvider></AuthContext.Provider> });

describe("carrito por cliente", () => {
  it("no admite compras anónimas", () => { const { result } = create(null); act(() => expect(result.current.addItem(book)).toBe(0)); expect(result.current.items).toEqual([]); });
  it("agrega, acumula y limita al inventario disponible", () => {
    const { result } = create();
    act(() => expect(result.current.addItem(book)).toBe(1));
    expect(result.current.subtotal).toBe(20);
    act(() => expect(result.current.addItem(book, 8)).toBe(2));
    expect(result.current.totalItems).toBe(3); expect(result.current.subtotal).toBe(60);
    act(() => expect(result.current.addItem(book)).toBe(0));
  });
  it.each([0, -1, "invalid"])("ignora cantidad inválida %s", quantity => { const { result } = create(); act(() => result.current.addItem(book, quantity)); expect(result.current.totalItems).toBe(0); });
  it("actualiza, elimina y vacía sin alterar otros libros", () => {
    const { result } = create();
    act(() => result.current.addItem(book, 1));
    act(() => result.current.addItem({ ...book, id: "two" }, 1));
    act(() => result.current.updateQuantity("one", 2));
    expect(result.current.totalItems).toBe(3);
    act(() => result.current.updateQuantity("missing", 2));
    act(() => result.current.updateQuantity("one", 0));
    act(() => result.current.updateQuantity("one", 2));
    expect(result.current.totalItems).toBe(3);
    act(() => result.current.removeItem("one"));
    expect(result.current.items.map(i => i.bookId)).toEqual(["two"]);
    act(() => result.current.removeItem("missing"));
    act(() => result.current.clearCart());
    expect(result.current.subtotal).toBe(0);
  });
  it("aísla el carrito al cambiar de cliente", () => {
    let user = { id: "a" };
    const wrapper = ({ children }) => <AuthContext.Provider value={{ user }}><CartProvider>{children}</CartProvider></AuthContext.Provider>;
    const { result, rerender } = renderHook(() => useCart(), { wrapper });
    act(() => result.current.addItem(book));
    user = { id: "b" }; rerender();
    expect(result.current.items).toEqual([]);
    act(() => result.current.addItem({ ...book, id: "two" }));
    expect(result.current.items.map(i => i.bookId)).toEqual(["two"]);
  });
  it("exige los proveedores de contexto", () => {
    expect(() => renderHook(() => useCart())).toThrow("CartProvider");
    expect(() => renderHook(() => useAuth())).toThrow("AuthProvider");
  });
});

import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import Login from "../src/screens/Login.jsx";
import CartScreen from "../src/screens/CartScreen.jsx";
import ProtectedRoute from "../src/components/ProtectedRoute.jsx";

const mocks = vi.hoisted(() => ({ auth: {}, cart: {}, order: {}, navigate: vi.fn(), location: { state: null } }));
vi.mock("../src/hooks/useAuth.js", () => ({ useAuth: () => mocks.auth }));
vi.mock("../src/hooks/useCart.js", () => ({ useCart: () => mocks.cart }));
vi.mock("../src/hooks/useOrders.js", () => ({ useCreateOrder: () => mocks.order }));
vi.mock("../src/lib/cartAnalytics.js", () => ({ trackCheckoutStarted: vi.fn() }));
vi.mock("react-router-dom", async original => ({ ...await original(), useNavigate: () => mocks.navigate, useLocation: () => mocks.location }));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.auth = { login: vi.fn().mockResolvedValue({}), user: null, isLoading: false };
  mocks.location = { state: null, pathname: "/orders" };
  mocks.cart = { items: [], totalItems: 0, subtotal: 0, updateQuantity: vi.fn(), removeItem: vi.fn(), clearCart: vi.fn() };
  mocks.order = { mutate: vi.fn(), isPending: false, isError: false };
});
const show = component => render(<MemoryRouter>{component}</MemoryRouter>);

describe("componente de inicio de sesión", () => {
  it("envía el correo y regresa al destino interno solicitado", async () => {
    mocks.location.state = { from: "/cart" }; show(<Login />);
    fireEvent.change(screen.getByLabelText("Correo electrónico:"), { target: { value: "user@bookstore.test" } });
    fireEvent.click(screen.getByRole("button", { name: "Ingresar" }));
    await waitFor(() => expect(mocks.navigate).toHaveBeenCalledWith("/cart", { replace: true }));
    expect(mocks.auth.login).toHaveBeenCalledWith("user@bookstore.test");
  });
  it.each(["//evil.test", "https://evil.test", 123, undefined])("evita redirección externa o inválida %s", async from => {
    mocks.location.state = { from }; show(<Login />);
    fireEvent.change(screen.getByLabelText("Correo electrónico:"), { target: { value: "user@test.co" } });
    fireEvent.submit(screen.getByRole("button", { name: "Ingresar" }).closest("form"));
    await waitFor(() => expect(mocks.navigate).toHaveBeenCalledWith("/", { replace: true }));
  });
  it("muestra un fallo de autenticación y permite reintentar", async () => {
    mocks.auth.login.mockRejectedValue(new Error("Usuario no disponible")); show(<Login />);
    fireEvent.change(screen.getByLabelText("Correo electrónico:"), { target: { value: "user@test.co" } });
    fireEvent.submit(screen.getByRole("button", { name: "Ingresar" }).closest("form"));
    expect(await screen.findByRole("alert")).toHaveTextContent("Usuario no disponible");
    expect(screen.getByRole("button", { name: "Ingresar" })).toBeEnabled();
    expect(mocks.navigate).not.toHaveBeenCalled();
  });
  it("impide envío duplicado mientras se inicia sesión", async () => {
    let finish;
    mocks.auth.login.mockImplementation(() => new Promise(resolve => { finish = resolve; })); show(<Login />);
    fireEvent.submit(screen.getByRole("button", { name: "Ingresar" }).closest("form"));
    expect(screen.getByRole("button", { name: "Ingresando..." })).toBeDisabled();
    finish({}); await waitFor(() => expect(mocks.navigate).toHaveBeenCalled());
  });
});

describe("componente del carrito", () => {
  const fill = () => {
    mocks.cart.items = [{ bookId: "b", isbn: "123", title: "Libro de prueba", price: 10, stock: 5, quantity: 2 }];
    mocks.cart.totalItems = 2; mocks.cart.subtotal = 20;
  };
  it("muestra estado vacío y enlace al catálogo", () => { show(<CartScreen />); expect(screen.getByText(/Tu carrito está vacío/)).toBeVisible(); expect(screen.getByRole("link", { name: "Regresar al catálogo" })).toHaveAttribute("href", "/"); });
  it("permite ajustar cantidad y eliminar un libro", () => {
    fill(); show(<CartScreen />);
    fireEvent.change(screen.getByLabelText("Cantidad de Libro de prueba"), { target: { value: "3" } });
    expect(mocks.cart.updateQuantity).toHaveBeenCalledWith("b", "3");
    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    expect(mocks.cart.removeItem).toHaveBeenCalledWith("b");
  });
  it("solo vacía y navega cuando el pedido se confirma", () => {
    fill(); show(<CartScreen />);
    fireEvent.click(screen.getByRole("button", { name: "Finalizar compra" }));
    expect(mocks.order.mutate).toHaveBeenCalledWith(mocks.cart.items, expect.any(Object));
    expect(mocks.cart.clearCart).not.toHaveBeenCalled();
    mocks.order.mutate.mock.calls[0][1].onSuccess({ id: "order-1" });
    expect(mocks.cart.clearCart).toHaveBeenCalledOnce();
    expect(mocks.navigate).toHaveBeenCalledWith("/orders/order-1/success", { replace: true });
  });
  it("muestra error sin borrar carrito", () => {
    fill(); mocks.order.isError = true; mocks.order.error = new Error("Stock insuficiente"); show(<CartScreen />);
    expect(screen.getByRole("alert")).toHaveTextContent("Stock insuficiente");
    expect(mocks.cart.clearCart).not.toHaveBeenCalled();
  });
  it("deshabilita cantidad, eliminación y compra durante envío", () => {
    fill(); mocks.order.isPending = true; show(<CartScreen />);
    expect(screen.getByLabelText("Cantidad de Libro de prueba")).toBeDisabled();
    expect(screen.getByRole("button", { name: "Eliminar" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Procesando compra..." })).toBeDisabled();
  });
});

describe("protección de rutas", () => {
  const protectedPage = () => render(<MemoryRouter initialEntries={["/private"]}><Routes><Route element={<ProtectedRoute />}><Route path="/private" element={<p>Privado</p>} /></Route><Route path="/login" element={<p>Ingresar para continuar</p>} /></Routes></MemoryRouter>);
  it("espera la sesión antes de renderizar contenido privado", () => {
    mocks.auth.isLoading = true; protectedPage();
    expect(screen.queryByText("Privado")).not.toBeInTheDocument();
  });
  it("renderiza contenido para cliente autenticado", () => {
    mocks.auth.isAuthenticated = true; protectedPage();
    expect(screen.getByText("Privado")).toBeVisible();
  });
  it("no muestra contenido privado a visitantes", () => {
    protectedPage();
    expect(screen.queryByText("Privado")).not.toBeInTheDocument();
  });
});

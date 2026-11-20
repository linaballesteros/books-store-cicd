import { expect, test } from "@playwright/test";
import { executeFixture, newFixture } from "./fixture.mjs";

const { isbn, email, title } = newFixture();
const customer = `SELECT customer_id FROM customers WHERE email = '${email}'`;
const customerOrders = `SELECT order_id FROM orders WHERE customer_id IN (${customer})`;

test.beforeAll(() => {
  test.setTimeout(300_000);
  executeFixture(`
    BEGIN;
    INSERT INTO customers (first_name, last_name, email)
      VALUES ('BookStore', 'Acceptance', '${email}');
    INSERT INTO books (isbn, title, author, price, stock)
      VALUES ('${isbn}', '${title}', 'BookStore', 10000, 2);
    COMMIT;
  `);
});

test.afterAll(() => {
  test.setTimeout(300_000);
  executeFixture(`
    BEGIN;
    DELETE FROM order_items WHERE order_id IN (${customerOrders});
    DELETE FROM orders WHERE customer_id IN (${customer});
    DELETE FROM customers WHERE email = '${email}';
    DELETE FROM books WHERE isbn = '${isbn}';
    COMMIT;
  `);
});

test("buys a staging book and finds the same order in purchase history", async ({ page }) => {
  await page.goto(`/book/${isbn}`);
  await expect(page.getByRole("heading", { name: title })).toBeVisible();
  await page.getByRole("button", { name: "Agregar al carrito" }).click();
  await expect(page).toHaveURL(/\/login/);
  await page.getByLabel("Correo electrónico").fill(email);
  await page.getByRole("button", { name: "Ingresar" }).click();

  await expect(page).toHaveURL(new RegExp(`/book/${isbn}$`));
  await page.getByRole("button", { name: "Agregar al carrito" }).click();
  await expect(page.getByText("El libro fue agregado al carrito.")).toBeVisible();
  await page.getByRole("link", { name: /Carrito con 1/ }).click();
  await expect(page.getByRole("heading", { name: "Carrito de compras" })).toBeVisible();
  await page.getByRole("button", { name: "Finalizar compra" }).click();

  await expect(page.getByText("Tu compra fue registrada correctamente.")).toBeVisible();
  const orderId = new URL(page.url()).pathname.split("/")[2];
  await page.getByText("Ver mis compras", { exact: true }).click();
  await expect(page).toHaveURL(/\/orders$/);
  await expect(page.getByRole("heading", { name: "Mis compras" })).toBeVisible();
  const order = page.getByRole("button", { name: new RegExp(orderId) });
  await expect(order).toBeVisible();
  await order.click();
  await expect(page.getByText(title, { exact: true })).toBeVisible();
});

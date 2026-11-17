import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, it } from "node:test";

// Integration suite: runs against a real PostgreSQL database loaded with the
// project schema and seed. It is skipped unless RUN_DB_TESTS=1 so the unit
// suite stays fast and database-free.
const runDbTests = process.env.RUN_DB_TESTS === "1";

let pool;
let closeDatabaseConnection;
let placeOrder;
let findBooks;
let findBookByIsbn;
let findOrdersByCustomerId;

// Customer id seeded by database/seed.sql (fixed UUIDs).
const SEEDED_CUSTOMER_ID = "00000000-0000-4000-8000-000000000001";

before(async () => {
  if (!runDbTests) return;

  process.loadEnvFile(new URL("../../.env.test", import.meta.url));

  ({ pool, closeDatabaseConnection } = await import("../../config/database.js"));
  ({ placeOrder } = await import("../../services/orderService.js"));
  ({ findBooks, findBookByIsbn } = await import(
    "../../repositories/bookRepository.js"
  ));
  ({ findOrdersByCustomerId } = await import(
    "../../repositories/orderRepository.js"
  ));
});

after(async () => {
  if (!runDbTests) return;
  await closeDatabaseConnection();
});

describe("order flow against PostgreSQL", { skip: !runDbTests }, () => {
  it("lists seeded books with stock", async () => {
    const books = await findBooks({ limit: 5, offset: 0 });

    assert.ok(books.length > 0, "the seed should provide books");
    assert.ok(Object.hasOwn(books[0], "stock"));
  });

  it("places an order and decreases stock", async () => {
    const [book] = await findBooks({ limit: 1, offset: 0 });
    const stockBefore = Number(book.stock);

    const order = await placeOrder({
      customerId: SEEDED_CUSTOMER_ID,
      items: [{ bookId: book.book_id, quantity: 1 }],
    });

    assert.equal(order.order_status, "PLACED");
    assert.equal(order.total_quantity, 1);
    assert.ok(Number(order.total_amount) > 0);

    const refreshed = await findBookByIsbn(book.isbn);
    assert.equal(Number(refreshed.stock), stockBefore - 1);
  });

  it("rejects an order when stock is insufficient", async () => {
    const [book] = await findBooks({ limit: 1, offset: 0 });

    await assert.rejects(
      () =>
        placeOrder({
          customerId: SEEDED_CUSTOMER_ID,
          items: [{ bookId: book.book_id, quantity: 1_000_000 }],
        }),
      (error) => {
        assert.equal(error.code, "INSUFFICIENT_STOCK");
        return true;
      }
    );
  });

  it("rejects an order for a customer that does not exist", async () => {
    const [book] = await findBooks({ limit: 1, offset: 0 });

    await assert.rejects(
      () =>
        placeOrder({
          customerId: randomUUID(),
          items: [{ bookId: book.book_id, quantity: 1 }],
        }),
      (error) => {
        assert.equal(error.code, "INVALID_SESSION");
        return true;
      }
    );
  });

  it("rejects an order for a book that does not exist", async () => {
    await assert.rejects(
      () =>
        placeOrder({
          customerId: SEEDED_CUSTOMER_ID,
          items: [{ bookId: randomUUID(), quantity: 1 }],
        }),
      (error) => {
        assert.equal(error.code, "BOOK_UNAVAILABLE");
        return true;
      }
    );
  });

  it("finds the orders placed by the seeded customer", async () => {
    const orders = await findOrdersByCustomerId(SEEDED_CUSTOMER_ID);

    assert.ok(Array.isArray(orders));
    assert.ok(orders.length > 0, "the previous test placed at least one order");
  });
});

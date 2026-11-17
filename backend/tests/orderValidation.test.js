import assert from "node:assert/strict";
import { before, describe, it } from "node:test";

import { AppError } from "../errors/AppError.js";

let normalizeItems;
let normalizeOrderId;

const validBookId = "11111111-1111-4111-8111-111111111111";
const otherBookId = "22222222-2222-4222-8222-222222222222";

before(async () => {
  // orderController imports the config module, which validates the environment
  // on load, so the test environment must be available first.
  process.loadEnvFile(new URL("../.env.test", import.meta.url));
  ({ normalizeItems, normalizeOrderId } = await import(
    "../controllers/orderController.js"
  ));
});

describe("normalizeItems", () => {
  it("accepts a valid list and normalizes the book id to lowercase", () => {
    const result = normalizeItems([
      { book_id: validBookId.toUpperCase(), quantity: 2 },
    ]);

    assert.deepEqual(result, [{ bookId: validBookId, quantity: 2 }]);
  });

  it("rejects an empty list", () => {
    assert.throws(() => normalizeItems([]), (error) => {
      assert.ok(error instanceof AppError);
      assert.equal(error.statusCode, 400);
      assert.equal(error.code, "INVALID_ORDER");
      return true;
    });
  });

  it("rejects a payload that is not an array", () => {
    assert.throws(() => normalizeItems("not-an-array"), AppError);
  });

  it("rejects an item with a non-uuid book id", () => {
    assert.throws(
      () => normalizeItems([{ book_id: "123", quantity: 1 }]),
      AppError
    );
  });

  it("rejects the same book appearing twice", () => {
    assert.throws(
      () =>
        normalizeItems([
          { book_id: validBookId, quantity: 1 },
          { book_id: validBookId, quantity: 2 },
        ]),
      (error) => {
        assert.equal(error.code, "INVALID_ORDER");
        return true;
      }
    );
  });

  it("rejects a non-positive quantity", () => {
    assert.throws(
      () => normalizeItems([{ book_id: validBookId, quantity: 0 }]),
      AppError
    );
  });

  it("rejects a non-integer quantity", () => {
    assert.throws(
      () => normalizeItems([{ book_id: validBookId, quantity: 1.5 }]),
      AppError
    );
  });

  it("accepts several distinct books", () => {
    const result = normalizeItems([
      { book_id: validBookId, quantity: 1 },
      { book_id: otherBookId, quantity: 3 },
    ]);

    assert.equal(result.length, 2);
  });
});

describe("normalizeOrderId", () => {
  it("accepts a valid uuid and lowercases it", () => {
    assert.equal(normalizeOrderId(validBookId.toUpperCase()), validBookId);
  });

  it("rejects a non-string order id", () => {
    assert.throws(() => normalizeOrderId(123), (error) => {
      assert.ok(error instanceof AppError);
      assert.equal(error.code, "INVALID_ORDER_ID");
      return true;
    });
  });

  it("rejects a malformed order id", () => {
    assert.throws(() => normalizeOrderId("abc"), AppError);
  });
});

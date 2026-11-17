import assert from "node:assert/strict";
import { describe, it, mock } from "node:test";

import { AppError } from "../errors/AppError.js";
import { authenticate } from "../middleware/authenticate.js";

describe("authenticate middleware", () => {
  it("calls next when the request is already authenticated", async () => {
    const next = mock.fn();
    const req = { auth: { customerId: "abc" } };

    await authenticate(req, {}, next);

    assert.equal(next.mock.callCount(), 1);
  });

  it("rejects an invalid session with a 401 INVALID_SESSION error", async () => {
    const next = mock.fn();
    const req = { authState: "invalid" };

    await assert.rejects(
      () => authenticate(req, {}, next),
      (error) => {
        assert.ok(error instanceof AppError);
        assert.equal(error.statusCode, 401);
        assert.equal(error.code, "INVALID_SESSION");
        return true;
      }
    );
    assert.equal(next.mock.callCount(), 0);
  });

  it("rejects a missing session with a 401 AUTH_REQUIRED error", async () => {
    const next = mock.fn();
    const req = {};

    await assert.rejects(
      () => authenticate(req, {}, next),
      (error) => {
        assert.ok(error instanceof AppError);
        assert.equal(error.statusCode, 401);
        assert.equal(error.code, "AUTH_REQUIRED");
        return true;
      }
    );
    assert.equal(next.mock.callCount(), 0);
  });
});

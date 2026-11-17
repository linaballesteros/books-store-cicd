import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { AppError } from "../errors/AppError.js";

describe("AppError", () => {
  it("is an instance of Error", () => {
    const error = new AppError("boom", 500, "INTERNAL");

    assert.ok(error instanceof Error);
    assert.ok(error instanceof AppError);
  });

  it("carries the message, status code and error code", () => {
    const error = new AppError("not found", 404, "RESOURCE_NOT_FOUND");

    assert.equal(error.message, "not found");
    assert.equal(error.statusCode, 404);
    assert.equal(error.code, "RESOURCE_NOT_FOUND");
    assert.equal(error.name, "AppError");
  });
});

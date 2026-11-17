import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { before, describe, it } from "node:test";

import { SignJWT } from "jose";

let createSessionToken;
let verifySessionToken;
let config;

before(async () => {
  // The config module validates every environment variable on import, so the
  // test environment must be loaded before importing anything that uses it.
  process.loadEnvFile(new URL("../.env.test", import.meta.url));

  ({ createSessionToken, verifySessionToken } = await import(
    "../services/authService.js"
  ));
  ({ config } = await import("../config/env.js"));
});

describe("authService", () => {
  it("creates a token that can be verified back to the same customer", async () => {
    const customerId = randomUUID();

    const { token, sessionId } = await createSessionToken(customerId);

    assert.equal(typeof token, "string");
    assert.ok(token.length > 0);

    const claims = await verifySessionToken(token);

    assert.equal(claims.customerId, customerId);
    assert.equal(claims.sessionId, sessionId);
  });

  it("generates a different session id on every call", async () => {
    const customerId = randomUUID();

    const first = await createSessionToken(customerId);
    const second = await createSessionToken(customerId);

    assert.notEqual(first.sessionId, second.sessionId);
  });

  it("rejects a token whose claims are not valid UUIDs", async () => {
    const secretKey = new TextEncoder().encode(config.auth.jwt.secret);

    const token = await new SignJWT({ sid: "not-a-uuid" })
      .setProtectedHeader({ alg: config.auth.jwt.algorithm, typ: "JWT" })
      .setSubject("also-not-a-uuid")
      .setIssuer(config.auth.jwt.issuer)
      .setAudience(config.auth.jwt.audience)
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(secretKey);

    await assert.rejects(() => verifySessionToken(token));
  });

  it("rejects a token signed by an untrusted issuer", async () => {
    const secretKey = new TextEncoder().encode(config.auth.jwt.secret);

    const token = await new SignJWT({ sid: randomUUID() })
      .setProtectedHeader({ alg: config.auth.jwt.algorithm, typ: "JWT" })
      .setSubject(randomUUID())
      .setIssuer("someone-else")
      .setAudience(config.auth.jwt.audience)
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(secretKey);

    await assert.rejects(() => verifySessionToken(token));
  });
});

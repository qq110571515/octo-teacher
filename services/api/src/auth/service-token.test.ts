import assert from "node:assert/strict";
import test from "node:test";
import { authorizeBearerToken } from "./service-token.js";

test("service token remains closed when the server secret is absent", () => {
  assert.equal(authorizeBearerToken("Bearer value", undefined), "not_configured");
});

test("service token rejects missing and incorrect bearer credentials", () => {
  assert.equal(authorizeBearerToken(undefined, "expected"), "unauthorized");
  assert.equal(authorizeBearerToken("Basic expected", "expected"), "unauthorized");
  assert.equal(authorizeBearerToken("Bearer wrong", "expected"), "unauthorized");
});

test("service token accepts an exact bearer credential", () => {
  assert.equal(authorizeBearerToken("Bearer expected", "expected"), "authorized");
});

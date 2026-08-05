import test from "node:test";
import assert from "node:assert/strict";
import { portalCorsPolicy } from "./portal-cors.js";

test("portal CORS allows the production portal and completes preflight", () => {
  const policy = portalCorsPolicy("OPTIONS", "https://octoteacher.com");

  assert.equal(policy.preflight, true);
  assert.equal(policy.headers["access-control-allow-origin"], "https://octoteacher.com");
  assert.match(policy.headers["access-control-allow-methods"] ?? "", /PUT/);
  assert.match(policy.headers["access-control-allow-methods"] ?? "", /PATCH/);
  assert.match(policy.headers["access-control-allow-methods"] ?? "", /DELETE/);
});

test("portal CORS does not grant access to an unapproved origin", () => {
  const policy = portalCorsPolicy("GET", "https://example.com");

  assert.equal(policy.preflight, false);
  assert.equal(policy.headers["access-control-allow-origin"], undefined);
});

import assert from "node:assert/strict";
import test from "node:test";
import { base64URLSHA256, sha256 } from "./apple-identity.js";

test("nonce hashing is deterministic and uses URL-safe encoding for Apple", () => {
  assert.equal(sha256("nonce"), "78377b525757b494427f89014f97d79928f3938d14eb51e20fb5dec9834eb304");
  assert.match(base64URLSHA256("nonce"), /^[A-Za-z0-9_-]+$/);
  assert.equal(base64URLSHA256("nonce").includes("="), false);
});

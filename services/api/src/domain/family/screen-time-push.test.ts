import assert from "node:assert/strict";
import test from "node:test";
import { normalizeChildPushRegistration, screenTimeWakePayload } from "./screen-time-push.js";

test("child push registration accepts only bounded hexadecimal APNs tokens", () => {
  const token = "AB".repeat(32);
  assert.deepEqual(normalizeChildPushRegistration({
    token,
    environment: "development",
  }), {
    token: token.toLowerCase(),
    environment: "development",
  });
  assert.throws(() => normalizeChildPushRegistration({
    token: "not-a-token",
    environment: "development",
  }));
});
test("screen time wake push contains no family, child, app, or point data", () => {
  const payload = screenTimeWakePayload({
    revision: 12,
    commandId: "control:1234",
  });
  assert.deepEqual(payload, {
    aps: { "content-available": 1 },
    octoteacher: {
      kind: "screen_time_sync",
      revision: 12,
      commandId: "control:1234",
    },
  });
  const json = JSON.stringify(payload);
  assert.equal(json.includes("child"), false);
  assert.equal(json.includes("selection"), false);
  assert.equal(json.includes("points"), false);
});

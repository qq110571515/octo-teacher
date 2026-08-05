import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import {
  childDeviceProtocolDecision,
  CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION,
  requireCurrentChildDeviceProtocol,
} from "./child-device-protocol.js";

test("old child apps must update before using current family APIs", () => {
  assert.equal(childDeviceProtocolDecision({ clientGeneration: undefined, bindingGeneration: 1 }), "client_update_required");
  assert.equal(childDeviceProtocolDecision({ clientGeneration: 1, bindingGeneration: 1 }), "client_update_required");
});

test("an upgraded child app must rebind when its token came from an older protocol", () => {
  assert.equal(childDeviceProtocolDecision({
    clientGeneration: CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION,
    bindingGeneration: 1,
  }), "device_rebind_required");
  assert.equal(childDeviceProtocolDecision({
    clientGeneration: CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION,
    bindingGeneration: CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION,
  }), "compatible");
});

test("invite claims accept only the server's exact child protocol generation", () => {
  assert.equal(requireCurrentChildDeviceProtocol("2"), 2);
  assert.throws(() => requireCurrentChildDeviceProtocol(1), FamilyCloudError);
  assert.throws(() => requireCurrentChildDeviceProtocol(3), FamilyCloudError);
});

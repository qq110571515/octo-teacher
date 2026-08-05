import assert from "node:assert/strict";
import test from "node:test";
import type { ChildDeviceSessionContext, FamilyCloudSnapshot } from "../../../src/domain/family/cloud-types.js";
import type { ApiResponse } from "../../_http.js";
import {
  handleChildDeviceProfile,
  type ChildDeviceProfileHandlerDependencies,
} from "./profile.js";

const context: ChildDeviceSessionContext = {
  deviceId: "device-id",
  familyId: "family-id",
  childProfileId: "child-id",
  devicePublicRef: "device-public-ref",
  protocolGeneration: 2,
};

const child: FamilyCloudSnapshot["children"][number] & {
  family: { id: string; publicRef: string; displayName: string };
} = {
  id: "child-id",
  publicRef: "child-public-ref",
  displayName: "Alex",
  preReaderMode: true,
  interfaceLanguage: "english",
  contentLanguage: "english",
  dailyLimitMinutes: 120,
  exchangePolicy: {
    baseMonthlyAllowance: 0,
    allowanceDayOfMonth: 1,
    screenRate: "one_point_per_minute",
    pointsPerCurrencyUnit: 10,
    pocketMoneyRequiresApproval: true,
    currencySymbol: "$",
  },
  screenTimeStatus: {
    authorization: "not_requested",
    enforcement: "waiting_for_authorization",
    updatedAt: "2026-07-17T00:00:00.000Z",
  },
  screenTimeEmergency: {
    schemaVersion: 1,
    status: "idle",
    updatedAt: "2026-07-17T00:00:00.000Z",
  },
  growthPointBalance: 0,
  profileVersion: 2,
  family: { id: "family-id", publicRef: "family-public-ref", displayName: "Family" },
};

function responseRecorder(): {
  response: ApiResponse;
  result: { status?: number; body?: unknown; headers: Record<string, string> };
} {
  const result: { status?: number; body?: unknown; headers: Record<string, string> } = { headers: {} };
  const response: ApiResponse = {
    status(code) {
      result.status = code;
      return response;
    },
    json(body) {
      result.body = body;
    },
    setHeader(name, value) {
      result.headers[name.toLowerCase()] = value;
    },
  };
  return { response, result };
}

function dependencies(overrides: Partial<ChildDeviceProfileHandlerDependencies> = {}): ChildDeviceProfileHandlerDependencies {
  return {
    requireSession: async () => context,
    loadProfile: async () => child,
    updateInterfaceLanguage: async () => child,
    ...overrides,
  };
}

test("PUT child device profile updates only the authenticated child's interface language", async () => {
  const { response, result } = responseRecorder();
  let updatedLanguage: "chinese" | "english" | undefined;
  await handleChildDeviceProfile(
    { method: "PUT", body: { interfaceLanguage: "english" } },
    response,
    dependencies({
      updateInterfaceLanguage: async (receivedContext, language) => {
        assert.deepEqual(receivedContext, context);
        updatedLanguage = language;
        return child;
      },
    }),
  );

  assert.equal(updatedLanguage, "english");
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { child });
});

test("PUT child device profile rejects attempts to update other fields", async () => {
  const { response, result } = responseRecorder();
  let repositoryCalled = false;
  await handleChildDeviceProfile(
    { method: "PUT", body: { interfaceLanguage: "english", displayName: "Changed" } },
    response,
    dependencies({
      updateInterfaceLanguage: async () => {
        repositoryCalled = true;
        return child;
      },
    }),
  );

  assert.equal(repositoryCalled, false);
  assert.equal(result.status, 400);
  assert.deepEqual(result.body, { error: "child_device_profile_fields_forbidden" });
});

test("child device profile route rejects unsupported methods before authentication", async () => {
  const { response, result } = responseRecorder();
  let authenticationCalled = false;
  await handleChildDeviceProfile(
    { method: "PATCH" },
    response,
    dependencies({
      requireSession: async () => {
        authenticationCalled = true;
        return context;
      },
    }),
  );

  assert.equal(authenticationCalled, false);
  assert.equal(result.status, 405);
  assert.deepEqual(result.body, { error: "method_not_allowed" });
});

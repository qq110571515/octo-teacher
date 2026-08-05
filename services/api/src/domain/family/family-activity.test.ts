import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import {
  normalizeActivitySummaryWindowDays,
  normalizeActivitySummaryDate,
  normalizeActivitySummaryTimeZone,
  normalizeFamilyActivityEvent,
  normalizeFamilyActivityPayload,
  normalizeScreenTimeAppDailyRows,
} from "./family-activity.js";

const now = new Date("2026-07-15T12:00:00.000Z");

function errorCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof FamilyCloudError && error.code === code;
}

test("activity payload accepts the exact single and batch contracts", () => {
  const single = normalizeFamilyActivityPayload({
    event: {
      clientRef: "evt_local_123",
      kind: "reading",
      occurredAt: "2026-07-15T11:45:00.000Z",
      durationSeconds: 900,
      progressPercent: 35,
      displayName: "The Picture Alphabet",
      resourceRef: "book_local_123",
    },
  }, now);
  assert.equal(single.length, 1);
  assert.equal(single[0]?.occurredAt, "2026-07-15T11:45:00.000Z");
  assert.match(single[0]?.payloadHash ?? "", /^[0-9a-f]{64}$/);

  const batch = normalizeFamilyActivityPayload({
    events: [{
      clientRef: "evt_task_123",
      kind: "task",
      occurredAt: "2026-07-15T11:50:00.000Z",
      progressPercent: 100,
      displayName: "Tidy the room",
    }, {
      clientRef: "evt_video_123",
      kind: "video",
      occurredAt: "2026-07-15T11:55:00.000Z",
      durationSeconds: 300,
      displayName: "Water cycle",
      resourceRef: "video_123",
    }],
  }, now);
  assert.deepEqual(batch.map((event) => event.kind), ["task", "video"]);
});

test("activity normalization produces stable hashes for idempotent retries", () => {
  const event = {
    clientRef: "evt_local_123",
    kind: "screen_time",
    occurredAt: "2026-07-15T11:00:00-01:00",
    durationSeconds: 2_700,
    displayName: "Game session",
    resourceRef: "screen_session_123",
  };
  const first = normalizeFamilyActivityEvent(event, now);
  const retry = normalizeFamilyActivityEvent(event, now);
  assert.equal(first.occurredAt, "2026-07-15T12:00:00.000Z");
  assert.equal(first.payloadHash, retry.payloadHash);

  const altered = normalizeFamilyActivityEvent({ ...event, durationSeconds: 3_600 }, now);
  assert.notEqual(first.payloadHash, altered.payloadHash);
});

test("activity normalization accepts guardian remote authorization receipts", () => {
  const event = normalizeFamilyActivityEvent({
    clientRef: "screen-time-complete:guardian-remote-123",
    kind: "screen_time",
    occurredAt: "2026-07-15T11:45:00.000Z",
    durationSeconds: 1_800,
    displayName: "App Authorized Time",
    resourceRef: "authority:guardian_remote",
  }, now);

  assert.equal(event.kind, "screen_time");
  assert.equal(event.durationSeconds, 1_800);
  assert.equal(event.resourceRef, "authority:guardian_remote");
});

test("activity payload rejects ambiguous shapes, duplicate refs, and raw sensitive fields", () => {
  const valid = {
    clientRef: "evt_local_123",
    kind: "task",
    occurredAt: "2026-07-15T11:45:00.000Z",
    progressPercent: 100,
    displayName: "Make the bed",
  };
  assert.throws(() => normalizeFamilyActivityPayload({ event: valid, events: [valid] }, now),
    errorCode("invalid_activity_payload"));
  assert.throws(() => normalizeFamilyActivityPayload({ events: [valid, valid] }, now),
    errorCode("duplicate_activity_client_ref"));
  assert.throws(() => normalizeFamilyActivityPayload({ event: { ...valid, photo: "base64" } }, now),
    errorCode("forbidden_activity_field"));
  assert.throws(() => normalizeFamilyActivityPayload({ event: { ...valid, rawChat: "private" } }, now),
    errorCode("forbidden_activity_field"));
  assert.throws(() => normalizeFamilyActivityPayload({ event: { ...valid, displayName: "https://private.example" } }, now),
    errorCode("forbidden_activity_content"));
  assert.throws(() => normalizeFamilyActivityPayload({ event: { ...valid, displayName: "API key placeholder" } }, now),
    errorCode("forbidden_activity_content"));
  assert.throws(() => normalizeFamilyActivityPayload({ event: { ...valid, resourceRef: "managedsettings_token_123" } }, now),
    errorCode("forbidden_activity_resource_ref"));
});

test("activity event kinds require useful sanitized measurements", () => {
  const common = {
    clientRef: "evt_local_123",
    occurredAt: "2026-07-15T11:45:00.000Z",
    displayName: "Activity",
  };
  assert.throws(() => normalizeFamilyActivityEvent({ ...common, kind: "reading" }, now),
    errorCode("activity_duration_required"));
  assert.throws(() => normalizeFamilyActivityEvent({ ...common, kind: "task" }, now),
    errorCode("activity_measure_required"));
  assert.throws(() => normalizeFamilyActivityEvent({ ...common, kind: "video", durationSeconds: 43_201 }, now),
    errorCode("invalid_activity_duration"));
});

test("activity summary window is bounded and defaults safely", () => {
  assert.equal(normalizeActivitySummaryWindowDays(undefined), 90);
  assert.equal(normalizeActivitySummaryWindowDays("1"), 1);
  assert.equal(normalizeActivitySummaryWindowDays("90"), 90);
  assert.throws(() => normalizeActivitySummaryWindowDays("0"),
    errorCode("invalid_activity_summary_window"));
  assert.throws(() => normalizeActivitySummaryWindowDays("91"),
    errorCode("invalid_activity_summary_window"));
  assert.throws(() => normalizeActivitySummaryWindowDays("1 day"),
    errorCode("invalid_activity_summary_window"));
});

test("activity summary calendar date rejects impossible dates", () => {
  assert.equal(normalizeActivitySummaryDate(undefined), undefined);
  assert.equal(normalizeActivitySummaryDate("2026-07-25"), "2026-07-25");
  assert.throws(() => normalizeActivitySummaryDate("2026-02-29"),
    /invalid_activity_summary_date/);
  assert.throws(() => normalizeActivitySummaryDate("07-25-2026"),
    /invalid_activity_summary_date/);
});

test("activity summary time zone accepts IANA identifiers only", () => {
  assert.equal(normalizeActivitySummaryTimeZone(undefined), "UTC");
  assert.equal(
    normalizeActivitySummaryTimeZone("America/Los_Angeles"),
    "America/Los_Angeles",
  );
  assert.throws(() => normalizeActivitySummaryTimeZone("Not/A_Zone"),
    /invalid_activity_summary_time_zone/);
});

test("screen time app daily rows expose only privacy-safe aliases", () => {
  const rows = normalizeScreenTimeAppDailyRows([
    {
      date: "2026-07-15",
      resourceRef: "authority:growth_points:app:0123456789abcdef0123456789abcdef",
      durationSeconds: 3_601.9,
      eventCount: 2.8,
    },
    {
      date: "invalid",
      resourceRef: "authority:parent_pin:app:fedcba9876543210fedcba9876543210",
      durationSeconds: 1_800,
      eventCount: 1,
    },
    {
      date: "2026-07-14",
      resourceRef: "authority:growth_points",
      durationSeconds: 900,
      eventCount: 1,
    },
  ]);

  assert.deepEqual(rows, [{
    date: "2026-07-15",
    appRef: "app:0123456789abcdef0123456789abcdef",
    authority: "growth_points",
    durationSeconds: 3_601,
    eventCount: 2,
  }]);
});

test("screen time app daily rows clamp unsafe counts and honor the result limit", () => {
  const rows = normalizeScreenTimeAppDailyRows([
    {
      date: "2026-07-15",
      resourceRef: "authority:parent_pin:app:0123456789abcdef0123456789abcdef",
      durationSeconds: -10,
      eventCount: -2,
    },
    {
      date: "2026-07-14",
      resourceRef: "authority:parent_pin:app:fedcba9876543210fedcba9876543210",
      durationSeconds: 600,
      eventCount: 1,
    },
  ], 1);

  assert.equal(rows.length, 1);
  assert.equal(rows[0]?.durationSeconds, 0);
  assert.equal(rows[0]?.eventCount, 0);
});

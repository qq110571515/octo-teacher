import assert from "node:assert/strict";
import test from "node:test";
import {
  buildPortalActivityByChild,
  emptyPortalChildActivity,
  type PortalActivityRecentRow,
} from "./family-portal-activity.js";

test("portal activity keeps complete per-child totals independent from recent rows", () => {
  const activity = buildPortalActivityByChild(
    [
      { childProfileId: "child-a", kind: "screen_time", durationSeconds: 3_600 },
      { childProfileId: "child-a", kind: "reading", durationSeconds: 900 },
      { childProfileId: "child-b", kind: "screen_time", durationSeconds: 120 },
      { childProfileId: "child-b", kind: "screen_time", durationSeconds: 30 },
    ],
    [
      recent("a-1", "child-a", "2026-07-25T10:00:00.000Z"),
      recent("b-1", "child-b", "2026-07-25T09:00:00.000Z"),
    ],
  );

  assert.deepEqual(activity.get("child-a")?.durationSeconds, {
    task: 0,
    reading: 900,
    video: 0,
    screen_time: 3_600,
    creation: 0,
  });
  assert.equal(activity.get("child-b")?.durationSeconds.screen_time, 150);
  assert.deepEqual(activity.get("child-a")?.recent.map((row) => row.eventId), ["a-1"]);
  assert.deepEqual(activity.get("child-b")?.recent.map((row) => row.eventId), ["b-1"]);
});

test("portal activity caps recent history independently for every child", () => {
  const recentRows = [
    ...Array.from({ length: 25 }, (_, index) =>
      recent(`a-${index}`, "child-a", `2026-07-25T10:${String(59 - index).padStart(2, "0")}:00.000Z`)),
    ...Array.from({ length: 22 }, (_, index) =>
      recent(`b-${index}`, "child-b", `2026-07-25T09:${String(59 - index).padStart(2, "0")}:00.000Z`)),
  ];

  const activity = buildPortalActivityByChild([], recentRows);

  assert.equal(activity.get("child-a")?.recent.length, 20);
  assert.equal(activity.get("child-b")?.recent.length, 20);
  assert.equal(activity.get("child-a")?.recent[0]?.eventId, "a-0");
  assert.equal(activity.get("child-b")?.recent[0]?.eventId, "b-0");
});

test("portal activity keeps authoritative daily Screen Time totals per child", () => {
  const activity = buildPortalActivityByChild([], [], [
    { childProfileId: "child-a", date: "2026-07-26", durationSeconds: 3_600, eventCount: 4 },
    { childProfileId: "child-b", date: "2026-07-26", durationSeconds: 900, eventCount: 1 },
    { childProfileId: "child-a", date: "2026-07-25", durationSeconds: 1_200, eventCount: 2 },
  ]);

  assert.deepEqual(activity.get("child-a")?.screenTimeDaily, [
    { date: "2026-07-26", durationSeconds: 3_600, eventCount: 4 },
    { date: "2026-07-25", durationSeconds: 1_200, eventCount: 2 },
  ]);
  assert.deepEqual(activity.get("child-b")?.screenTimeDaily, [
    { date: "2026-07-26", durationSeconds: 900, eventCount: 1 },
  ]);
});

test("portal activity caps daily Screen Time history independently for every child", () => {
  const dailyRows = [
    ...Array.from({ length: 35 }, (_, index) => ({
      childProfileId: "child-a",
      date: dateKeyDaysBefore("2026-07-31", index),
      durationSeconds: 60,
      eventCount: 1,
    })),
    ...Array.from({ length: 33 }, (_, index) => ({
      childProfileId: "child-b",
      date: dateKeyDaysBefore("2026-06-30", index),
      durationSeconds: 120,
      eventCount: 2,
    })),
  ];

  const activity = buildPortalActivityByChild([], [], dailyRows);

  assert.equal(activity.get("child-a")?.screenTimeDaily.length, 31);
  assert.equal(activity.get("child-b")?.screenTimeDaily.length, 31);
});

test("portal activity keeps only valid anonymous per-app authorization windows", () => {
  const activity = buildPortalActivityByChild([], [], [], [
    {
      childProfileId: "child-a",
      date: "2026-07-26",
      resourceRef: "authority:growth_points:app:0123456789abcdef0123456789abcdef",
      durationSeconds: 2_700,
      eventCount: 2,
    },
    {
      childProfileId: "child-a",
      date: "2026-07-26",
      resourceRef: "authority:parent_pin:app:fedcba9876543210fedcba9876543210",
      durationSeconds: 3_600,
      eventCount: 1,
    },
    {
      childProfileId: "child-b",
      date: "2026-07-26",
      resourceRef: "authority:growth_points:app:not-an-anonymous-id",
      durationSeconds: 900,
      eventCount: 1,
    },
  ]);

  assert.deepEqual(activity.get("child-a")?.screenTimeAppDaily, [
    {
      date: "2026-07-26",
      appRef: "app:0123456789abcdef0123456789abcdef",
      authority: "growth_points",
      durationSeconds: 2_700,
      eventCount: 2,
    },
    {
      date: "2026-07-26",
      appRef: "app:fedcba9876543210fedcba9876543210",
      authority: "parent_pin",
      durationSeconds: 3_600,
      eventCount: 1,
    },
  ]);
  assert.equal(activity.has("child-b"), false);
});

test("empty portal activity returns an isolated zero-filled value", () => {
  const first = emptyPortalChildActivity();
  const second = emptyPortalChildActivity();
  first.durationSeconds.task = 10;

  assert.equal(second.durationSeconds.task, 0);
  assert.deepEqual(second.recent, []);
  assert.deepEqual(second.screenTimeDaily, []);
  assert.deepEqual(second.screenTimeAppDaily, []);
});

function recent(
  eventId: string,
  childProfileId: string,
  occurredAt: string,
): PortalActivityRecentRow {
  return {
    eventId,
    childProfileId,
    kind: "screen_time",
    occurredAt,
    durationSeconds: 60,
    progressPercent: null,
    displayName: `Authorized ${eventId}`,
    resourceRef: null,
  };
}

function dateKeyDaysBefore(dateKey: string, days: number): string {
  const date = new Date(`${dateKey}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

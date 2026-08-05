import type { FamilyConsole } from "./cloud-types.js";
import {
  FAMILY_ACTIVITY_KINDS,
  type FamilyActivityKind,
} from "./family-activity.js";

export type PortalActivitySummaryRow = {
  childProfileId: string;
  kind: FamilyActivityKind;
  durationSeconds: number;
};

export type PortalActivityRecentRow = {
  eventId: string;
  childProfileId: string;
  kind: FamilyActivityKind;
  occurredAt: string;
  durationSeconds: number | null;
  progressPercent: number | null;
  displayName: string;
  resourceRef: string | null;
};

export type PortalActivityDailyRow = {
  childProfileId: string;
  date: string;
  durationSeconds: number;
  eventCount: number;
};

export type PortalActivityAppDailyRow = PortalActivityDailyRow & {
  resourceRef: string;
};

export type PortalChildActivity = NonNullable<FamilyConsole["children"][number]["activity"]>;

export function emptyPortalChildActivity(): PortalChildActivity {
  return {
    windowDays: 90,
    durationSeconds: {
      task: 0,
      reading: 0,
      video: 0,
      screen_time: 0,
      creation: 0,
    },
    screenTimeDaily: [],
    screenTimeAppDaily: [],
    recent: [],
  };
}

export function buildPortalActivityByChild(
  summaryRows: PortalActivitySummaryRow[],
  recentRows: PortalActivityRecentRow[],
  dailyRows: PortalActivityDailyRow[] = [],
  appDailyRows: PortalActivityAppDailyRow[] = [],
): Map<string, PortalChildActivity> {
  const result = new Map<string, PortalChildActivity>();

  const activityFor = (childProfileId: string): PortalChildActivity => {
    const existing = result.get(childProfileId);
    if (existing) return existing;
    const activity = emptyPortalChildActivity();
    result.set(childProfileId, activity);
    return activity;
  };

  for (const row of summaryRows) {
    if (!FAMILY_ACTIVITY_KINDS.includes(row.kind)) continue;
    activityFor(row.childProfileId).durationSeconds[row.kind] += row.durationSeconds;
  }

  for (const row of recentRows) {
    const activity = activityFor(row.childProfileId);
    if (activity.recent.length >= 20) continue;
    activity.recent.push({
      eventId: row.eventId,
      kind: row.kind,
      occurredAt: new Date(row.occurredAt).toISOString(),
      ...(row.durationSeconds == null ? {} : { durationSeconds: row.durationSeconds }),
      ...(row.progressPercent == null ? {} : { progressPercent: row.progressPercent }),
      displayName: row.displayName,
      ...(row.resourceRef == null ? {} : { resourceRef: row.resourceRef }),
    });
  }

  for (const row of dailyRows) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(row.date)) continue;
    const activity = activityFor(row.childProfileId);
    if (activity.screenTimeDaily.length >= 31) continue;
    activity.screenTimeDaily.push({
      date: row.date,
      durationSeconds: Math.max(0, row.durationSeconds),
      eventCount: Math.max(0, row.eventCount),
    });
  }

  for (const row of appDailyRows) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(row.date)) continue;
    const match = /^authority:([a-z0-9_]+):app:([a-f0-9]{32})$/.exec(row.resourceRef);
    if (!match) continue;
    const activity = activityFor(row.childProfileId);
    if (activity.screenTimeAppDaily.length >= 200) continue;
    activity.screenTimeAppDaily.push({
      date: row.date,
      appRef: `app:${match[2]}`,
      authority: match[1],
      durationSeconds: Math.max(0, row.durationSeconds),
      eventCount: Math.max(0, row.eventCount),
    });
  }

  return result;
}

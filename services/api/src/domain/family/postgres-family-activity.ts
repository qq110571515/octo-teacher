import type { TransactionSql } from "postgres";
import { sha256 } from "../../auth/apple-identity.js";
import { platformDatabase } from "../../database/postgres.js";
import type {
  ChildDeviceSessionContext,
  GuardianSessionContext,
} from "./cloud-types.js";
import { FamilyCloudError } from "./cloud-types.js";
import {
  normalizeFamilyActivityPayload,
  type FamilyActivityWriteResult,
  type NormalizedFamilyActivityEvent,
} from "./family-activity.js";

type ActivityActor = {
  kind: "child_device" | "guardian";
  familyId: string;
  childProfileId: string;
  deviceId?: string;
  guardianId?: string;
};

async function recordEvents(
  tx: TransactionSql,
  actor: ActivityActor,
  events: NormalizedFamilyActivityEvent[],
): Promise<FamilyActivityWriteResult> {
  const results: FamilyActivityWriteResult["events"] = [];
  for (const event of events) {
    const inserted = await tx<{ id: string }[]>`
      insert into platform_family_activity_events (
        family_id, child_profile_id, device_id, guardian_id, actor_kind,
        client_ref, kind, occurred_at, duration_seconds, progress_percent,
        display_name, resource_ref, payload_hash
      ) values (
        ${actor.familyId}, ${actor.childProfileId}, ${actor.deviceId ?? null}, ${actor.guardianId ?? null},
        ${actor.kind}, ${event.clientRef}, ${event.kind}, ${event.occurredAt},
        ${event.durationSeconds ?? null}, ${event.progressPercent ?? null}, ${event.displayName},
        ${event.resourceRef ?? null}, ${event.payloadHash}
      )
      on conflict (family_id, child_profile_id, actor_kind, client_ref) do nothing
      returning id
    `;
    if (inserted[0]) {
      results.push({ clientRef: event.clientRef, status: "created", eventId: inserted[0].id });
      continue;
    }
    const existing = await tx<{ id: string; payloadHash: string }[]>`
      select id, payload_hash as "payloadHash"
      from platform_family_activity_events
      where family_id = ${actor.familyId}
        and child_profile_id = ${actor.childProfileId}
        and actor_kind = ${actor.kind}
        and client_ref = ${event.clientRef}
      for update
    `;
    if (!existing[0] || existing[0].payloadHash !== event.payloadHash) {
      throw new FamilyCloudError("activity_client_ref_conflict");
    }
    results.push({ clientRef: event.clientRef, status: "duplicate", eventId: existing[0].id });
  }
  const duplicateCount = results.filter((result) => result.status === "duplicate").length;
  return {
    acceptedCount: results.length - duplicateCount,
    duplicateCount,
    events: results,
  };
}

export async function recordChildDeviceActivityEvents(
  context: ChildDeviceSessionContext,
  value: unknown,
): Promise<FamilyActivityWriteResult> {
  const events = normalizeFamilyActivityPayload(value);
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const child = await tx<{ id: string }[]>`
      select p.id
      from platform_child_profiles p
      join platform_family_devices d on d.child_profile_id = p.id and d.family_id = p.family_id
      where p.id = ${context.childProfileId}
        and p.family_id = ${context.familyId}
        and p.status = 'active'
        and d.id = ${context.deviceId}
        and d.status = 'active'
        and d.role = 'child'
      for update of p
    `;
    if (!child[0]) throw new FamilyCloudError("activity_child_access_denied");
    const result = await recordEvents(tx, {
      kind: "child_device",
      familyId: context.familyId,
      childProfileId: context.childProfileId,
      deviceId: context.deviceId,
    }, events);
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref, detail)
      values (
        ${context.familyId}, 'family_activity_recorded', 'child_device', ${sha256(context.deviceId)},
        ${context.childProfileId}, ${tx.json({ count: events.length, kinds: [...new Set(events.map((event) => event.kind))] })}
      )
    `;
    return result;
  });
}

export async function recordGuardianActivityEvents(input: {
  context: GuardianSessionContext;
  familyId: string;
  childProfileId: string;
  value: unknown;
}): Promise<FamilyActivityWriteResult> {
  const events = normalizeFamilyActivityPayload(input.value);
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const membership = await tx<{ childProfileId: string }[]>`
      select p.id as "childProfileId"
      from platform_family_guardians m
      join platform_families f on f.id = m.family_id and f.status = 'active'
      join platform_child_profiles p on p.family_id = f.id and p.status = 'active'
      where m.guardian_id = ${input.context.guardianId}
        and m.family_id = ${input.familyId}
        and m.status = 'active'
        and p.id = ${input.childProfileId}
      for update of p
    `;
    if (!membership[0]) throw new FamilyCloudError("activity_child_access_denied");
    const result = await recordEvents(tx, {
      kind: "guardian",
      familyId: input.familyId,
      childProfileId: input.childProfileId,
      guardianId: input.context.guardianId,
    }, events);
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref, detail)
      values (
        ${input.familyId}, 'family_activity_recorded', 'guardian', ${sha256(input.context.guardianId)},
        ${input.childProfileId}, ${tx.json({ count: events.length, kinds: [...new Set(events.map((event) => event.kind))] })}
      )
    `;
    return result;
  });
}

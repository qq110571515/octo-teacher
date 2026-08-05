import { createHash } from "node:crypto";
import type { Sql, TransactionSql } from "postgres";
import { platformDatabase } from "../../database/postgres.js";
import { FamilyCloudError } from "./cloud-types.js";
import {
  buildFamilyRepairPlan,
  validateExactFamilyRepair,
  type ExactFamilyRepairInspection,
  type ExactFamilyRepairSpec,
  type ExactFamilyRepairValidation,
  type FamilyRepairCandidate,
  type FamilyRepairPlan,
} from "./family-repair.js";

export async function inspectGuardianFamilyRepairPlan(input: {
  guardianId: string;
  targetFamilyId: string;
}): Promise<FamilyRepairPlan> {
  const sql = platformDatabase();
  const families = await sql<Array<Omit<FamilyRepairCandidate, "guardianIds" | "children" | "counts">>>`
    select f.id as "familyId", f.public_ref as "publicRef", f.display_name as "displayName",
      f.created_at::text as "createdAt"
    from platform_family_guardians membership
    join platform_families f on f.id = membership.family_id and f.status = 'active'
    where membership.guardian_id = ${input.guardianId} and membership.status = 'active'
    order by f.created_at
  `;
  if (families.length < 2) throw new FamilyCloudError("family_repair_not_required");
  const candidates: FamilyRepairCandidate[] = [];
  for (const family of families) {
    const [guardians, children, counts] = await Promise.all([
      sql<{ guardianId: string }[]>`
        select guardian_id as "guardianId" from platform_family_guardians
        where family_id = ${family.familyId} and status = 'active' order by created_at
      `,
      sql<FamilyRepairCandidate["children"]>`
        select id, public_ref as "publicRef", client_ref as "clientRef",
          profile_version::int as "profileVersion", updated_at::text as "updatedAt"
        from platform_child_profiles where family_id = ${family.familyId} and status = 'active'
        order by created_at
      `,
      sql<FamilyRepairCandidate["counts"][]>`
        select
          (select count(*)::int from platform_family_devices where family_id = ${family.familyId}) as devices,
          (select count(*)::int from platform_family_tasks where family_id = ${family.familyId}) as tasks,
          (select count(*)::int from platform_family_growth_point_ledger where family_id = ${family.familyId}) as "pointEntries",
          (select count(*)::int from platform_family_content_items where family_id = ${family.familyId}) as "contentItems",
          (select count(*)::int from platform_family_activity_events where family_id = ${family.familyId}) as "activityEvents"
      `,
    ]);
    candidates.push({ ...family, guardianIds: guardians.map((guardian) => guardian.guardianId),
      children, counts: counts[0] ?? { devices: 0, tasks: 0, pointEntries: 0, contentItems: 0, activityEvents: 0 } });
  }
  return buildFamilyRepairPlan(candidates, input.targetFamilyId);
}

type RepairSql = Sql | TransactionSql;

async function inspectExactFamilyRepairWithSql(
  sql: RepairSql,
  spec: ExactFamilyRepairSpec,
  lockFamilies: boolean,
): Promise<ExactFamilyRepairInspection> {
  const familyRows = lockFamilies
    ? await sql<{ id: string; status: string }[]>`
        select id, status from platform_families
        where id in (${spec.sourceFamilyId}, ${spec.targetFamilyId})
        order by id for update
      `
    : await sql<{ id: string; status: string }[]>`
        select id, status from platform_families
        where id in (${spec.sourceFamilyId}, ${spec.targetFamilyId})
        order by id
      `;
  const childIds = spec.childMappings.flatMap((mapping) => [mapping.sourceChildId, mapping.targetChildId]);
  const [membershipRows, children, sourceDevices, taskCounts, activityCounts, inviteCounts] = await Promise.all([
    sql<{ status: string; isCreator: boolean }[]>`
      select status, is_creator as "isCreator" from platform_family_guardians
      where family_id = ${spec.sourceFamilyId} and guardian_id = ${spec.guardianId}
    `,
    sql<ExactFamilyRepairInspection["children"]>`
      select c.id, c.family_id as "familyId", c.client_ref as "clientRef", c.status,
        c.profile_version::int as "profileVersion",
        coalesce((select l.balance_after from platform_family_growth_point_ledger l
          where l.child_profile_id = c.id order by l.created_at desc, l.id desc limit 1), 0)::int as "pointBalance"
      from platform_child_profiles c where c.id = any(${childIds}::uuid[])
      order by c.id
    `,
    sql<ExactFamilyRepairInspection["sourceDevices"]>`
      select public_ref as "publicRef", role, guardian_id as "guardianId",
        child_profile_id as "childProfileId", status
      from platform_family_devices where family_id = ${spec.sourceFamilyId}
      order by public_ref
    `,
    sql<{ sourceTaskCount: number; overlappingTaskCount: number; regressedTargetTaskCount: number }[]>`
      with source_tasks as (
        select t.client_ref, t.version, c.client_ref as child_client_ref
        from platform_family_tasks t join platform_child_profiles c on c.id = t.child_profile_id
        where t.family_id = ${spec.sourceFamilyId}
      ), target_tasks as (
        select t.client_ref, t.version, c.client_ref as child_client_ref
        from platform_family_tasks t join platform_child_profiles c on c.id = t.child_profile_id
        where t.family_id = ${spec.targetFamilyId}
      )
      select count(*)::int as "sourceTaskCount",
        count(target_tasks.client_ref)::int as "overlappingTaskCount",
        count(*) filter (where target_tasks.client_ref is null or target_tasks.version < source_tasks.version)::int
          as "regressedTargetTaskCount"
      from source_tasks left join target_tasks using (client_ref, child_client_ref)
    `,
    sql<{ count: number }[]>`
      select count(*)::int as count from platform_family_activity_events where family_id = ${spec.sourceFamilyId}
    `,
    sql<{ count: number }[]>`
      select count(*)::int as count from platform_family_invites
      where family_id = ${spec.sourceFamilyId} and status = 'active'
    `,
  ]);
  const taskCount = taskCounts[0] ?? { sourceTaskCount: 0, overlappingTaskCount: 0, regressedTargetTaskCount: 0 };
  return {
    sourceFamilyStatus: familyRows.find((family) => family.id === spec.sourceFamilyId)?.status,
    targetFamilyStatus: familyRows.find((family) => family.id === spec.targetFamilyId)?.status,
    sourceMembershipStatus: membershipRows[0]?.status,
    sourceMembershipIsCreator: membershipRows[0]?.isCreator,
    ...taskCount,
    sourceActivityCount: activityCounts[0]?.count ?? 0,
    activeSourceInviteCount: inviteCounts[0]?.count ?? 0,
    children,
    sourceDevices,
  };
}

export async function inspectExactFamilyRepair(
  spec: ExactFamilyRepairSpec,
): Promise<{ inspection: ExactFamilyRepairInspection; validation: ExactFamilyRepairValidation }> {
  const inspection = await inspectExactFamilyRepairWithSql(platformDatabase(), spec, false);
  return { inspection, validation: validateExactFamilyRepair(spec, inspection) };
}

export async function executeExactFamilyRepair(
  spec: ExactFamilyRepairSpec,
): Promise<ExactFamilyRepairValidation & { applied: true; archivedChildCount: number }> {
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const inspection = await inspectExactFamilyRepairWithSql(tx, spec, true);
    const validation = validateExactFamilyRepair(spec, inspection);
    await tx`
      insert into platform_family_guardians (
        family_id, guardian_id, membership_role, is_creator, status, joined_at, created_at
      )
      select ${spec.targetFamilyId}, guardian_id, membership_role, false, 'active', coalesce(joined_at, now()), created_at
      from platform_family_guardians
      where family_id = ${spec.sourceFamilyId} and guardian_id = ${spec.guardianId}
      on conflict (family_id, guardian_id) do update set
        is_creator = false, status = 'active',
        joined_at = coalesce(platform_family_guardians.joined_at, excluded.joined_at)
    `;
    await tx`update platform_family_guardians set status = 'revoked'
      where family_id = ${spec.sourceFamilyId} and guardian_id = ${spec.guardianId}`;
    for (const publicRef of spec.guardianDevicePublicRefs) {
      await tx`update platform_family_devices set family_id = ${spec.targetFamilyId}, last_seen_at = now()
        where family_id = ${spec.sourceFamilyId} and public_ref = ${publicRef}
          and role = 'guardian' and guardian_id = ${spec.guardianId}`;
    }
    for (const mapping of spec.childMappings) {
      for (const publicRef of mapping.childDevicePublicRefs) {
        await tx`update platform_family_devices set family_id = ${spec.targetFamilyId},
          child_profile_id = ${mapping.targetChildId}, last_seen_at = now()
          where family_id = ${spec.sourceFamilyId} and public_ref = ${publicRef}
            and role = 'child' and child_profile_id = ${mapping.sourceChildId}`;
      }
      await tx`update platform_child_profiles set status = 'archived', updated_at = now()
        where family_id = ${spec.sourceFamilyId} and id = ${mapping.sourceChildId}`;
    }
    await tx`update platform_family_invites set status = 'revoked'
      where family_id = ${spec.sourceFamilyId} and status = 'active'`;
    await tx`update platform_families set status = 'deleted', updated_at = now()
      where id = ${spec.sourceFamilyId}`;

    const actorHash = createHash("sha256").update(spec.repairRef).digest("hex");
    const detail = {
      repairRef: spec.repairRef,
      sourceFamilyId: spec.sourceFamilyId,
      targetFamilyId: spec.targetFamilyId,
      preservedTaskCount: validation.sourceTaskCount,
      movedGuardianDeviceCount: validation.guardianDeviceCount,
      movedChildDeviceCount: validation.childDeviceCount,
      revokedInviteCount: validation.activeSourceInviteCount,
      pointLedgerMoved: false,
      taskRowsMoved: false,
    };
    await tx`insert into platform_family_audit
      (family_id, action, actor_kind, actor_ref_hash, target_public_ref, detail)
      values (${spec.targetFamilyId}, 'duplicate_family_repaired', 'system', ${actorHash}, ${spec.repairRef}, ${tx.json(detail)})`;
    await tx`insert into platform_family_audit
      (family_id, action, actor_kind, actor_ref_hash, target_public_ref, detail)
      values (${spec.sourceFamilyId}, 'duplicate_family_archived', 'system', ${actorHash}, ${spec.repairRef}, ${tx.json(detail)})`;

    return { ...validation, applied: true as const, archivedChildCount: spec.childMappings.length };
  });
}

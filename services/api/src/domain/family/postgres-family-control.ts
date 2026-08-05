import { randomBytes, randomUUID } from "node:crypto";
import type { TransactionSql } from "postgres";
import { sha256 } from "../../auth/apple-identity.js";
import { platformDatabase } from "../../database/postgres.js";
import type { ChildDeviceSessionContext, GuardianSessionContext } from "./cloud-types.js";
import { FamilyCloudError } from "./cloud-types.js";
import { buildFamilyChildSurfaces } from "./family-child-surface.js";
import { normalizeScreenTimeAppDailyRows } from "./family-activity.js";
import {
  FAMILY_ACTIVITY_SUMMARY_DAYS,
  FAMILY_SYNC_PAGE_LIMIT,
  childCanSeeFamilyChange,
  normalizeFamilyContent,
  normalizeFamilySyncCursor,
  normalizeMutationReference,
  requireSafeGuardianRevocation,
  type FamilySyncChange,
} from "./family-control.js";

type Member = { guardianId: string; isCreator: boolean };
type ContentAvailability = "processing" | "ready" | "unavailable" | "archived";
type FamilyContentRecord = {
  id: string;
  publicRef: string;
  clientRef: string;
  kind: "book" | "video" | "creation";
  title: string;
  titleEnglish?: string;
  sourceKind: "marketplace" | "cloud_library" | "guardian_upload" | "external" | "generated";
  sourceRef?: string;
  storageObjectKey?: string;
  availability: ContentAvailability;
  metadata: Record<string, string | number | boolean | null>;
  version: number;
  updatedAt: string;
};

function publicRef(prefix: string): string {
  return `${prefix}_${randomBytes(12).toString("hex")}`;
}

function safeText(value: unknown, code: string, maximum: number): string {
  if (typeof value !== "string") throw new FamilyCloudError(code);
  const normalized = value.trim();
  if (!normalized || normalized.length > maximum || /[\u0000-\u001f\u007f]/.test(normalized)) {
    throw new FamilyCloudError(code);
  }
  return normalized;
}

async function guardianMembership(
  tx: TransactionSql,
  context: GuardianSessionContext,
  familyId: string,
  creatorOnly = false,
): Promise<Member> {
  const rows = await tx<Member[]>`
    select m.guardian_id as "guardianId", m.is_creator as "isCreator"
    from platform_family_guardians m
    join platform_families f on f.id = m.family_id and f.status = 'active'
    where m.family_id = ${familyId} and m.guardian_id = ${context.guardianId}
      and m.status = 'active'
    for update of m
  `;
  if (!rows[0]) throw new FamilyCloudError("family_access_denied");
  if (creatorOnly && !rows[0].isCreator) throw new FamilyCloudError("family_creator_required");
  return rows[0];
}

async function childDeviceMembership(tx: TransactionSql, context: ChildDeviceSessionContext): Promise<void> {
  const rows = await tx<{ id: string }[]>`
    select d.id
    from platform_family_devices d
    join platform_child_profiles p on p.id = d.child_profile_id and p.family_id = d.family_id
    join platform_families f on f.id = d.family_id
    where d.id = ${context.deviceId} and d.family_id = ${context.familyId}
      and d.child_profile_id = ${context.childProfileId} and d.role = 'child'
      and d.status = 'active' and p.status = 'active' and f.status = 'active'
    for update of d
  `;
  if (!rows[0]) throw new FamilyCloudError("family_access_denied");
}

async function audit(tx: TransactionSql, input: {
  familyId: string;
  action: string;
  actorKind: "guardian" | "child_device" | "system";
  actorRef: string;
  target?: string;
  detail?: Record<string, unknown>;
}): Promise<void> {
  await tx`
    insert into platform_family_audit (
      family_id, action, actor_kind, actor_ref_hash, target_public_ref, detail
    ) values (
      ${input.familyId}, ${input.action}, ${input.actorKind}, ${sha256(input.actorRef)},
      ${input.target ?? null}, ${tx.json((input.detail ?? {}) as any)}
    )
  `;
}

export async function renameFamily(input: {
  context: GuardianSessionContext;
  familyId: string;
  displayName: unknown;
  baseVersion?: unknown;
}): Promise<{ id: string; publicRef: string; displayName: string; syncVersion: number }> {
  const displayName = safeText(input.displayName, "invalid_family_name", 120);
  const baseVersion = input.baseVersion === undefined ? undefined : Number(input.baseVersion);
  if (baseVersion !== undefined && (!Number.isInteger(baseVersion) || baseVersion < 1)) {
    throw new FamilyCloudError("invalid_family_version");
  }
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    await guardianMembership(tx, input.context, input.familyId);
    const current = await tx<{ id: string; publicRef: string; displayName: string; syncVersion: number }[]>`
      select id, public_ref as "publicRef", display_name as "displayName", sync_version::int as "syncVersion"
      from platform_families where id = ${input.familyId} for update
    `;
    if (!current[0]) throw new FamilyCloudError("family_access_denied");
    if (current[0].displayName === displayName) return current[0];
    if (baseVersion !== undefined && current[0].syncVersion !== baseVersion) {
      throw new FamilyCloudError("stale_family_version");
    }
    const rows = await tx<{ id: string; publicRef: string; displayName: string; syncVersion: number }[]>`
      update platform_families set display_name = ${displayName}
      where id = ${input.familyId}
      returning id, public_ref as "publicRef", display_name as "displayName", sync_version::int as "syncVersion"
    `;
    await audit(tx, { familyId: input.familyId, action: "family.renamed", actorKind: "guardian",
      actorRef: input.context.guardianId, target: rows[0]?.publicRef });
    return rows[0]!;
  });
}

export async function listFamilyMembers(input: {
  context: GuardianSessionContext;
  familyId: string;
  includeRevoked?: boolean;
}): Promise<{
  guardians: Array<{ id: string; displayName: string; isCreator: boolean; status: string; version: number; joinedAt?: string; revokedAt?: string }>;
  children: Array<{ id: string; publicRef: string; displayName: string; status: string; version: number }>;
  devices: Array<{ id: string; publicRef: string; displayName: string; role: string; childProfileId?: string; guardianId?: string; status: string; version: number }>;
}> {
  const sql = platformDatabase();
  await sql.begin((tx) => guardianMembership(tx, input.context, input.familyId));
  const [guardians, children, devices] = await Promise.all([
    sql<any[]>`
      select g.id, coalesce(g.display_name, 'Guardian') as "displayName", m.is_creator as "isCreator",
        m.status, m.membership_version::int as version, m.joined_at::text as "joinedAt", m.revoked_at::text as "revokedAt"
      from platform_family_guardians m join platform_guardian_accounts g on g.id = m.guardian_id
      where m.family_id = ${input.familyId} ${input.includeRevoked ? sql`` : sql`and m.status = 'active'`}
      order by m.is_creator desc, m.created_at
    `,
    sql<any[]>`
      select id, public_ref as "publicRef", display_name as "displayName", status, profile_version::int as version
      from platform_child_profiles where family_id = ${input.familyId}
        ${input.includeRevoked ? sql`` : sql`and status = 'active'`} order by created_at
    `,
    sql<any[]>`
      select id, public_ref as "publicRef", display_name as "displayName", role,
        child_profile_id as "childProfileId", guardian_id as "guardianId", status, sync_version::int as version
      from platform_family_devices where family_id = ${input.familyId}
        ${input.includeRevoked ? sql`` : sql`and status = 'active'`} order by bound_at
    `,
  ]);
  return { guardians, children, devices };
}

export async function revokeFamilyGuardian(input: {
  context: GuardianSessionContext;
  familyId: string;
  guardianId: string;
}): Promise<{ revoked: boolean }> {
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    await guardianMembership(tx, input.context, input.familyId, true);
    const targets = await tx<{ isCreator: boolean; status: string }[]>`
      select is_creator as "isCreator", status from platform_family_guardians
      where family_id = ${input.familyId} and guardian_id = ${input.guardianId} for update
    `;
    if (!targets[0]) throw new FamilyCloudError("guardian_membership_not_found");
    requireSafeGuardianRevocation({ actorGuardianId: input.context.guardianId,
      targetGuardianId: input.guardianId, targetIsCreator: targets[0].isCreator });
    if (targets[0].status === "revoked") return { revoked: false };
    await tx`update platform_family_guardians set status = 'revoked' where family_id = ${input.familyId} and guardian_id = ${input.guardianId}`;
    await tx`update platform_family_devices set status = 'revoked', revoked_at = now()
      where family_id = ${input.familyId} and guardian_id = ${input.guardianId} and status = 'active'`;
    await audit(tx, { familyId: input.familyId, action: "guardian.revoked", actorKind: "guardian",
      actorRef: input.context.guardianId, target: input.guardianId });
    return { revoked: true };
  });
}

export async function archiveFamilyChild(input: {
  context: GuardianSessionContext;
  familyId: string;
  childProfileId: string;
}): Promise<{ archived: boolean }> {
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    await guardianMembership(tx, input.context, input.familyId);
    const families = await tx<{ id: string }[]>`
      select id from platform_families
      where id = ${input.familyId} and status = 'active'
      for update
    `;
    if (!families[0]) throw new FamilyCloudError("family_access_denied");
    const rows = await tx<{ publicRef: string; status: string }[]>`
      select public_ref as "publicRef", status from platform_child_profiles
      where id = ${input.childProfileId} and family_id = ${input.familyId} for update
    `;
    if (!rows[0]) throw new FamilyCloudError("child_profile_not_found");
    if (rows[0].status === "archived") return { archived: false };
    const activeChildren = await tx<{ count: number }[]>`
      select count(*)::int as count from platform_child_profiles
      where family_id = ${input.familyId} and status = 'active'
    `;
    if ((activeChildren[0]?.count ?? 0) <= 1) {
      throw new FamilyCloudError("family_must_keep_one_child");
    }
    await tx`update platform_child_profiles set status = 'archived', profile_version = profile_version + 1,
      updated_at = now() where id = ${input.childProfileId}`;
    await tx`update platform_family_devices set status = 'revoked', revoked_at = now()
      where family_id = ${input.familyId} and child_profile_id = ${input.childProfileId} and status = 'active'`;
    await tx`update platform_family_tasks set status = 'cancelled', version = version + 1, updated_at = now()
      where family_id = ${input.familyId} and child_profile_id = ${input.childProfileId}
        and status not in ('approved', 'cancelled')`;
    await tx`update platform_family_content_assignments set status = 'removed', version = version + 1, updated_at = now()
      where family_id = ${input.familyId} and child_profile_id = ${input.childProfileId} and status <> 'removed'`;
    await audit(tx, { familyId: input.familyId, action: "child.archived", actorKind: "guardian",
      actorRef: input.context.guardianId, target: rows[0].publicRef });
    return { archived: true };
  });
}

async function activitySummaries(
  sql: ReturnType<typeof platformDatabase>,
  familyId: string,
  childId?: string,
  windowDays = FAMILY_ACTIVITY_SUMMARY_DAYS,
  localDate?: string,
  timeZone = "UTC",
) {
  const timeFilter = localDate
    ? sql`and (occurred_at at time zone ${timeZone})::date = ${localDate}::date`
    : sql`and occurred_at >= now() - (${windowDays} * interval '1 day')`;
  return sql<any[]>`
    select child_profile_id as "childProfileId", kind,
      count(*)::int as "eventCount", coalesce(sum(duration_seconds), 0)::int as "durationSeconds",
      max(progress_percent)::int as "maxProgressPercent", max(occurred_at)::text as "lastOccurredAt"
    from platform_family_activity_events
    where family_id = ${familyId} ${timeFilter}
      ${childId ? sql`and child_profile_id = ${childId}` : sql``}
    group by child_profile_id, kind order by child_profile_id, kind
  `;
}

async function guardianSnapshot(familyId: string) {
  const sql = platformDatabase();
  const [family, guardians, children, devices, tasks, taskCursors, balances, pointLedger, content, assignments, activity] = await Promise.all([
    sql<any[]>`select id, public_ref as "publicRef", display_name as "displayName", sync_version::int as version
      from platform_families where id = ${familyId} and status = 'active'`,
    sql<any[]>`select g.id, coalesce(g.display_name, 'Guardian') as "displayName", m.is_creator as "isCreator",
      m.membership_version::int as version from platform_family_guardians m
      join platform_guardian_accounts g on g.id = m.guardian_id where m.family_id = ${familyId} and m.status = 'active'`,
    sql<any[]>`select id, public_ref as "publicRef", client_ref as "clientRef", display_name as "displayName",
      birth_year as "birthYear", pre_reader_mode as "preReaderMode", interface_language as "interfaceLanguage",
      content_language as "contentLanguage", daily_limit_minutes as "dailyLimitMinutes",
      exchange_policy as "exchangePolicy", profile_version::int as version
      from platform_child_profiles where family_id = ${familyId} and status = 'active'`,
    sql<any[]>`select id, public_ref as "publicRef", display_name as "displayName", role,
      guardian_id as "guardianId", child_profile_id as "childProfileId", status, sync_version::int as version
      from platform_family_devices where family_id = ${familyId} and status = 'active'`,
    sql<any[]>`select id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
      title_english as "titleEnglish", status, growth_points as "growthPoints", requires_evidence as "requiresEvidence",
      planned_for::text as "plannedFor", evidence_summary as "evidenceSummary", task_payload as "taskPayload",
      delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
      version, updated_at::text as "updatedAt"
      from platform_family_tasks where family_id = ${familyId}`,
    sql<any[]>`select child_profile_id as "childProfileId", coalesce(max(cursor), 0)::text as cursor
      from platform_family_task_changes where family_id = ${familyId} group by child_profile_id`,
    sql<any[]>`select id as "childProfileId", growth_point_balance::int as balance
      from platform_child_profiles where family_id = ${familyId} and status = 'active'`,
    sql<any[]>`select id, child_profile_id as "childProfileId", delta::int, entry_kind as "entryKind", source_ref as "sourceRef",
      created_at::text as "createdAt" from platform_family_growth_point_ledger
      where family_id = ${familyId} order by created_at desc limit 200`,
    sql<FamilyContentRecord[]>`select id, public_ref as "publicRef", client_ref as "clientRef", kind, title,
      title_english as "titleEnglish", source_kind as "sourceKind", source_ref as "sourceRef",
      storage_object_key as "storageObjectKey", availability, metadata, version, updated_at::text as "updatedAt"
      from platform_family_content_items where family_id = ${familyId} and availability <> 'archived' order by updated_at desc`,
    sql<any[]>`select id, content_item_id as "contentItemId", child_profile_id as "childProfileId", status,
      progress_percent as "progressPercent", duration_seconds as "durationSeconds", version,
      updated_at::text as "updatedAt" from platform_family_content_assignments
      where family_id = ${familyId} and status <> 'removed'`,
    activitySummaries(sql, familyId),
  ]);
  if (!family[0]) throw new FamilyCloudError("family_access_denied");
  return { schemaVersion: 1, generatedAt: new Date().toISOString(), family: family[0], guardians,
    children, devices, tasks, taskCursors, points: { balances, recentLedger: pointLedger }, content, assignments, activity };
}

export async function loadGuardianFamilySnapshot(context: GuardianSessionContext, familyId: string) {
  const sql = platformDatabase();
  await sql.begin((tx) => guardianMembership(tx, context, familyId));
  return guardianSnapshot(familyId);
}

export async function loadChildFamilySnapshot(context: ChildDeviceSessionContext) {
  const sql = platformDatabase();
  await sql.begin((tx) => childDeviceMembership(tx, context));
  const full = await guardianSnapshot(context.familyId);
  const assignments = full.assignments.filter((entry: any) => entry.childProfileId === context.childProfileId);
  const assignedContentIds = new Set(assignments.map((entry: any) => entry.contentItemId));
  return {
    schemaVersion: full.schemaVersion,
    generatedAt: full.generatedAt,
    family: full.family,
    child: full.children.find((child: any) => child.id === context.childProfileId),
    device: full.devices.find((device: any) => device.id === context.deviceId),
    tasks: full.tasks.filter((task: any) => task.childProfileId === context.childProfileId && task.deliveryStatus === "ready"),
    points: {
      balance: full.points.balances.find((entry: any) => entry.childProfileId === context.childProfileId)?.balance ?? 0,
      recentLedger: full.points.recentLedger.filter((entry: any) => entry.childProfileId === context.childProfileId),
    },
    content: full.content
      .filter((entry: FamilyContentRecord) => entry.availability === "ready" && assignedContentIds.has(entry.id))
      .map(({ storageObjectKey: _storageObjectKey, ...entry }: FamilyContentRecord) => entry),
    assignments,
    activity: full.activity.filter((entry: any) => entry.childProfileId === context.childProfileId),
  };
}

function childSurfacesFromSnapshot(snapshot: Awaited<ReturnType<typeof guardianSnapshot>>) {
  return buildFamilyChildSurfaces({
    generatedAt: snapshot.generatedAt,
    children: snapshot.children,
    tasks: snapshot.tasks,
    taskCursors: snapshot.taskCursors,
    balances: snapshot.points.balances,
    content: snapshot.content,
    assignments: snapshot.assignments,
  });
}

export async function loadGuardianChildSurfaces(context: GuardianSessionContext, familyId: string) {
  const sql = platformDatabase();
  await sql.begin((tx) => guardianMembership(tx, context, familyId));
  return childSurfacesFromSnapshot(await guardianSnapshot(familyId));
}

export async function loadGuardianChildSurface(
  context: GuardianSessionContext,
  familyId: string,
  childProfileId: string,
) {
  const surface = (await loadGuardianChildSurfaces(context, familyId))
    .find((entry) => entry.child.id === childProfileId);
  if (!surface) throw new FamilyCloudError("child_profile_not_found");
  return surface;
}

export async function loadChildDeviceSurface(context: ChildDeviceSessionContext) {
  const sql = platformDatabase();
  await sql.begin((tx) => childDeviceMembership(tx, context));
  const surface = childSurfacesFromSnapshot(await guardianSnapshot(context.familyId))
    .find((entry) => entry.child.id === context.childProfileId);
  if (!surface) throw new FamilyCloudError("child_profile_not_found");
  return surface;
}

async function readChanges(familyId: string, cursor: unknown, childProfileId?: string) {
  const normalizedCursor = normalizeFamilySyncCursor(cursor);
  const sql = platformDatabase();
  const rows = await sql<FamilySyncChange[]>`
    select cursor::text, child_profile_id as "childProfileId", entity_kind as "entityKind",
      entity_ref as "entityRef", operation, entity_version::int as "entityVersion", changed_at::text as "changedAt"
    from platform_family_sync_changes where family_id = ${familyId} and cursor > ${normalizedCursor}::bigint
      ${childProfileId ? sql`and (
        entity_kind = 'family'
        or (child_profile_id = ${childProfileId} and entity_kind not in ('guardian', 'content'))
      )` : sql``}
    order by cursor limit ${FAMILY_SYNC_PAGE_LIMIT + 1}
  `;
  const page = rows.slice(0, FAMILY_SYNC_PAGE_LIMIT);
  return { changes: page, cursor: page.at(-1)?.cursor ?? normalizedCursor,
    hasMore: rows.length > FAMILY_SYNC_PAGE_LIMIT, requiresSnapshot: page.length > 0 };
}

export async function listGuardianFamilyChanges(context: GuardianSessionContext, familyId: string, cursor: unknown) {
  const sql = platformDatabase();
  await sql.begin((tx) => guardianMembership(tx, context, familyId));
  return readChanges(familyId, cursor);
}

export async function listChildFamilyChanges(context: ChildDeviceSessionContext, cursor: unknown) {
  const sql = platformDatabase();
  await sql.begin((tx) => childDeviceMembership(tx, context));
  return readChanges(context.familyId, cursor, context.childProfileId);
}

async function contentMutation(tx: TransactionSql, input: {
  familyId: string; mutationRef: string; payloadHash: string; operation: string; targetId: string;
}): Promise<"created" | "duplicate"> {
  const rows = await tx<{ payloadHash: string; operation: string; targetId: string }[]>`
    insert into platform_family_content_mutations (family_id, mutation_ref, payload_hash, operation, target_id)
    values (${input.familyId}, ${input.mutationRef}, ${input.payloadHash}, ${input.operation}, ${input.targetId})
    on conflict (family_id, mutation_ref) do nothing returning payload_hash as "payloadHash", operation, target_id as "targetId"
  `;
  if (rows[0]) return "created";
  const existing = await tx<{ payloadHash: string; operation: string; targetId: string }[]>`
    select payload_hash as "payloadHash", operation, target_id as "targetId"
    from platform_family_content_mutations where family_id = ${input.familyId} and mutation_ref = ${input.mutationRef}
  `;
  if (!existing[0] || existing[0].payloadHash !== input.payloadHash || existing[0].operation !== input.operation || existing[0].targetId !== input.targetId) {
    throw new FamilyCloudError("content_mutation_ref_conflict");
  }
  return "duplicate";
}

function selectContent(tx: TransactionSql, familyId: string, contentId: string) {
  return tx<FamilyContentRecord[]>`
    select id, public_ref as "publicRef", client_ref as "clientRef", kind, title,
      title_english as "titleEnglish", source_kind as "sourceKind", source_ref as "sourceRef",
      storage_object_key as "storageObjectKey", availability, metadata, version, updated_at::text as "updatedAt"
    from platform_family_content_items where id = ${contentId} and family_id = ${familyId}
  `;
}

export async function upsertFamilyContent(input: {
  context: GuardianSessionContext; familyId: string; value: unknown;
}): Promise<{ status: "created" | "updated" | "duplicate"; content: FamilyContentRecord }> {
  const normalized = normalizeFamilyContent(input.value);
  const raw = input.value as Record<string, unknown>;
  const baseVersion = raw.baseVersion === undefined ? undefined : Number(raw.baseVersion);
  if (baseVersion !== undefined && (!Number.isInteger(baseVersion) || baseVersion < 1)) throw new FamilyCloudError("invalid_content_version");
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    await guardianMembership(tx, input.context, input.familyId);
    await tx`select pg_advisory_xact_lock(hashtextextended(${`${input.familyId}:${normalized.clientRef}`}, 0))`;
    const existing = await tx<{ id: string; version: number }[]>`
      select id, version from platform_family_content_items
      where family_id = ${input.familyId} and client_ref = ${normalized.clientRef} for update
    `;
    if (existing[0] && baseVersion !== undefined && existing[0].version !== baseVersion) throw new FamilyCloudError("stale_content_version");
    const targetId = existing[0]?.id ?? randomUUID();
    const receipt = await contentMutation(tx, { familyId: input.familyId, mutationRef: normalized.mutationRef,
      payloadHash: normalized.payloadHash, operation: "content_upsert", targetId });
    if (receipt === "duplicate") {
      const content = await selectContent(tx, input.familyId, targetId);
      if (!content[0]) throw new FamilyCloudError("content_not_found");
      return { status: "duplicate", content: content[0] };
    }
    await tx`
      insert into platform_family_content_items (
        id, family_id, public_ref, client_ref, kind, title, title_english, source_kind,
        source_ref, storage_object_key, availability, metadata, created_by_guardian_id
      ) values (
        ${targetId}, ${input.familyId}, ${publicRef("content")}, ${normalized.clientRef}, ${normalized.kind},
        ${normalized.title}, ${normalized.titleEnglish ?? null}, ${normalized.sourceKind}, ${normalized.sourceRef ?? null},
        ${normalized.storageObjectKey ?? null}, ${normalized.availability}, ${tx.json(normalized.metadata as any)}, ${input.context.guardianId}
      ) on conflict (family_id, client_ref) do update set
        kind = excluded.kind, title = excluded.title, title_english = excluded.title_english,
        source_kind = excluded.source_kind, source_ref = excluded.source_ref,
        storage_object_key = excluded.storage_object_key, availability = excluded.availability,
        metadata = excluded.metadata, version = platform_family_content_items.version + 1, updated_at = now()
    `;
    const content = await selectContent(tx, input.familyId, targetId);
    await audit(tx, { familyId: input.familyId, action: existing[0] ? "content.updated" : "content.created",
      actorKind: "guardian", actorRef: input.context.guardianId, target: content[0]?.publicRef,
      detail: { kind: normalized.kind, availability: normalized.availability } });
    return { status: existing[0] ? "updated" : "created", content: content[0]! };
  });
}

export async function archiveFamilyContent(input: {
  context: GuardianSessionContext; familyId: string; contentId: string; mutationRef: unknown; baseVersion?: unknown;
}): Promise<{ archived: boolean; content: FamilyContentRecord }> {
  const mutationRef = normalizeMutationReference(input.mutationRef);
  const baseVersion = input.baseVersion === undefined ? undefined : Number(input.baseVersion);
  if (baseVersion !== undefined && (!Number.isInteger(baseVersion) || baseVersion < 1)) {
    throw new FamilyCloudError("invalid_content_version");
  }
  const hash = sha256(JSON.stringify({ contentId: input.contentId, baseVersion: baseVersion ?? null }));
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    await guardianMembership(tx, input.context, input.familyId);
    const current = await selectContent(tx, input.familyId, input.contentId);
    if (!current[0]) throw new FamilyCloudError("content_not_found");
    if (baseVersion !== undefined && current[0].version !== baseVersion) throw new FamilyCloudError("stale_content_version");
    const receipt = await contentMutation(tx, { familyId: input.familyId, mutationRef, payloadHash: hash,
      operation: "content_archive", targetId: input.contentId });
    if (receipt === "duplicate" || current[0].availability === "archived") return { archived: false, content: current[0] };
    await tx`update platform_family_content_items set availability = 'archived', version = version + 1, updated_at = now()
      where id = ${input.contentId}`;
    await tx`update platform_family_content_assignments set status = 'removed', version = version + 1, updated_at = now()
      where family_id = ${input.familyId} and content_item_id = ${input.contentId} and status <> 'removed'`;
    const content = await selectContent(tx, input.familyId, input.contentId);
    await audit(tx, { familyId: input.familyId, action: "content.archived", actorKind: "guardian",
      actorRef: input.context.guardianId, target: content[0]?.publicRef });
    return { archived: true, content: content[0]! };
  });
}

export async function upsertFamilyContentAssignment(input: {
  context: GuardianSessionContext; familyId: string; contentId: string; childProfileId: unknown;
  status: unknown; progressPercent?: unknown; durationSeconds?: unknown; mutationRef: unknown; baseVersion?: unknown;
}) {
  const childProfileId = safeText(input.childProfileId, "invalid_child_profile", 80);
  const mutationRef = normalizeMutationReference(input.mutationRef);
  if (!["assigned", "in_progress", "completed", "removed"].includes(String(input.status))) throw new FamilyCloudError("invalid_content_assignment_status");
  const progressPercent = Number(input.progressPercent ?? 0);
  const durationSeconds = Number(input.durationSeconds ?? 0);
  if (!Number.isInteger(progressPercent) || progressPercent < 0 || progressPercent > 100 ||
      !Number.isInteger(durationSeconds) || durationSeconds < 0 || durationSeconds > 31_536_000) {
    throw new FamilyCloudError("invalid_content_assignment_progress");
  }
  const baseVersion = input.baseVersion === undefined ? undefined : Number(input.baseVersion);
  if (baseVersion !== undefined && (!Number.isInteger(baseVersion) || baseVersion < 1)) {
    throw new FamilyCloudError("invalid_content_assignment_version");
  }
  const payloadHash = sha256(JSON.stringify({ contentId: input.contentId, childProfileId,
    status: input.status, progressPercent, durationSeconds, baseVersion: baseVersion ?? null }));
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    await guardianMembership(tx, input.context, input.familyId);
    await tx`select pg_advisory_xact_lock(hashtextextended(${`${input.familyId}:${input.contentId}:${childProfileId}`}, 0))`;
    const scope = await tx<{ id: string }[]>`select c.id from platform_family_content_items c
      join platform_child_profiles p on p.family_id = c.family_id
      where c.id = ${input.contentId} and c.family_id = ${input.familyId} and c.availability <> 'archived'
        and p.id = ${childProfileId} and p.status = 'active'`;
    if (!scope[0]) throw new FamilyCloudError("content_assignment_scope_mismatch");
    const current = await tx<{ id: string; version: number }[]>`
      select id, version from platform_family_content_assignments
      where family_id = ${input.familyId} and content_item_id = ${input.contentId}
        and child_profile_id = ${childProfileId} for update
    `;
    if (current[0] && baseVersion !== undefined && current[0].version !== baseVersion) throw new FamilyCloudError("stale_content_assignment_version");
    const targetId = current[0]?.id ?? randomUUID();
    const receipt = await contentMutation(tx, { familyId: input.familyId, mutationRef, payloadHash,
      operation: "assignment_upsert", targetId });
    if (receipt === "duplicate") return { status: "duplicate", assignmentId: targetId };
    await tx`insert into platform_family_content_assignments (
      id, family_id, content_item_id, child_profile_id, status, progress_percent, duration_seconds, assigned_by_guardian_id
    ) values (${targetId}, ${input.familyId}, ${input.contentId}, ${childProfileId}, ${String(input.status)},
      ${progressPercent}, ${durationSeconds}, ${input.context.guardianId})
      on conflict (content_item_id, child_profile_id) do update set status = excluded.status,
        progress_percent = excluded.progress_percent, duration_seconds = excluded.duration_seconds,
        version = platform_family_content_assignments.version + 1, updated_at = now()`;
    return { status: current[0] ? "updated" : "created", assignmentId: targetId };
  });
}

export async function loadGuardianLearningActivitySummary(input: {
  context: GuardianSessionContext;
  familyId: string;
  childProfileId: string;
  windowDays?: number;
  localDate?: string;
  timeZone?: string;
}) {
  const sql = platformDatabase();
  await sql.begin(async (tx) => {
    await guardianMembership(tx, input.context, input.familyId);
    const child = await tx<{ id: string }[]>`select id from platform_child_profiles
      where id = ${input.childProfileId} and family_id = ${input.familyId} and status = 'active'`;
    if (!child[0]) throw new FamilyCloudError("child_profile_not_found");
  });
  const windowDays = input.windowDays ?? FAMILY_ACTIVITY_SUMMARY_DAYS;
  const timeZone = input.timeZone ?? "UTC";
  const timeFilter = input.localDate
    ? sql`and (occurred_at at time zone ${timeZone})::date = ${input.localDate}::date`
    : sql`and occurred_at >= now() - (${windowDays} * interval '1 day')`;
  const [summary, recent, screenTimeDaily, screenTimeAppDailyRows] = await Promise.all([
    activitySummaries(
      sql,
      input.familyId,
      input.childProfileId,
      windowDays,
      input.localDate,
      timeZone,
    ),
    sql<any[]>`select id as "eventId", kind, occurred_at::text as "occurredAt",
      duration_seconds as "durationSeconds", progress_percent as "progressPercent",
      display_name as "displayName", resource_ref as "resourceRef"
      from platform_family_activity_events where family_id = ${input.familyId}
        and child_profile_id = ${input.childProfileId}
        ${timeFilter}
        order by occurred_at desc limit 50`,
    sql<Array<{ date: string; durationSeconds: number; eventCount: number }>>`
      select (occurred_at at time zone ${timeZone})::date::text as date,
        coalesce(sum(duration_seconds), 0)::int as "durationSeconds",
        count(*)::int as "eventCount"
      from platform_family_activity_events
      where family_id = ${input.familyId}
        and child_profile_id = ${input.childProfileId}
        and kind = 'screen_time'
        ${timeFilter}
      group by 1 order by 1 desc limit 90`,
    sql<Array<{ date: string; resourceRef: string; durationSeconds: number; eventCount: number }>>`
      select (occurred_at at time zone ${timeZone})::date::text as date,
        resource_ref as "resourceRef",
        coalesce(sum(duration_seconds), 0)::int as "durationSeconds",
        count(*)::int as "eventCount"
      from platform_family_activity_events
      where family_id = ${input.familyId}
        and child_profile_id = ${input.childProfileId}
        and kind = 'screen_time'
        ${timeFilter}
        and resource_ref ~ '^authority:[a-z0-9_]+:app:[a-f0-9]{32}$'
      group by 1, 2 order by 1 desc, 2 limit 200`,
  ]);
  return {
    windowDays,
    summary,
    recent,
    screenTimeDaily,
    screenTimeAppDaily: normalizeScreenTimeAppDailyRows(screenTimeAppDailyRows),
  };
}

export async function loadChildLearningActivitySummary(context: ChildDeviceSessionContext) {
  const sql = platformDatabase();
  await sql.begin((tx) => childDeviceMembership(tx, context));
  return { windowDays: FAMILY_ACTIVITY_SUMMARY_DAYS,
    summary: await activitySummaries(sql, context.familyId, context.childProfileId) };
}

import { randomBytes } from "node:crypto";
import type { TransactionSql } from "postgres";
import { sha256, type VerifiedAppleIdentity } from "../../auth/apple-identity.js";
import { platformDatabase } from "../../database/postgres.js";
import {
  FamilyCloudError,
  type ChildDeviceSessionContext,
  type FamilyCloudExport,
  type FamilyConsole,
  type FamilyExchangePolicyPayload,
  type FamilyCloudSnapshot,
  type FamilyGrowthPointMutationResult,
  type FamilyScreenTimeCatalogPayload,
  type FamilyTaskCloudRecord,
  type FamilyTaskSyncPage,
  type FamilyScreenTimePolicyPayload,
  type FamilyScreenTimeSelectionPayload,
  type FamilyScreenTimeEmergencyPayload,
  type FamilyScreenTimeStatusPayload,
  type GuardianSessionContext,
} from "./cloud-types.js";
import { normalizeGrowthPointMutation, shouldAwardTaskGrowthPoints } from "./family-growth-points.js";
import {
  FAMILY_EXPORT_VERSION,
  requireFamilyDeletionConfirmation,
} from "./family-lifecycle.js";
import {
  canWithdrawChildTask,
  FAMILY_TASK_SYNC_PAGE_LIMIT,
  normalizeMutationRef,
  parseFamilyTaskCursor,
  resolveGuardianTaskStatus,
} from "./family-task-sync.js";
import { buildFamilyConsole, classifyFamilyTaskDelivery } from "./family-task-delivery.js";
import {
  applyChildScreenTimeEmergencyAction,
  applyGuardianScreenTimeEmergencyAction,
  assertScreenTimeEmergencyScope,
  normalizeStoredScreenTimeEmergency,
} from "./screen-time-emergency.js";
import {
  applyGuardianScreenTimeControl,
  screenTimePolicyCanApplyOnDevice,
} from "./screen-time-control.js";
import {
  normalizeChildPushRegistration,
  sendScreenTimeWakePushes,
  type ChildPushEnvironment,
} from "./screen-time-push.js";
import { resolveUniqueActiveGuardianFamily } from "./family-control.js";
import {
  guardianForAccountInTransaction,
  linkAccountToGuardianInTransaction,
} from "./guardian-identity.js";
import {
  CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION,
  requireCurrentChildDeviceProtocol,
} from "./child-device-protocol.js";

const SESSION_SECONDS = 14 * 24 * 60 * 60;
const INVITE_SECONDS = 10 * 60;
export const FAMILY_SYNC_CONSENT_VERSION = "2026-07-family-sync-v1";

function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

function publicRef(prefix: string): string {
  return `${prefix}_${randomBytes(12).toString("hex")}`;
}

function safeText(value: unknown, code: string, max: number): string {
  if (typeof value !== "string") throw new FamilyCloudError(code);
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > max) throw new FamilyCloudError(code);
  return trimmed;
}

function optionalText(value: unknown, code: string, max: number): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return safeText(value, code, max);
}

function boundedInteger(value: unknown, fallback: number, minimum: number, maximum: number): number {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.trunc(number)));
}

function normalizeExchangePolicy(value: unknown): FamilyExchangePolicyPayload {
  const raw = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : {};
  const allowanceCycle = ["monthly", "weekly", "daily"].includes(String(raw.allowanceCycle))
    ? raw.allowanceCycle as FamilyExchangePolicyPayload["allowanceCycle"] : "monthly";
  const screenRate = ["one_point_per_minute", "two_points_per_minute", "one_point_per_two_minutes"]
    .includes(String(raw.screenRate))
    ? raw.screenRate as FamilyExchangePolicyPayload["screenRate"] : "one_point_per_minute";
  const customPoints = raw.customScreenPointsPer15Minutes === undefined || raw.customScreenPointsPer15Minutes === null
    ? undefined : boundedInteger(raw.customScreenPointsPer15Minutes, 1, 1, 100_000);
  const customMinutes = raw.customScreenExchangeMinutes === undefined || raw.customScreenExchangeMinutes === null
    ? undefined : boundedInteger(raw.customScreenExchangeMinutes, 15, 1, 720);
  const cap = raw.monthlyPocketMoneyCap === undefined || raw.monthlyPocketMoneyCap === null
    ? undefined : boundedInteger(raw.monthlyPocketMoneyCap, 0, 0, 1_000_000);
  return {
    allowanceCycle,
    baseMonthlyAllowance: boundedInteger(raw.baseMonthlyAllowance, 0, 0, 100_000),
    allowanceDayOfMonth: boundedInteger(raw.allowanceDayOfMonth, 1, 1, 28),
    screenRate,
    ...(customPoints === undefined ? {} : { customScreenPointsPer15Minutes: customPoints }),
    ...(customMinutes === undefined ? {} : { customScreenExchangeMinutes: customMinutes }),
    pointsPerCurrencyUnit: boundedInteger(raw.pointsPerCurrencyUnit, 10, 1, 100_000),
    pocketMoneyRequiresApproval: raw.pocketMoneyRequiresApproval !== false,
    ...(cap === undefined || cap <= 0 ? {} : { monthlyPocketMoneyCap: cap }),
    currencySymbol: raw.currencySymbol === "$" ? "$" : "¥",
  };
}

export function normalizeScreenTimeSelection(value: unknown): FamilyScreenTimeSelectionPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_policy");
  }
  const raw = value as Record<string, unknown>;
  if (raw.schemaVersion !== 3) {
    throw new FamilyCloudError("unsupported_screen_time_policy_schema");
  }
  const selectionData = safeText(raw.selectionData, "invalid_screen_time_selection", 250_000);
  if (selectionData.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(selectionData)) {
    throw new FamilyCloudError("invalid_screen_time_selection");
  }
  const selectionHash = safeText(raw.selectionHash, "invalid_screen_time_selection_hash", 64);
  if (!/^[a-f0-9]{64}$/.test(selectionHash) || selectionHash !== sha256(selectionData)) {
    throw new FamilyCloudError("invalid_screen_time_selection_hash");
  }
  const selection = {
    schemaVersion: 3,
    selectionData,
    selectionHash,
    applicationCount: boundedInteger(raw.applicationCount, 0, 0, 500),
    categoryCount: boundedInteger(raw.categoryCount, 0, 0, 100),
    webDomainCount: boundedInteger(raw.webDomainCount, 0, 0, 500),
  } satisfies FamilyScreenTimeSelectionPayload;
  if (selection.applicationCount + selection.categoryCount + selection.webDomainCount === 0) {
    throw new FamilyCloudError("empty_screen_time_selection");
  }
  return selection;
}

type FamilyScreenTimeCatalogUpload = Omit<
  FamilyScreenTimeCatalogPayload,
  "revision" | "sourceDevicePublicRef"
>;

export function normalizeScreenTimeCatalogUpload(value: unknown): FamilyScreenTimeCatalogUpload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_catalog");
  }
  const raw = value as Record<string, unknown>;
  if (raw.schemaVersion !== 1) {
    throw new FamilyCloudError("unsupported_screen_time_catalog_schema");
  }
  const selectionData = safeText(raw.selectionData, "invalid_screen_time_selection", 250_000);
  if (selectionData.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(selectionData)) {
    throw new FamilyCloudError("invalid_screen_time_selection");
  }
  const selectionHash = safeText(raw.selectionHash, "invalid_screen_time_selection_hash", 64);
  if (!/^[a-f0-9]{64}$/.test(selectionHash) || selectionHash !== sha256(selectionData)) {
    throw new FamilyCloudError("invalid_screen_time_selection_hash");
  }
  const capturedAt = validScreenTimeTimestamp(raw.capturedAt);
  if (!capturedAt) throw new FamilyCloudError("invalid_screen_time_catalog_timestamp");
  const catalog = {
    schemaVersion: 1,
    selectionData,
    selectionHash,
    applicationCount: boundedInteger(raw.applicationCount, 0, 0, 500),
    categoryCount: boundedInteger(raw.categoryCount, 0, 0, 100),
    webDomainCount: boundedInteger(raw.webDomainCount, 0, 0, 500),
    capturedAt,
  } satisfies FamilyScreenTimeCatalogUpload;
  if (catalog.applicationCount + catalog.categoryCount + catalog.webDomainCount === 0) {
    throw new FamilyCloudError("empty_screen_time_catalog");
  }
  return catalog;
}

export function normalizeStoredScreenTimeCatalog(value: unknown): FamilyScreenTimeCatalogPayload {
  const upload = normalizeScreenTimeCatalogUpload(value);
  const raw = value as Record<string, unknown>;
  return {
    ...upload,
    revision: boundedInteger(raw.revision, 1, 1, 2_147_483_647),
    sourceDevicePublicRef: safeText(
      raw.sourceDevicePublicRef,
      "invalid_screen_time_catalog_device",
      160,
    ),
  };
}

function normalizeScreenTimeCatalogBinding(
  value: unknown,
): FamilyScreenTimePolicyPayload["catalogBinding"] {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_catalog_binding");
  }
  const raw = value as Record<string, unknown>;
  const selectionHash = safeText(raw.selectionHash, "invalid_screen_time_catalog_binding", 64);
  if (!/^[a-f0-9]{64}$/.test(selectionHash)) {
    throw new FamilyCloudError("invalid_screen_time_catalog_binding");
  }
  return {
    revision: boundedInteger(raw.revision, 1, 1, 2_147_483_647),
    selectionHash,
  };
}

function normalizeScreenTimeStateForDevice(input: {
  catalog: unknown;
  policy: unknown;
  devicePublicRef: string;
}): {
  catalog?: FamilyScreenTimeCatalogPayload;
  policy?: FamilyScreenTimePolicyPayload;
} {
  const catalog = input.catalog === undefined || input.catalog === null
    ? undefined
    : normalizeStoredScreenTimeCatalog(input.catalog);
  const policy = input.policy === undefined || input.policy === null
    ? undefined
    : normalizeStoredScreenTimePolicy(input.policy);
  return {
    catalog,
    policy: policy !== undefined && screenTimePolicyCanApplyOnDevice(
      policy,
      catalog,
      input.devicePublicRef,
    )
      ? policy
      : undefined,
  };
}

export function normalizeScreenTimePolicy(value: unknown): FamilyScreenTimePolicyPayload {
  const raw = value as Record<string, unknown>;
  const selection = normalizeScreenTimeSelection(value);
  const updatedAt = new Date().toISOString();
  const revision = boundedInteger(raw.revision, 1, 1, 2_147_483_647);
  return {
    ...selection,
    revision,
    ...(normalizeScreenTimeCatalogBinding(raw.catalogBinding) === undefined
      ? {}
      : { catalogBinding: normalizeScreenTimeCatalogBinding(raw.catalogBinding) }),
    control: {
      schemaVersion: 1,
      commandId: `policy:${revision}:${selection.selectionHash.slice(0, 16)}`,
      mode: "locked",
      issuedAt: updatedAt,
    },
    updatedAt,
  } satisfies FamilyScreenTimePolicyPayload;
}

export function normalizeStoredScreenTimePolicy(value: unknown): FamilyScreenTimePolicyPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_policy");
  }
  const raw = value as Record<string, unknown>;
  if (raw.schemaVersion !== 1 && raw.schemaVersion !== 3) {
    throw new FamilyCloudError("unsupported_screen_time_policy_schema");
  }
  const selectionData = safeText(raw.selectionData, "invalid_screen_time_selection", 250_000);
  if (selectionData.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(selectionData)) {
    throw new FamilyCloudError("invalid_screen_time_selection");
  }
  const expectedHash = sha256(selectionData);
  const selectionHash = raw.schemaVersion === 1
    ? expectedHash
    : safeText(raw.selectionHash, "invalid_screen_time_selection_hash", 64);
  if (!/^[a-f0-9]{64}$/.test(selectionHash) || selectionHash !== expectedHash) {
    throw new FamilyCloudError("invalid_screen_time_selection_hash");
  }
  const revision = boundedInteger(raw.revision, 1, 1, 2_147_483_647);
  const updatedAt = validScreenTimeTimestamp(raw.updatedAt) ?? new Date().toISOString();
  const applicationCount = boundedInteger(raw.applicationCount, 0, 0, 500);
  const categoryCount = boundedInteger(raw.categoryCount, 0, 0, 100);
  const webDomainCount = boundedInteger(raw.webDomainCount, 0, 0, 500);
  if (applicationCount + categoryCount + webDomainCount === 0) {
    throw new FamilyCloudError("empty_screen_time_selection");
  }
  return {
    schemaVersion: 3,
    revision,
    selectionData,
    selectionHash,
    applicationCount,
    categoryCount,
    webDomainCount,
    ...(normalizeScreenTimeCatalogBinding(raw.catalogBinding) === undefined
      ? {}
      : { catalogBinding: normalizeScreenTimeCatalogBinding(raw.catalogBinding) }),
    control: normalizeStoredScreenTimeControl(raw.control, revision, selectionHash, updatedAt),
    updatedAt,
  };
}

function normalizeStoredScreenTimeControl(
  value: unknown,
  revision: number,
  selectionHash: string,
  fallbackIssuedAt: string,
): NonNullable<FamilyScreenTimePolicyPayload["control"]> {
  if (value === undefined || value === null) {
    return {
      schemaVersion: 1,
      commandId: `policy:${revision}:${selectionHash.slice(0, 16)}`,
      mode: "locked",
      issuedAt: fallbackIssuedAt,
    };
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_control");
  }
  const raw = value as Record<string, unknown>;
  if (raw.schemaVersion !== 1 || (raw.mode !== "locked" && raw.mode !== "unlocked")) {
    throw new FamilyCloudError("invalid_screen_time_control");
  }
  const commandId = safeText(raw.commandId, "invalid_screen_time_control_command", 160);
  const issuedAt = validScreenTimeTimestamp(raw.issuedAt);
  if (!issuedAt) throw new FamilyCloudError("invalid_screen_time_control_timestamp");
  if (raw.mode === "locked") {
    return { schemaVersion: 1, commandId, mode: "locked", issuedAt };
  }
  const unlockUntil = validScreenTimeTimestamp(raw.unlockUntil);
  if (!unlockUntil) throw new FamilyCloudError("invalid_screen_time_control_timestamp");
  return { schemaVersion: 1, commandId, mode: "unlocked", issuedAt, unlockUntil };
}

function validScreenTimeTimestamp(value: unknown): string | undefined {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) return undefined;
  return new Date(value).toISOString();
}

export function normalizeScreenTimeStatus(value: unknown): FamilyScreenTimeStatusPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_status");
  }
  const raw = value as Record<string, unknown>;
  const authorizations = ["not_requested", "approved", "denied", "unavailable", "error"] as const;
  const enforcements = ["waiting_for_authorization", "waiting_for_policy", "ready", "applied", "error"] as const;
  if (!authorizations.includes(raw.authorization as typeof authorizations[number]) ||
      !enforcements.includes(raw.enforcement as typeof enforcements[number])) {
    throw new FamilyCloudError("invalid_screen_time_status");
  }
  const revision = raw.appliedPolicyRevision === undefined || raw.appliedPolicyRevision === null
    ? undefined : boundedInteger(raw.appliedPolicyRevision, 1, 1, 2_147_483_647);
  if (raw.enforcement === "applied" && raw.authorization !== "approved") {
    throw new FamilyCloudError("invalid_screen_time_status");
  }
  const errorCode = optionalText(raw.lastErrorCode, "invalid_screen_time_error", 120);
  const appliedSelectionHash = optionalText(
    raw.appliedSelectionHash,
    "invalid_screen_time_selection_hash",
    64,
  );
  if (appliedSelectionHash !== undefined && !/^[a-f0-9]{64}$/.test(appliedSelectionHash)) {
    throw new FamilyCloudError("invalid_screen_time_selection_hash");
  }
  const appliedControlCommandId = optionalText(
    raw.appliedControlCommandId,
    "invalid_screen_time_control_command",
    160,
  );
  const controlMode = raw.controlMode === undefined || raw.controlMode === null
    ? undefined : raw.controlMode;
  if (controlMode !== undefined && controlMode !== "locked" && controlMode !== "unlocked") {
    throw new FamilyCloudError("invalid_screen_time_control_mode");
  }
  const unlockedUntil = optionalText(raw.unlockedUntil, "invalid_screen_time_control_timestamp", 64);
  if (unlockedUntil !== undefined && !Number.isFinite(Date.parse(unlockedUntil))) {
    throw new FamilyCloudError("invalid_screen_time_control_timestamp");
  }
  if (controlMode === "unlocked" && unlockedUntil === undefined) {
    throw new FamilyCloudError("invalid_screen_time_control_timestamp");
  }
  if (raw.enforcement === "applied" &&
      (revision === undefined || appliedSelectionHash === undefined ||
       appliedControlCommandId === undefined || controlMode === undefined)) {
    throw new FamilyCloudError("incomplete_screen_time_applied_receipt");
  }
  const applicationCount = boundedInteger(raw.applicationCount, 0, 0, 500);
  const categoryCount = boundedInteger(raw.categoryCount, 0, 0, 100);
  const webDomainCount = boundedInteger(raw.webDomainCount, 0, 0, 500);
  return {
    authorization: raw.authorization as FamilyScreenTimeStatusPayload["authorization"],
    enforcement: raw.enforcement as FamilyScreenTimeStatusPayload["enforcement"],
    ...(revision === undefined ? {} : { appliedPolicyRevision: revision }),
    ...(appliedSelectionHash === undefined ? {} : { appliedSelectionHash }),
    ...(appliedControlCommandId === undefined ? {} : { appliedControlCommandId }),
    ...(controlMode === undefined ? {} : { controlMode }),
    ...(unlockedUntil === undefined ? {} : { unlockedUntil }),
    ...(errorCode === undefined ? {} : { lastErrorCode: errorCode }),
    applicationCount,
    categoryCount,
    webDomainCount,
    updatedAt: new Date().toISOString(),
  };
}

function stableJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right));
    return `{${entries.map(([key, entry]) => `${JSON.stringify(key)}:${stableJSON(entry)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function validDeviceRef(value: string): string {
  const ref = safeText(value, "invalid_device_ref", 160);
  if (!/^[A-Za-z0-9:_-]{8,160}$/.test(ref)) throw new FamilyCloudError("invalid_device_ref");
  return ref;
}

export async function issueAppleAuthNonce(devicePublicRef: string): Promise<{ nonce: string; expiresAt: string }> {
  const sql = platformDatabase();
  const deviceHash = sha256(validDeviceRef(devicePublicRef));
  const recent = await sql<{ count: number }[]>`
    select count(*)::int as count from platform_auth_nonces
    where device_ref_hash = ${deviceHash} and created_at > now() - interval '1 minute'
  `;
  if ((recent[0]?.count ?? 0) >= 5) throw new FamilyCloudError("nonce_rate_limited");
  const nonce = randomToken();
  const rows = await sql<{ expiresAt: string }[]>`
    insert into platform_auth_nonces (nonce_hash, device_ref_hash, expires_at)
    values (${sha256(nonce)}, ${deviceHash}, now() + interval '5 minutes')
    returning expires_at::text as "expiresAt"
  `;
  return { nonce, expiresAt: rows[0]?.expiresAt ?? new Date(Date.now() + 300_000).toISOString() };
}

export async function createGuardianSession(input: {
  identity: VerifiedAppleIdentity;
  rawNonce: string;
  devicePublicRef: string;
  deviceName: string;
  displayName?: string;
}): Promise<{
  sessionToken: string;
  expiresAt: string;
  guardian: { id: string; displayName?: string };
  family?: FamilyCloudSnapshot;
}> {
  const sql = platformDatabase();
  const nonceHash = sha256(safeText(input.rawNonce, "invalid_nonce", 512));
  const deviceRef = validDeviceRef(input.devicePublicRef);
  const deviceName = safeText(input.deviceName, "invalid_device_name", 120);
  const displayName = optionalText(input.displayName, "invalid_display_name", 120);
  const token = randomToken(48);

  const created = await sql.begin(async (tx) => {
    const consumed = await tx<{ id: string }[]>`
      update platform_auth_nonces
      set status = 'consumed', consumed_at = now()
      where nonce_hash = ${nonceHash} and status = 'issued' and expires_at > now()
      returning id
    `;
    if (!consumed[0]) throw new FamilyCloudError("nonce_invalid_or_consumed");

    const guardians = await tx<{ id: string; displayName?: string; accountId?: string }[]>`
      insert into platform_guardian_accounts (external_subject, display_name)
      values (${input.identity.subject}, ${displayName ?? null})
      on conflict (external_subject) do update set
        display_name = coalesce(platform_guardian_accounts.display_name, excluded.display_name),
        updated_at = now()
      returning id, display_name as "displayName", account_id as "accountId"
    `;
    const guardian = guardians[0];
    if (!guardian) throw new FamilyCloudError("guardian_session_create_failed");
    const linkedIdentities = await tx<{ accountId: string; accountStatus: string }[]>`
      select i.account_id as "accountId", a.status as "accountStatus"
      from platform_account_identities i
      join platform_accounts a on a.id = i.account_id
      where i.provider = 'apple'
        and i.provider_subject = ${input.identity.subject}
        and i.status = 'active'
      for update of i, a
    `;
    const linkedIdentity = linkedIdentities[0];
    if (linkedIdentity) {
      if (linkedIdentity.accountStatus !== 'active') {
        throw new FamilyCloudError("guardian_account_inactive");
      }
      await linkAccountToGuardianInTransaction(tx, {
        accountId: linkedIdentity.accountId,
        targetGuardianId: guardian.id,
      });
      await tx`
        update platform_account_identities
        set last_used_at = now()
        where provider = 'apple'
          and provider_subject = ${input.identity.subject}
          and account_id = ${linkedIdentity.accountId}
      `;
    }
    const sessions = await tx<{ expiresAt: string }[]>`
      insert into platform_guardian_sessions (
        guardian_id, token_hash, device_public_ref, device_name, expires_at
      ) values (
        ${guardian.id}, ${sha256(token)}, ${deviceRef}, ${deviceName}, now() + (${SESSION_SECONDS} * interval '1 second')
      ) returning expires_at::text as "expiresAt"
    `;
    return { guardian, expiresAt: sessions[0]?.expiresAt ?? new Date(Date.now() + SESSION_SECONDS * 1_000).toISOString() };
  });

  const context = await authenticateGuardianToken(token);
  const family = context ? await loadCurrentFamily(context) : undefined;
  return { sessionToken: token, expiresAt: created.expiresAt, guardian: created.guardian, ...(family ? { family } : {}) };
}

export async function createGuardianSessionForAccountInTransaction(
  tx: TransactionSql,
  input: {
    accountId: string;
    devicePublicRef: string;
    deviceName: string;
    consentVersion: string;
    familySyncAccepted: boolean;
    childTaskSyncAccepted: boolean;
  },
): Promise<{
  sessionToken: string;
  expiresAt: string;
  guardian: { id: string; displayName?: string };
}> {
  const deviceRef = validDeviceRef(input.devicePublicRef);
  const deviceName = safeText(input.deviceName, "invalid_device_name", 120);
  if (input.consentVersion !== FAMILY_SYNC_CONSENT_VERSION ||
      !input.familySyncAccepted || !input.childTaskSyncAccepted) {
    throw new FamilyCloudError("guardian_consent_required");
  }
  const accounts = await tx<{ id: string; displayName: string }[]>`
    select id, display_name as "displayName" from platform_accounts
    where id = ${input.accountId} and status = 'active' for update
  `;
  const account = accounts[0];
  if (!account) throw new FamilyCloudError("guardian_account_inactive");

  const guardian = await guardianForAccountInTransaction(tx, {
    accountId: account.id,
    displayName: account.displayName,
  });

  await tx`
    insert into platform_guardian_consents (
      guardian_id, consent_version, family_sync_accepted, child_task_sync_accepted
    ) values (
      ${guardian.id}, ${input.consentVersion}, true, true
    ) on conflict (guardian_id, consent_version) do update set
      family_sync_accepted = true,
      child_task_sync_accepted = true,
      accepted_at = now(),
      revoked_at = null
  `;
  const token = randomToken(48);
  const sessions = await tx<{ expiresAt: string }[]>`
    insert into platform_guardian_sessions (
      guardian_id, token_hash, device_public_ref, device_name, expires_at
    ) values (
      ${guardian.id}, ${sha256(token)}, ${deviceRef}, ${deviceName},
      now() + (${SESSION_SECONDS} * interval '1 second')
    ) returning expires_at::text as "expiresAt"
  `;
  return {
    sessionToken: token,
    expiresAt: sessions[0]?.expiresAt ?? new Date(Date.now() + SESSION_SECONDS * 1_000).toISOString(),
    guardian,
  };
}

export async function authenticateGuardianToken(token: string | undefined): Promise<GuardianSessionContext | undefined> {
  if (!token || token.length > 512) return undefined;
  const sql = platformDatabase();
  const rows = await sql<GuardianSessionContext[]>`
    update platform_guardian_sessions s
    set last_seen_at = now()
    from platform_guardian_accounts g
    where s.token_hash = ${sha256(token)}
      and s.guardian_id = g.id
      and s.revoked_at is null
      and s.expires_at > now()
      and g.status = 'active'
    returning s.id as "sessionId", g.id as "guardianId", g.display_name as "displayName", s.device_public_ref as "devicePublicRef"
  `;
  return rows[0];
}

export async function authenticateChildDeviceToken(token: string | undefined): Promise<ChildDeviceSessionContext | undefined> {
  if (!token || token.length > 512) return undefined;
  const sql = platformDatabase();
  const rows = await sql<ChildDeviceSessionContext[]>`
    update platform_family_devices
    set last_seen_at = now()
    where session_token_hash = ${sha256(token)} and role = 'child' and status = 'active'
    returning id as "deviceId", family_id as "familyId", child_profile_id as "childProfileId",
      public_ref as "devicePublicRef", protocol_generation as "protocolGeneration"
  `;
  return rows[0];
}

export async function registerChildDevicePush(input: {
  context: ChildDeviceSessionContext;
  registration: unknown;
}): Promise<FamilyCloudSnapshot["children"][number] & {
  family: { id: string; publicRef: string; displayName: string };
}> {
  const registration = normalizeChildPushRegistration(input.registration);
  const sql = platformDatabase();
  await sql.begin(async (tx) => {
    await tx`
      update platform_family_devices
      set push_token = null, push_environment = null, push_token_updated_at = null
      where push_token = ${registration.token}
        and id <> ${input.context.deviceId}
    `;
    const rows = await tx<{ id: string }[]>`
      update platform_family_devices
      set push_token = ${registration.token},
          push_environment = ${registration.environment},
          push_token_updated_at = now(),
          last_seen_at = now()
      where id = ${input.context.deviceId}
        and family_id = ${input.context.familyId}
        and child_profile_id = ${input.context.childProfileId}
        and role = 'child'
        and status = 'active'
      returning id
    `;
    if (!rows[0]) throw new FamilyCloudError("child_device_not_found");
  });
  return loadChildDeviceProfile(input.context);
}

export async function revokeGuardianSession(context: GuardianSessionContext): Promise<void> {
  const sql = platformDatabase();
  await sql`update platform_guardian_sessions set revoked_at = now() where id = ${context.sessionId}`;
}

async function membership(context: GuardianSessionContext, familyId?: string): Promise<{ familyId: string; isCreator: boolean }> {
  const sql = platformDatabase();
  const rows = await sql<{ familyId: string; isCreator: boolean }[]>`
    select m.family_id as "familyId", m.is_creator as "isCreator"
    from platform_family_guardians m
    join platform_families f on f.id = m.family_id
    where m.guardian_id = ${context.guardianId}
      and m.status = 'active'
      and f.status = 'active'
    order by m.is_creator desc, m.joined_at nulls last
    limit 2
  `;
  return resolveUniqueActiveGuardianFamily(rows, familyId);
}

async function assertGuardianFamilyUniqueness(
  tx: TransactionSql,
  guardianId: string,
  targetFamilyId?: string,
): Promise<void> {
  const rows = await tx<{ familyId: string }[]>`
    select m.family_id as "familyId"
    from platform_family_guardians m
    join platform_families f on f.id = m.family_id and f.status = 'active'
    where m.guardian_id = ${guardianId} and m.status = 'active'
    order by m.created_at
    limit 2
  `;
  if (rows.length > 1) throw new FamilyCloudError("guardian_multiple_active_families");
  if (rows[0] && rows[0].familyId !== targetFamilyId) {
    throw new FamilyCloudError("guardian_family_conflict");
  }
}

async function assertChildClientRefUniqueness(
  tx: TransactionSql,
  clientRefs: string[],
  targetFamilyId?: string,
  excludedChildId?: string,
): Promise<void> {
  if (clientRefs.length === 0) return;
  const rows = await tx<{ clientRef: string; familyId: string }[]>`
    select c.client_ref as "clientRef", c.family_id as "familyId"
    from platform_child_profiles c
    join platform_families f on f.id = c.family_id and f.status = 'active'
    where c.status = 'active' and c.client_ref in ${tx(clientRefs)}
      ${excludedChildId ? tx`and c.id <> ${excludedChildId}` : tx``}
      ${targetFamilyId ? tx`and c.family_id <> ${targetFamilyId}` : tx``}
    limit 1
  `;
  if (rows[0]) throw new FamilyCloudError("child_client_ref_family_conflict");
}

async function assertUniqueActiveChildDisplayName(
  tx: TransactionSql,
  familyId: string,
  displayName: string,
  excludedChildId?: string,
): Promise<void> {
  const rows = await tx<{ id: string }[]>`
    select id from platform_child_profiles
    where family_id = ${familyId} and status = 'active'
      and lower(btrim(display_name)) = lower(btrim(${displayName}))
      ${excludedChildId ? tx`and id <> ${excludedChildId}` : tx``}
    limit 1
  `;
  if (rows[0]) throw new FamilyCloudError("duplicate_child_name");
}

async function familySnapshot(familyId: string, guardianId: string): Promise<FamilyCloudSnapshot> {
  const sql = platformDatabase();
  const families = await sql<FamilyCloudSnapshot["family"][]>`
    select f.id, f.public_ref as "publicRef", f.display_name as "displayName", m.is_creator as "isCreator"
    from platform_families f
    join platform_family_guardians m on m.family_id = f.id
    where f.id = ${familyId} and m.guardian_id = ${guardianId} and m.status = 'active'
  `;
  const family = families[0];
  if (!family) throw new FamilyCloudError("family_access_denied");
  const [guardians, children, devices] = await Promise.all([
    sql<FamilyCloudSnapshot["guardians"]>`
      select g.id, coalesce(g.display_name, 'Guardian') as "displayName", m.is_creator as "isCreator", m.joined_at::text as "joinedAt"
      from platform_family_guardians m join platform_guardian_accounts g on g.id = m.guardian_id
      where m.family_id = ${familyId} and m.status = 'active' order by m.is_creator desc, m.joined_at
    `,
    sql<FamilyCloudSnapshot["children"]>`
      select id, public_ref as "publicRef", client_ref as "clientRef", display_name as "displayName", birth_year as "birthYear",
        pre_reader_mode as "preReaderMode", interface_language as "interfaceLanguage",
        content_language as "contentLanguage", daily_limit_minutes as "dailyLimitMinutes",
        exchange_policy as "exchangePolicy", screen_time_catalog as "screenTimeCatalog",
        screen_time_policy as "screenTimePolicy",
        screen_time_status as "screenTimeStatus", screen_time_emergency as "screenTimeEmergency",
        growth_point_balance as "growthPointBalance",
        profile_version as "profileVersion"
      from platform_child_profiles where family_id = ${familyId} and status = 'active' order by created_at
    `,
    sql<FamilyCloudSnapshot["devices"]>`
      select id, public_ref as "publicRef", display_name as "displayName", role,
        child_profile_id as "childProfileId", status, bound_at::text as "boundAt",
        protocol_generation as "protocolGeneration",
        (role = 'child' and protocol_generation <> ${CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION}) as "requiresRebind"
      from platform_family_devices where family_id = ${familyId} order by bound_at
    `,
  ]);
  return {
    family,
    guardians,
    children: children.map((child) => ({
      ...child,
      ...(child.screenTimeCatalog === undefined || child.screenTimeCatalog === null
        ? { screenTimeCatalog: undefined }
        : { screenTimeCatalog: normalizeStoredScreenTimeCatalog(child.screenTimeCatalog) }),
      ...(child.screenTimePolicy === undefined || child.screenTimePolicy === null
        ? { screenTimePolicy: undefined }
        : { screenTimePolicy: normalizeStoredScreenTimePolicy(child.screenTimePolicy) }),
    })),
    devices,
  };
}

export async function loadCurrentFamily(context: GuardianSessionContext): Promise<FamilyCloudSnapshot | undefined> {
  try {
    const member = await membership(context);
    return familySnapshot(member.familyId, context.guardianId);
  } catch (error) {
    if (error instanceof FamilyCloudError && error.code === "family_access_denied") return undefined;
    throw error;
  }
}

export async function exportFamilyData(
  context: GuardianSessionContext,
  familyId: string,
): Promise<FamilyCloudExport> {
  const member = await membership(context, familyId);
  if (!member.isCreator) throw new FamilyCloudError("family_creator_required");
  const sql = platformDatabase();
  const [family, tasks, audit] = await Promise.all([
    familySnapshot(familyId, context.guardianId),
    listGuardianTasks(context, familyId),
    sql<FamilyCloudExport["audit"]>`
      select action, actor_kind as "actorKind", target_public_ref as "targetPublicRef",
        created_at::text as "createdAt"
      from platform_family_audit
      where family_id = ${familyId}
      order by created_at
    `,
  ]);
  return {
    exportVersion: FAMILY_EXPORT_VERSION,
    exportedAt: new Date().toISOString(),
    scope: "cloud_family_minimal_sync",
    scopeNote: "Includes cloud family membership, device bindings, minimal task state, and audit actions only. Local chats, photos, recordings, AI memory, journals, email, and school documents are not uploaded and are not included.",
    family,
    tasks,
    audit,
  };
}

export async function deleteFamilyData(input: {
  context: GuardianSessionContext;
  familyId: string;
  confirmation: unknown;
}): Promise<{ receiptId: string; deletedAt: string }> {
  const member = await membership(input.context, input.familyId);
  if (!member.isCreator) throw new FamilyCloudError("family_creator_required");
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const families = await tx<{ publicRef: string }[]>`
      select public_ref as "publicRef" from platform_families
      where id = ${input.familyId} and status = 'active'
      for update
    `;
    const family = families[0];
    if (!family) throw new FamilyCloudError("family_access_denied");
    requireFamilyDeletionConfirmation(family.publicRef, input.confirmation);

    const [guardians, counts] = await Promise.all([
      tx<{ guardianId: string }[]>`
        select guardian_id as "guardianId" from platform_family_guardians
        where family_id = ${input.familyId}
      `,
      tx<{ children: number; devices: number; tasks: number; audits: number }[]>`
        select
          (select count(*)::int from platform_child_profiles where family_id = ${input.familyId}) as children,
          (select count(*)::int from platform_family_devices where family_id = ${input.familyId}) as devices,
          (select count(*)::int from platform_family_tasks where family_id = ${input.familyId}) as tasks,
          (select count(*)::int from platform_family_audit where family_id = ${input.familyId}) as audits
      `,
    ]);
    const guardianIds = guardians.map((guardian) => guardian.guardianId);
    if (guardianIds.length > 0) {
      await tx`
        update platform_guardian_sessions set revoked_at = now()
        where guardian_id in ${tx(guardianIds)} and revoked_at is null
      `;
    }
    const receipts = await tx<{ receiptId: string; deletedAt: string }[]>`
      insert into platform_deletion_receipts (
        scope, subject_ref_hash, actor_ref_hash, deleted_counts
      ) values (
        'family', ${sha256(family.publicRef)}, ${sha256(input.context.guardianId)},
        ${tx.json({ guardians: guardianIds.length, ...(counts[0] ?? { children: 0, devices: 0, tasks: 0, audits: 0 }) })}
      )
      returning id as "receiptId", created_at::text as "deletedAt"
    `;
    await tx`delete from platform_families where id = ${input.familyId}`;
    const receipt = receipts[0];
    if (!receipt) throw new FamilyCloudError("family_delete_failed");
    return receipt;
  });
}

export async function createFamily(input: {
  context: GuardianSessionContext;
  displayName: string;
  deviceName: string;
  children: Array<{
    clientRef: string;
    displayName: string;
    birthYear?: number;
    preReaderMode?: boolean;
    interfaceLanguage?: "chinese" | "english";
    contentLanguage?: "chinese" | "english" | "bilingual";
    dailyLimitMinutes?: number;
    exchangePolicy?: unknown;
  }>;
  consentVersion: string;
  familySyncAccepted: boolean;
  childTaskSyncAccepted: boolean;
}): Promise<FamilyCloudSnapshot> {
  const sql = platformDatabase();
  if (await loadCurrentFamily(input.context)) throw new FamilyCloudError("guardian_already_in_family");
  const displayName = safeText(input.displayName, "invalid_family_name", 120);
  const deviceName = safeText(input.deviceName, "invalid_device_name", 120);
  if (input.consentVersion !== FAMILY_SYNC_CONSENT_VERSION || !input.familySyncAccepted || !input.childTaskSyncAccepted) {
    throw new FamilyCloudError("guardian_consent_required");
  }
  if (!Array.isArray(input.children) || input.children.length < 1 || input.children.length > 12) {
    throw new FamilyCloudError("invalid_children");
  }
  const children = input.children.map((child) => ({
    clientRef: safeText(child.clientRef, "invalid_child_client_ref", 120),
    displayName: safeText(child.displayName, "invalid_child_name", 80),
    birthYear: child.birthYear === undefined ? undefined : Number(child.birthYear),
    preReaderMode: child.preReaderMode === true,
    interfaceLanguage: child.interfaceLanguage === "english" ? "english" : "chinese",
    contentLanguage: ["chinese", "english", "bilingual"].includes(child.contentLanguage ?? "")
      ? child.contentLanguage! : "chinese",
    dailyLimitMinutes: boundedInteger(child.dailyLimitMinutes, 60, 15, 720),
    exchangePolicy: normalizeExchangePolicy(child.exchangePolicy),
  }));
  if (children.some((child) => child.birthYear !== undefined && (!Number.isInteger(child.birthYear) || child.birthYear! < 2000 || child.birthYear! > 2100))) {
    throw new FamilyCloudError("invalid_child_birth_year");
  }
  if (new Set(children.map((child) => child.clientRef)).size !== children.length) {
    throw new FamilyCloudError("duplicate_child_client_ref");
  }
  if (new Set(children.map((child) => child.displayName.trim().toLocaleLowerCase())).size !== children.length) {
    throw new FamilyCloudError("duplicate_child_name");
  }

  const familyId = await sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(hashtextextended(${`guardian-family:${input.context.guardianId}`}, 0))`;
    await assertGuardianFamilyUniqueness(tx, input.context.guardianId);
    for (const child of children) {
      await tx`select pg_advisory_xact_lock(hashtextextended(${`child-client-ref:${child.clientRef}`}, 0))`;
    }
    await assertChildClientRefUniqueness(tx, children.map((child) => child.clientRef));
    const familyRows = await tx<{ id: string; publicRef: string }[]>`
      insert into platform_families (public_ref, display_name, created_by_guardian_id)
      values (${publicRef("family")}, ${displayName}, ${input.context.guardianId})
      returning id, public_ref as "publicRef"
    `;
    const family = familyRows[0];
    if (!family) throw new FamilyCloudError("family_create_failed");
    await tx`
      insert into platform_family_guardians (family_id, guardian_id, is_creator, status, joined_at)
      values (${family.id}, ${input.context.guardianId}, true, 'active', now())
    `;
    await tx`
      insert into platform_guardian_consents (
        guardian_id, consent_version, family_sync_accepted, child_task_sync_accepted
      ) values (${input.context.guardianId}, ${input.consentVersion}, true, true)
      on conflict (guardian_id, consent_version) do update set
        family_sync_accepted = true, child_task_sync_accepted = true, accepted_at = now(), revoked_at = null
    `;
    await tx`
      insert into platform_family_devices (family_id, guardian_id, public_ref, display_name, role)
      values (${family.id}, ${input.context.guardianId}, ${input.context.devicePublicRef}, ${deviceName}, 'guardian')
    `;
    for (const child of children) {
      await tx`
        insert into platform_child_profiles (
          family_id, public_ref, client_ref, display_name, birth_year,
          pre_reader_mode, interface_language, content_language, daily_limit_minutes, exchange_policy
        ) values (
          ${family.id}, ${publicRef("child")}, ${child.clientRef}, ${child.displayName}, ${child.birthYear ?? null},
          ${child.preReaderMode}, ${child.interfaceLanguage}, ${child.contentLanguage},
          ${child.dailyLimitMinutes}, ${sql.json(child.exchangePolicy as any)}
        )
      `;
    }
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
      values (${family.id}, 'family.created', 'guardian', ${sha256(input.context.guardianId)}, ${family.publicRef})
    `;
    return family.id;
  });
  return familySnapshot(familyId, input.context.guardianId);
}

export async function createChildProfile(input: {
  context: GuardianSessionContext;
  familyId: string;
  clientRef: string;
  displayName: string;
  birthYear?: number;
  preReaderMode?: boolean;
  interfaceLanguage?: "chinese" | "english";
  contentLanguage?: "chinese" | "english" | "bilingual";
  dailyLimitMinutes?: number;
  exchangePolicy?: unknown;
}): Promise<FamilyCloudSnapshot> {
  await membership(input.context, input.familyId);
  const sql = platformDatabase();
  const clientRef = safeText(input.clientRef, "invalid_child_client_ref", 120);
  const displayName = safeText(input.displayName, "invalid_child_name", 80);
  if (input.birthYear !== undefined && (!Number.isInteger(input.birthYear) || input.birthYear < 2000 || input.birthYear > 2100)) {
    throw new FamilyCloudError("invalid_child_birth_year");
  }
  const interfaceLanguage = input.interfaceLanguage === "english" ? "english" : "chinese";
  const contentLanguage = ["chinese", "english", "bilingual"].includes(input.contentLanguage ?? "")
    ? input.contentLanguage! : "chinese";
  const dailyLimitMinutes = boundedInteger(input.dailyLimitMinutes, 60, 15, 720);
  const exchangePolicy = normalizeExchangePolicy(input.exchangePolicy);
  await sql.begin(async (tx) => {
    const families = await tx<{ id: string }[]>`
      select id from platform_families
      where id = ${input.familyId} and status = 'active'
      for update
    `;
    if (!families[0]) throw new FamilyCloudError("family_access_denied");
    await tx`select pg_advisory_xact_lock(hashtextextended(${`child-client-ref:${clientRef}`}, 0))`;
    const existing = await tx<{ id: string; status: string }[]>`
      select id, status from platform_child_profiles
      where family_id = ${input.familyId} and client_ref = ${clientRef}
      for update
    `;
    if (existing[0]?.status === "archived") {
      throw new FamilyCloudError("child_profile_archived");
    }
    await assertChildClientRefUniqueness(tx, [clientRef], input.familyId);
    await assertUniqueActiveChildDisplayName(tx, input.familyId, displayName, existing[0]?.id);
    await tx`
      insert into platform_child_profiles (
      family_id, public_ref, client_ref, display_name, birth_year,
      pre_reader_mode, interface_language, content_language, daily_limit_minutes, exchange_policy
    ) values (
      ${input.familyId}, ${publicRef("child")}, ${clientRef}, ${displayName}, ${input.birthYear ?? null},
      ${input.preReaderMode === true}, ${interfaceLanguage}, ${contentLanguage},
      ${dailyLimitMinutes}, ${sql.json(exchangePolicy as any)}
    )
    on conflict (family_id, client_ref) where client_ref is not null do update set
      display_name = excluded.display_name, birth_year = excluded.birth_year,
      pre_reader_mode = excluded.pre_reader_mode, interface_language = excluded.interface_language,
      content_language = excluded.content_language, daily_limit_minutes = excluded.daily_limit_minutes,
      exchange_policy = excluded.exchange_policy,
      profile_version = platform_child_profiles.profile_version + 1,
      updated_at = now()
    `;
  });
  return familySnapshot(input.familyId, input.context.guardianId);
}

export async function updateChildProfile(input: {
  context: GuardianSessionContext;
  familyId: string;
  childProfileId: string;
  baseVersion: number;
  clientRef: string;
  displayName: string;
  birthYear?: number;
  preReaderMode?: boolean;
  interfaceLanguage?: "chinese" | "english";
  contentLanguage?: "chinese" | "english" | "bilingual";
  dailyLimitMinutes?: number;
  exchangePolicy?: unknown;
}): Promise<FamilyCloudSnapshot> {
  await membership(input.context, input.familyId);
  if (!Number.isInteger(input.baseVersion) || input.baseVersion < 1) {
    throw new FamilyCloudError("invalid_child_profile_version");
  }
  const clientRef = safeText(input.clientRef, "invalid_child_client_ref", 120);
  const displayName = safeText(input.displayName, "invalid_child_name", 80);
  if (input.birthYear !== undefined && (!Number.isInteger(input.birthYear) || input.birthYear < 2000 || input.birthYear > 2100)) {
    throw new FamilyCloudError("invalid_child_birth_year");
  }
  const interfaceLanguage = input.interfaceLanguage === "english" ? "english" : "chinese";
  const contentLanguage = ["chinese", "english", "bilingual"].includes(input.contentLanguage ?? "")
    ? input.contentLanguage! : "chinese";
  const dailyLimitMinutes = boundedInteger(input.dailyLimitMinutes, 60, 15, 720);
  const exchangePolicy = normalizeExchangePolicy(input.exchangePolicy);
  const sql = platformDatabase();
  const rows = await sql.begin(async (tx) => {
    const families = await tx<{ id: string }[]>`
      select id from platform_families
      where id = ${input.familyId} and status = 'active'
      for update
    `;
    if (!families[0]) throw new FamilyCloudError("family_access_denied");
    await tx`select pg_advisory_xact_lock(hashtextextended(${`child-client-ref:${clientRef}`}, 0))`;
    await assertChildClientRefUniqueness(tx, [clientRef], input.familyId, input.childProfileId);
    await assertUniqueActiveChildDisplayName(tx, input.familyId, displayName, input.childProfileId);
    return tx<{ publicRef: string }[]>`
      update platform_child_profiles
    set client_ref = ${clientRef}, display_name = ${displayName}, birth_year = ${input.birthYear ?? null},
        pre_reader_mode = ${input.preReaderMode === true}, interface_language = ${interfaceLanguage},
        content_language = ${contentLanguage}, daily_limit_minutes = ${dailyLimitMinutes},
        exchange_policy = ${sql.json(exchangePolicy as any)},
        profile_version = profile_version + 1, updated_at = now()
    where id = ${input.childProfileId} and family_id = ${input.familyId} and status = 'active'
      and profile_version = ${input.baseVersion}
    returning public_ref as "publicRef"
    `;
  });
  if (!rows[0]) {
    const existing = await sql<{ version: number }[]>`
      select profile_version as version from platform_child_profiles
      where id = ${input.childProfileId} and family_id = ${input.familyId} and status = 'active'
    `;
    if (!existing[0]) throw new FamilyCloudError("child_profile_not_found");
    throw new FamilyCloudError("stale_child_profile_version");
  }
  await sql`
    insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
    values (
      ${input.familyId}, 'child_profile.updated', 'guardian',
      ${sha256(input.context.guardianId)}, ${rows[0].publicRef}
    )
  `;
  return familySnapshot(input.familyId, input.context.guardianId);
}

export async function issueFamilyInvite(input: {
  context: GuardianSessionContext;
  familyId: string;
  kind: "guardian" | "child_device";
  childProfileId?: string;
}): Promise<{ payload: string; publicRef: string; expiresAt: string; kind: string }> {
  const member = await membership(input.context, input.familyId);
  if (!member.isCreator) throw new FamilyCloudError("family_creator_required");
  if (input.kind === "child_device" && !input.childProfileId) throw new FamilyCloudError("child_profile_required");
  if (input.kind === "guardian" && input.childProfileId) throw new FamilyCloudError("invalid_invite_target");
  const sql = platformDatabase();
  if (input.childProfileId) {
    const child = await sql<{ id: string }[]>`
      select id from platform_child_profiles where id = ${input.childProfileId} and family_id = ${input.familyId} and status = 'active'
    `;
    if (!child[0]) throw new FamilyCloudError("child_profile_not_found");
  }
  const secret = randomToken(32);
  const inviteRef = publicRef("invite");
  const rows = await sql<{ expiresAt: string }[]>`
    insert into platform_family_invites (
      family_id, invite_kind, public_ref, secret_hash, created_by_guardian_id, child_profile_id, expires_at
    ) values (
      ${input.familyId}, ${input.kind}, ${inviteRef}, ${sha256(secret)}, ${input.context.guardianId},
      ${input.childProfileId ?? null}, now() + (${INVITE_SECONDS} * interval '1 second')
    ) returning expires_at::text as "expiresAt"
  `;
  const expiresAt = rows[0]?.expiresAt ?? new Date(Date.now() + INVITE_SECONDS * 1_000).toISOString();
  const encoded = Buffer.from(JSON.stringify({ version: 2, publicRef: inviteRef, secret, kind: input.kind, expiresAt })).toString("base64url");
  return { payload: `octoteacher://family/cloud-join/${encoded}`, publicRef: inviteRef, expiresAt, kind: input.kind };
}

export async function claimFamilyInvite(input: {
  publicRef: string;
  secret: string;
  devicePublicRef: string;
  deviceName: string;
  guardianContext?: GuardianSessionContext;
  consentVersion?: string;
  familySyncAccepted?: boolean;
  childTaskSyncAccepted?: boolean;
  protocolGeneration?: unknown;
}): Promise<
  | { kind: "guardian"; family: FamilyCloudSnapshot }
  | {
      kind: "child_device";
      deviceSessionToken: string;
      family: { id: string; publicRef: string; displayName: string };
      child: FamilyCloudSnapshot["children"][number];
    }
> {
  const sql = platformDatabase();
  const deviceRef = validDeviceRef(input.devicePublicRef);
  const deviceName = safeText(input.deviceName, "invalid_device_name", 120);
  const inviteRef = safeText(input.publicRef, "invalid_invite_ref", 120);
  const secretHash = sha256(safeText(input.secret, "invalid_invite_secret", 512));
  const childToken = randomToken(48);

  const result = await sql.begin(async (tx) => {
    const invites = await tx<{
      id: string; familyId: string; kind: "guardian" | "child_device"; childProfileId?: string;
    }[]>`
      select id, family_id as "familyId", invite_kind as kind, child_profile_id as "childProfileId"
      from platform_family_invites
      where public_ref = ${inviteRef} and secret_hash = ${secretHash}
        and status = 'active' and expires_at > now() and use_count < max_uses
      for update
    `;
    const invite = invites[0];
    if (!invite) throw new FamilyCloudError("invite_invalid_or_expired");
    if (invite.kind === "guardian") {
      if (!input.guardianContext) throw new FamilyCloudError("guardian_session_required");
      if (input.consentVersion !== FAMILY_SYNC_CONSENT_VERSION || !input.familySyncAccepted || !input.childTaskSyncAccepted) {
        throw new FamilyCloudError("guardian_consent_required");
      }
      await tx`select pg_advisory_xact_lock(hashtextextended(${`guardian-family:${input.guardianContext.guardianId}`}, 0))`;
      await assertGuardianFamilyUniqueness(tx, input.guardianContext.guardianId, invite.familyId);
      await tx`
        insert into platform_family_guardians (family_id, guardian_id, is_creator, status, joined_at)
        values (${invite.familyId}, ${input.guardianContext.guardianId}, false, 'active', now())
        on conflict (family_id, guardian_id) do update set status = 'active', joined_at = coalesce(platform_family_guardians.joined_at, now())
      `;
      await tx`
        insert into platform_guardian_consents (
          guardian_id, consent_version, family_sync_accepted, child_task_sync_accepted
        ) values (${input.guardianContext.guardianId}, ${input.consentVersion}, true, true)
        on conflict (guardian_id, consent_version) do update set
          family_sync_accepted = true, child_task_sync_accepted = true, accepted_at = now(), revoked_at = null
      `;
      await tx`
        insert into platform_family_devices (family_id, guardian_id, public_ref, display_name, role)
        values (${invite.familyId}, ${input.guardianContext.guardianId}, ${deviceRef}, ${deviceName}, 'guardian')
        on conflict (public_ref) do update set status = 'active', revoked_at = null, last_seen_at = now()
      `;
    } else {
      if (!invite.childProfileId) throw new FamilyCloudError("invite_child_missing");
      const protocolGeneration = requireCurrentChildDeviceProtocol(input.protocolGeneration);
      await tx`select pg_advisory_xact_lock(hashtextextended(${`child-device:${invite.familyId}:${invite.childProfileId}`}, 0))`;
      await tx`
        update platform_family_devices
        set status = 'revoked', revoked_at = now(), session_token_hash = null,
            push_token = null, push_environment = null, push_token_updated_at = null
        where family_id = ${invite.familyId}
          and child_profile_id = ${invite.childProfileId}
          and role = 'child' and status = 'active' and public_ref <> ${deviceRef}
      `;
      const boundDevices = await tx<{ id: string }[]>`
        insert into platform_family_devices (
          family_id, child_profile_id, public_ref, display_name, role, session_token_hash,
          protocol_generation
        ) values (
          ${invite.familyId}, ${invite.childProfileId}, ${deviceRef}, ${deviceName}, 'child',
          ${sha256(childToken)}, ${protocolGeneration}
        )
        on conflict (public_ref) do update set
          family_id = excluded.family_id, child_profile_id = excluded.child_profile_id,
          display_name = excluded.display_name, session_token_hash = excluded.session_token_hash,
          protocol_generation = excluded.protocol_generation,
          status = 'active', revoked_at = null, bound_at = now(), last_seen_at = now(),
          push_token = null, push_environment = null, push_token_updated_at = null
        where platform_family_devices.role = 'child'
        returning id
      `;
      if (!boundDevices[0]) throw new FamilyCloudError("device_role_conflict");
      await tx`
        update platform_child_profiles
        set screen_time_catalog = null,
            screen_time_policy = null,
            screen_time_status = jsonb_build_object(
              'authorization', coalesce(screen_time_status->>'authorization', 'not_requested'),
              'enforcement', case
                when screen_time_status->>'authorization' = 'approved' then 'waiting_for_policy'
                else 'waiting_for_authorization'
              end,
              'updatedAt', now()::text
            ),
            profile_version = profile_version + 1,
            updated_at = now()
        where id = ${invite.childProfileId} and family_id = ${invite.familyId} and status = 'active'
      `;
    }
    await tx`
      update platform_family_invites
      set use_count = use_count + 1, status = 'consumed', consumed_at = now()
      where id = ${invite.id}
    `;
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
      values (
        ${invite.familyId}, ${invite.kind === "guardian" ? "guardian.joined" : "child_device.bound"},
        ${invite.kind === "guardian" ? "guardian" : "child_device"},
        ${sha256(input.guardianContext?.guardianId ?? deviceRef)}, ${deviceRef}
      )
    `;
    return invite;
  });

  if (result.kind === "guardian") {
    return { kind: "guardian", family: await familySnapshot(result.familyId, input.guardianContext!.guardianId) };
  }
  const rows = await sql<{
    familyId: string; familyPublicRef: string; familyName: string;
    childId: string; childPublicRef: string; childClientRef?: string; childName: string;
    birthYear?: number; preReaderMode: boolean; interfaceLanguage: "chinese" | "english";
    contentLanguage: "chinese" | "english" | "bilingual"; dailyLimitMinutes: number;
    exchangePolicy: FamilyExchangePolicyPayload;
    screenTimeCatalog?: FamilyScreenTimeCatalogPayload;
    screenTimePolicy?: FamilyScreenTimePolicyPayload;
    screenTimeStatus: FamilyScreenTimeStatusPayload;
    screenTimeEmergency: FamilyScreenTimeEmergencyPayload;
    growthPointBalance: number;
    profileVersion: number;
  }[]>`
    select f.id as "familyId", f.public_ref as "familyPublicRef", f.display_name as "familyName",
      c.id as "childId", c.public_ref as "childPublicRef", c.client_ref as "childClientRef",
      c.display_name as "childName", c.birth_year as "birthYear", c.pre_reader_mode as "preReaderMode",
      c.interface_language as "interfaceLanguage", c.content_language as "contentLanguage",
      c.daily_limit_minutes as "dailyLimitMinutes", c.exchange_policy as "exchangePolicy",
      c.screen_time_catalog as "screenTimeCatalog",
      c.screen_time_policy as "screenTimePolicy", c.screen_time_status as "screenTimeStatus",
      c.screen_time_emergency as "screenTimeEmergency",
      c.growth_point_balance as "growthPointBalance",
      c.profile_version as "profileVersion"
    from platform_families f join platform_child_profiles c on c.family_id = f.id
    where f.id = ${result.familyId} and c.id = ${result.childProfileId!}
  `;
  const row = rows[0];
  if (!row) throw new FamilyCloudError("invite_claim_result_missing");
  const screenTime = normalizeScreenTimeStateForDevice({
    catalog: row.screenTimeCatalog,
    policy: row.screenTimePolicy,
    devicePublicRef: deviceRef,
  });
  return {
    kind: "child_device",
    deviceSessionToken: childToken,
    family: { id: row.familyId, publicRef: row.familyPublicRef, displayName: row.familyName },
    child: {
      id: row.childId,
      publicRef: row.childPublicRef,
      clientRef: row.childClientRef,
      displayName: row.childName,
      birthYear: row.birthYear,
      preReaderMode: row.preReaderMode,
      interfaceLanguage: row.interfaceLanguage,
      contentLanguage: row.contentLanguage,
      dailyLimitMinutes: row.dailyLimitMinutes,
      exchangePolicy: row.exchangePolicy,
      screenTimeCatalog: screenTime.catalog,
      screenTimePolicy: screenTime.policy,
      screenTimeStatus: row.screenTimeStatus,
      screenTimeEmergency: row.screenTimeEmergency,
      growthPointBalance: row.growthPointBalance,
      profileVersion: row.profileVersion,
    },
  };
}

export async function loadChildDeviceProfile(context: ChildDeviceSessionContext): Promise<
  FamilyCloudSnapshot["children"][number] & { family: { id: string; publicRef: string; displayName: string } }
> {
  const sql = platformDatabase();
  const rows = await sql<(FamilyCloudSnapshot["children"][number] & {
    family: { id: string; publicRef: string; displayName: string };
  })[]>`
    select c.id, c.public_ref as "publicRef", c.client_ref as "clientRef", c.display_name as "displayName",
      c.birth_year as "birthYear", c.pre_reader_mode as "preReaderMode",
      c.interface_language as "interfaceLanguage", c.content_language as "contentLanguage",
      c.daily_limit_minutes as "dailyLimitMinutes", c.exchange_policy as "exchangePolicy",
      c.screen_time_catalog as "screenTimeCatalog",
      c.screen_time_policy as "screenTimePolicy", c.screen_time_status as "screenTimeStatus",
      c.screen_time_emergency as "screenTimeEmergency",
      c.growth_point_balance as "growthPointBalance",
      c.profile_version as "profileVersion",
      json_build_object('id', f.id, 'publicRef', f.public_ref, 'displayName', f.display_name) as family
    from platform_child_profiles c join platform_families f on f.id = c.family_id
    where c.id = ${context.childProfileId} and c.family_id = ${context.familyId} and c.status = 'active'
  `;
  const row = rows[0];
  if (!row) throw new FamilyCloudError("child_profile_not_found");
  const screenTime = normalizeScreenTimeStateForDevice({
    catalog: row.screenTimeCatalog,
    policy: row.screenTimePolicy,
    devicePublicRef: context.devicePublicRef,
  });
  return {
    ...row,
    screenTimeCatalog: screenTime.catalog,
    screenTimePolicy: screenTime.policy,
  };
}

export async function updateChildDeviceInterfaceLanguage(
  context: ChildDeviceSessionContext,
  interfaceLanguage: "chinese" | "english",
): Promise<FamilyCloudSnapshot["children"][number] & {
  family: { id: string; publicRef: string; displayName: string };
}> {
  const sql = platformDatabase();
  await sql.begin(async (tx) => {
    const rows = await tx<{ publicRef: string }[]>`
      update platform_child_profiles c
      set interface_language = ${interfaceLanguage},
          profile_version = c.profile_version + 1,
          updated_at = now()
      where c.id = ${context.childProfileId}
        and c.family_id = ${context.familyId}
        and c.status = 'active'
        and exists (
          select 1
          from platform_family_devices d
          where d.id = ${context.deviceId}
            and d.family_id = c.family_id
            and d.child_profile_id = c.id
            and d.role = 'child'
            and d.status = 'active'
        )
      returning c.public_ref as "publicRef"
    `;
    const row = rows[0];
    if (!row) throw new FamilyCloudError("child_profile_not_found");
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
      values (
        ${context.familyId}, 'child_profile.interface_language.updated', 'child_device',
        ${sha256(context.deviceId)}, ${row.publicRef}
      )
    `;
  });
  return loadChildDeviceProfile(context);
}

export async function mutateChildDeviceGrowthPoints(
  context: ChildDeviceSessionContext,
  rawMutation: unknown,
): Promise<FamilyGrowthPointMutationResult> {
  const mutation = normalizeGrowthPointMutation(rawMutation);
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const children = await tx<{ balance: number }[]>`
      select growth_point_balance as balance from platform_child_profiles
      where id = ${context.childProfileId} and family_id = ${context.familyId} and status = 'active'
      for update
    `;
    const child = children[0];
    if (!child) throw new FamilyCloudError("child_profile_not_found");

    const byMutationRef = await tx<{
      kind: string; delta: number; sourceRef: string;
    }[]>`
      select entry_kind as kind, delta, source_ref as "sourceRef"
      from platform_family_growth_point_ledger
      where child_profile_id = ${context.childProfileId} and mutation_ref = ${mutation.mutationRef}
    `;
    if (byMutationRef[0]) {
      const prior = byMutationRef[0];
      if (prior.kind !== mutation.kind || prior.delta !== mutation.delta || prior.sourceRef !== mutation.sourceRef) {
        throw new FamilyCloudError("points_mutation_ref_conflict");
      }
      return { balance: child.balance, applied: false };
    }

    const bySourceRef = await tx<{ delta: number }[]>`
      select delta
      from platform_family_growth_point_ledger
      where child_profile_id = ${context.childProfileId}
        and entry_kind = ${mutation.kind} and source_ref = ${mutation.sourceRef}
    `;
    if (bySourceRef[0]) {
      if (bySourceRef[0].delta !== mutation.delta) {
        throw new FamilyCloudError("points_source_ref_conflict");
      }
      return { balance: child.balance, applied: false };
    }

    if (mutation.kind === "screen_time_refund") {
      const spends = await tx<{ delta: number }[]>`
        select delta from platform_family_growth_point_ledger
        where child_profile_id = ${context.childProfileId}
          and entry_kind = 'screen_time_spend' and source_ref = ${mutation.sourceRef}
      `;
      if (!spends[0] || mutation.delta > -spends[0].delta) {
        throw new FamilyCloudError("points_refund_invalid");
      }
    }

    const balanceAfter = child.balance + mutation.delta;
    if (balanceAfter < 0) throw new FamilyCloudError("insufficient_growth_points");
    const inserted = await tx<{ id: string }[]>`
      insert into platform_family_growth_point_ledger (
        family_id, child_profile_id, entry_kind, delta, balance_after, mutation_ref, source_ref
      ) values (
        ${context.familyId}, ${context.childProfileId}, ${mutation.kind}, ${mutation.delta},
        ${balanceAfter}, ${mutation.mutationRef}, ${mutation.sourceRef}
      )
      on conflict do nothing
      returning id
    `;
    if (!inserted[0]) throw new FamilyCloudError("points_mutation_conflict");
    await tx`
      update platform_child_profiles set growth_point_balance = ${balanceAfter}
      where id = ${context.childProfileId} and family_id = ${context.familyId}
    `;
    return { balance: balanceAfter, applied: true };
  });
}

export async function updateFamilyScreenTimePolicy(input: {
  context: GuardianSessionContext;
  familyId: string;
  childProfileId: string;
  policy?: unknown;
}): Promise<FamilyCloudSnapshot> {
  await membership(input.context, input.familyId);
  const sql = platformDatabase();
  let wakeRevision: number | undefined;
  let wakeCommandId: string | undefined;
  if (input.policy === undefined || input.policy === null) {
    const rows = await sql<{ id: string }[]>`
      update platform_child_profiles
      set screen_time_policy = null,
          screen_time_status = jsonb_build_object(
            'authorization', coalesce(screen_time_status->>'authorization', 'not_requested'),
            'enforcement', 'waiting_for_policy',
            'appliedPolicyRevision', null,
            'appliedSelectionHash', null,
            'appliedControlCommandId', null,
            'controlMode', null,
            'unlockedUntil', null,
            'lastErrorCode', null,
            'updatedAt', now()::text
          ),
          profile_version = profile_version + 1,
          updated_at = now()
      where id = ${input.childProfileId} and family_id = ${input.familyId} and status = 'active'
      returning id
    `;
    if (!rows[0]) throw new FamilyCloudError("child_profile_not_found");
  } else {
    const compatibleDevices = await sql<{ available: boolean }[]>`
      select exists (
        select 1 from platform_family_devices
        where family_id = ${input.familyId}
          and child_profile_id = ${input.childProfileId}
          and role = 'child'
          and status = 'active'
          and protocol_generation = ${CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION}
      ) as available
    `;
    if (compatibleDevices[0]?.available !== true) {
      throw new FamilyCloudError("child_device_rebind_required");
    }
    const policy = normalizeScreenTimePolicy(input.policy);
    const catalogRevision = policy.catalogBinding?.revision ?? 0;
    const catalogSelectionHash = policy.catalogBinding?.selectionHash ?? "";
    wakeRevision = policy.revision;
    wakeCommandId = policy.control?.commandId;
    const rows = await sql<{ id: string }[]>`
      update platform_child_profiles
      set screen_time_policy = ${sql.json(policy as any)},
          profile_version = profile_version + 1,
          updated_at = now()
      where id = ${input.childProfileId} and family_id = ${input.familyId} and status = 'active'
        and (${policy.revision} > coalesce((screen_time_policy->>'revision')::integer, 0)
          or screen_time_policy is null)
        and (${policy.catalogBinding === undefined} or (
          (screen_time_catalog->>'revision')::integer = ${catalogRevision}
          and screen_time_catalog->>'selectionHash' = ${catalogSelectionHash}
          and exists (
            select 1 from platform_family_devices d
            where d.family_id = ${input.familyId}
              and d.child_profile_id = ${input.childProfileId}
              and d.public_ref = screen_time_catalog->>'sourceDevicePublicRef'
              and d.role = 'child' and d.status = 'active'
              and d.protocol_generation = ${CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION}
          )
        ))
      returning id
    `;
    if (!rows[0]) {
      throw new FamilyCloudError(
        policy.catalogBinding === undefined
          ? "stale_screen_time_policy"
          : "stale_screen_time_catalog_binding",
      );
    }
  }
  await sql`
    insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
    select ${input.familyId}, 'screen_time.policy.updated', 'guardian', ${sha256(input.context.guardianId)}, public_ref
    from platform_child_profiles where id = ${input.childProfileId} and family_id = ${input.familyId}
  `;
  await wakeChildScreenTimeDevice({
    familyId: input.familyId,
    childProfileId: input.childProfileId,
    revision: wakeRevision,
    commandId: wakeCommandId,
  });
  return familySnapshot(input.familyId, input.context.guardianId);
}

export async function updateFamilyScreenTimeControl(input: {
  context: GuardianSessionContext;
  familyId: string;
  childProfileId: string;
  control: unknown;
}): Promise<FamilyCloudSnapshot> {
  const member = await membership(input.context, input.familyId);
  const sql = platformDatabase();
  let wakeRevision: number | undefined;
  let wakeCommandId: string | undefined;
  await sql.begin(async (tx) => {
    const rows = await tx<Array<{
      familyId: string;
      childProfileId: string;
      childPublicRef: string;
      policy: unknown;
    }>>`
      select c.family_id as "familyId", c.id as "childProfileId", c.public_ref as "childPublicRef",
        c.screen_time_policy as policy
      from platform_child_profiles c
      join platform_family_guardians m on m.family_id = c.family_id
        and m.guardian_id = ${input.context.guardianId} and m.status = 'active'
      where c.id = ${input.childProfileId}
        and c.family_id = ${member.familyId}
        and c.status = 'active'
      for update of c, m
    `;
    const row = rows[0];
    if (!row) throw new FamilyCloudError("child_profile_not_found");
    if (row.policy === undefined || row.policy === null) {
      throw new FamilyCloudError("screen_time_policy_required");
    }
    const current = normalizeStoredScreenTimePolicy(row.policy);
    const next = applyGuardianScreenTimeControl(current, input.control);
    wakeRevision = next.revision;
    wakeCommandId = next.control?.commandId;
    await tx`
      update platform_child_profiles
      set screen_time_policy = ${tx.json(next as any)},
          profile_version = profile_version + 1,
          updated_at = now()
      where id = ${row.childProfileId} and family_id = ${row.familyId} and status = 'active'
    `;
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
      values (
        ${row.familyId}, ${`screen_time.control.${next.control?.mode ?? "unknown"}`}, 'guardian',
        ${sha256(input.context.guardianId)}, ${row.childPublicRef}
      )
    `;
  });
  await wakeChildScreenTimeDevice({
    familyId: member.familyId,
    childProfileId: input.childProfileId,
    revision: wakeRevision,
    commandId: wakeCommandId,
  });
  return familySnapshot(member.familyId, input.context.guardianId);
}

async function wakeChildScreenTimeDevice(input: {
  familyId: string;
  childProfileId: string;
  revision?: number;
  commandId?: string;
}): Promise<void> {
  try {
    const sql = platformDatabase();
    const registrations = await sql<Array<{
      token: string;
      environment: ChildPushEnvironment;
    }>>`
      select push_token as token, push_environment as environment
      from platform_family_devices
      where family_id = ${input.familyId}
        and child_profile_id = ${input.childProfileId}
        and role = 'child'
        and status = 'active'
        and push_token is not null
        and push_environment in ('development', 'production')
    `;
    const outcome = await sendScreenTimeWakePushes(registrations.map((registration) => ({
      ...registration,
      revision: input.revision,
      commandId: input.commandId,
    })));
    if (outcome.configured && outcome.delivered < outcome.attempted) {
      console.warn("screen_time_push_partial_failure", {
        attempted: outcome.attempted,
        delivered: outcome.delivered,
      });
    }
  } catch {
    console.warn("screen_time_push_unavailable");
  }
}

export async function updateChildScreenTimeCatalog(input: {
  context: ChildDeviceSessionContext;
  catalog: unknown;
}): Promise<FamilyCloudSnapshot["children"][number] & {
  family: { id: string; publicRef: string; displayName: string };
}> {
  const upload = normalizeScreenTimeCatalogUpload(input.catalog);
  const sql = platformDatabase();
  await sql.begin(async (tx) => {
    const rows = await tx<{
      childPublicRef: string;
      devicePublicRef: string;
      currentRevision: number;
    }[]>`
      select c.public_ref as "childPublicRef", d.public_ref as "devicePublicRef",
        coalesce((c.screen_time_catalog->>'revision')::integer, 0) as "currentRevision"
      from platform_child_profiles c
      join platform_family_devices d on d.id = ${input.context.deviceId}
        and d.family_id = c.family_id and d.child_profile_id = c.id
        and d.role = 'child' and d.status = 'active'
      where c.id = ${input.context.childProfileId}
        and c.family_id = ${input.context.familyId}
        and c.status = 'active'
      for update of c, d
    `;
    const row = rows[0];
    if (!row) throw new FamilyCloudError("child_profile_not_found");
    const catalog: FamilyScreenTimeCatalogPayload = {
      ...upload,
      revision: row.currentRevision + 1,
      capturedAt: new Date().toISOString(),
      sourceDevicePublicRef: row.devicePublicRef,
    };
    await tx`
      update platform_child_profiles
      set screen_time_catalog = ${tx.json(catalog as any)},
          profile_version = profile_version + 1,
          updated_at = now()
      where id = ${input.context.childProfileId}
        and family_id = ${input.context.familyId}
        and status = 'active'
    `;
    await tx`
      insert into platform_family_audit (
        family_id, action, actor_kind, actor_ref_hash, target_public_ref
      ) values (
        ${input.context.familyId}, 'screen_time.catalog.updated', 'child_device',
        ${sha256(input.context.deviceId)}, ${row.childPublicRef}
      )
    `;
  });
  return loadChildDeviceProfile(input.context);
}

export async function updateChildScreenTimeStatus(input: {
  context: ChildDeviceSessionContext;
  status: unknown;
}): Promise<FamilyCloudSnapshot["children"][number] & {
  family: { id: string; publicRef: string; displayName: string };
}> {
  const status = normalizeScreenTimeStatus(input.status);
  const sql = platformDatabase();
  const rows = await sql<{ id: string }[]>`
    update platform_child_profiles
    set screen_time_status = ${sql.json(status as any)}, updated_at = now()
    where id = ${input.context.childProfileId} and family_id = ${input.context.familyId} and status = 'active'
    returning id
  `;
  if (!rows[0]) throw new FamilyCloudError("child_profile_not_found");
  return loadChildDeviceProfile(input.context);
}

type ScreenTimeEmergencyRow = {
  familyId: string;
  childProfileId: string;
  childPublicRef: string;
  emergency: unknown;
};

export async function updateChildScreenTimeEmergency(input: {
  context: ChildDeviceSessionContext;
  emergency: unknown;
}): Promise<FamilyCloudSnapshot["children"][number] & {
  family: { id: string; publicRef: string; displayName: string };
}> {
  const sql = platformDatabase();
  await sql.begin(async (tx) => {
    const rows = await tx<ScreenTimeEmergencyRow[]>`
      select c.family_id as "familyId", c.id as "childProfileId", c.public_ref as "childPublicRef",
        c.screen_time_emergency as emergency
      from platform_child_profiles c
      join platform_family_devices d on d.id = ${input.context.deviceId}
        and d.family_id = c.family_id and d.child_profile_id = c.id
        and d.role = 'child' and d.status = 'active'
      where c.id = ${input.context.childProfileId}
        and c.family_id = ${input.context.familyId}
        and c.status = 'active'
      for update of c, d
    `;
    const row = rows[0];
    if (!row) throw new FamilyCloudError("child_profile_not_found");
    assertScreenTimeEmergencyScope({
      actorFamilyId: input.context.familyId,
      childFamilyId: row.familyId,
      actorChildProfileId: input.context.childProfileId,
      childProfileId: row.childProfileId,
    });
    const current = normalizeStoredScreenTimeEmergency(row.emergency);
    const next = applyChildScreenTimeEmergencyAction(current, input.emergency);
    if (stableJSON(current) === stableJSON(next)) return;
    await tx`
      update platform_child_profiles
      set screen_time_emergency = ${tx.json(next as any)}, updated_at = now()
      where id = ${row.childProfileId} and family_id = ${row.familyId} and status = 'active'
    `;
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
      values (
        ${row.familyId}, ${`screen_time.emergency.${next.status}`}, 'child_device',
        ${sha256(input.context.deviceId)}, ${row.childPublicRef}
      )
    `;
  });
  return loadChildDeviceProfile(input.context);
}

export async function updateFamilyScreenTimeEmergency(input: {
  context: GuardianSessionContext;
  familyId: string;
  childProfileId: string;
  emergency: unknown;
}): Promise<FamilyCloudSnapshot> {
  const member = await membership(input.context, input.familyId);
  const sql = platformDatabase();
  await sql.begin(async (tx) => {
    const rows = await tx<ScreenTimeEmergencyRow[]>`
      select c.family_id as "familyId", c.id as "childProfileId", c.public_ref as "childPublicRef",
        c.screen_time_emergency as emergency
      from platform_child_profiles c
      join platform_family_guardians m on m.family_id = c.family_id
        and m.guardian_id = ${input.context.guardianId} and m.status = 'active'
      where c.id = ${input.childProfileId}
        and c.family_id = ${member.familyId}
        and c.status = 'active'
      for update of c, m
    `;
    const row = rows[0];
    if (!row) throw new FamilyCloudError("child_profile_not_found");
    assertScreenTimeEmergencyScope({
      actorFamilyId: member.familyId,
      childFamilyId: row.familyId,
      childProfileId: row.childProfileId,
    });
    const current = normalizeStoredScreenTimeEmergency(row.emergency);
    const next = applyGuardianScreenTimeEmergencyAction(current, input.emergency);
    if (stableJSON(current) === stableJSON(next)) return;
    await tx`
      update platform_child_profiles
      set screen_time_emergency = ${tx.json(next as any)}, updated_at = now()
      where id = ${row.childProfileId} and family_id = ${row.familyId} and status = 'active'
    `;
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
      values (
        ${row.familyId}, ${`screen_time.emergency.${next.status}`}, 'guardian',
        ${sha256(input.context.guardianId)}, ${row.childPublicRef}
      )
    `;
  });
  return familySnapshot(member.familyId, input.context.guardianId);
}

export async function revokeFamilyDevice(input: {
  context: GuardianSessionContext;
  familyId: string;
  deviceId: string;
}): Promise<FamilyCloudSnapshot> {
  const member = await membership(input.context, input.familyId);
  if (!member.isCreator) throw new FamilyCloudError("family_creator_required");
  const sql = platformDatabase();
  const rows = await sql<{ publicRef: string }[]>`
    update platform_family_devices
    set status = 'revoked', revoked_at = now(), session_token_hash = null,
        push_token = null, push_environment = null, push_token_updated_at = null
    where id = ${input.deviceId} and family_id = ${input.familyId} and status = 'active'
    returning public_ref as "publicRef"
  `;
  if (!rows[0]) throw new FamilyCloudError("device_not_found");
  await sql`
    insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref)
    values (${input.familyId}, 'device.revoked', 'guardian', ${sha256(input.context.guardianId)}, ${rows[0].publicRef})
  `;
  return familySnapshot(input.familyId, input.context.guardianId);
}

async function awardTaskGrowthPoints(
  tx: TransactionSql,
  input: { familyId: string; childProfileId: string; taskId: string; growthPoints: number },
): Promise<void> {
  if (input.growthPoints <= 0) return;
  const children = await tx<{ balance: number }[]>`
    select growth_point_balance as balance from platform_child_profiles
    where id = ${input.childProfileId} and family_id = ${input.familyId}
    for update
  `;
  const child = children[0];
  if (!child) throw new FamilyCloudError("task_child_not_found");
  const balanceAfter = child.balance + input.growthPoints;
  const inserted = await tx<{ id: string }[]>`
    insert into platform_family_growth_point_ledger (
      family_id, child_profile_id, entry_kind, delta, balance_after, mutation_ref, source_ref
    ) values (
      ${input.familyId}, ${input.childProfileId}, 'task_approved', ${input.growthPoints}, ${balanceAfter},
      ${`task-approved:${input.taskId}`}, ${`task-ref:${input.taskId}`}
    )
    on conflict do nothing
    returning id
  `;
  if (inserted[0]) {
    await tx`
      update platform_child_profiles set growth_point_balance = ${balanceAfter}
      where id = ${input.childProfileId} and family_id = ${input.familyId}
    `;
  }
}

export async function syncGuardianTasks(input: {
  context: GuardianSessionContext;
  familyId: string;
  mutationRef: string;
  tasks: Array<{
    childClientRef: string;
    clientRef: string;
    title: string;
    titleEnglish?: string;
    status: FamilyTaskCloudRecord["status"];
    growthPoints: number;
    requiresEvidence: boolean;
    plannedFor?: string;
    version: number;
    baseVersion?: number;
    taskPayload?: unknown;
  }>;
}): Promise<FamilyTaskCloudRecord[]> {
  await membership(input.context, input.familyId);
  const mutationRef = normalizeMutationRef(input.mutationRef);
  if (!Array.isArray(input.tasks) || input.tasks.length > 100) throw new FamilyCloudError("invalid_tasks");
  const allowedStatuses = new Set(["assigned", "started", "submitted", "approved", "rejected", "cancelled"]);
  const normalized = input.tasks.map((task) => {
    const status = safeText(task.status, "invalid_task_status", 20) as FamilyTaskCloudRecord["status"];
    if (!allowedStatuses.has(status)) throw new FamilyCloudError("invalid_task_status");
    if (!Number.isInteger(task.growthPoints) || task.growthPoints < 0 || task.growthPoints > 10_000) throw new FamilyCloudError("invalid_task_points");
    if (!Number.isInteger(task.version) || task.version < 1) throw new FamilyCloudError("invalid_task_version");
    if (task.baseVersion !== undefined && (!Number.isInteger(task.baseVersion) || task.baseVersion < 1)) {
      throw new FamilyCloudError("invalid_task_base_version");
    }
    if (task.plannedFor && !/^\d{4}-\d{2}-\d{2}$/.test(task.plannedFor)) throw new FamilyCloudError("invalid_task_date");
    const taskPayload = task.taskPayload === undefined
      ? undefined
      : JSON.parse(JSON.stringify(task.taskPayload)) as unknown;
    if (taskPayload !== undefined && JSON.stringify(taskPayload).length > 64_000) {
      throw new FamilyCloudError("invalid_task_payload");
    }
    const delivery = classifyFamilyTaskDelivery(taskPayload);
    return {
      childClientRef: safeText(task.childClientRef, "invalid_child_client_ref", 120),
      clientRef: safeText(task.clientRef, "invalid_task_ref", 120),
      title: safeText(task.title, "invalid_task_title", 240),
      titleEnglish: optionalText(task.titleEnglish, "invalid_task_title_english", 240),
      status,
      growthPoints: task.growthPoints,
      requiresEvidence: Boolean(task.requiresEvidence),
      plannedFor: task.plannedFor,
      version: task.version,
      baseVersion: task.baseVersion,
      taskPayload,
      deliveryStatus: delivery.status,
      quarantineReason: delivery.reason,
    };
  });
  const sql = platformDatabase();
  await sql.begin(async (tx) => {
    const receipt = await tx<{ id: string }[]>`
      insert into platform_family_sync_requests (family_id, actor_kind, actor_ref_hash, mutation_ref)
      values (${input.familyId}, 'guardian', ${sha256(input.context.guardianId)}, ${mutationRef})
      on conflict (family_id, actor_kind, actor_ref_hash, mutation_ref) do nothing
      returning id
    `;
    if (!receipt[0]) return;

    for (const task of normalized) {
      const children = await tx<{ id: string }[]>`
        select id from platform_child_profiles
        where family_id = ${input.familyId} and client_ref = ${task.childClientRef} and status = 'active'
      `;
      if (!children[0]) throw new FamilyCloudError("task_child_not_found");
      const existing = await tx<{
        id: string; childProfileId: string; title: string; titleEnglish: string | null;
        status: FamilyTaskCloudRecord["status"]; growthPoints: number; requiresEvidence: boolean;
        plannedFor: string | null; taskPayload: unknown;
        deliveryStatus: FamilyTaskCloudRecord["deliveryStatus"]; quarantineReason: string | null;
        version: number;
      }[]>`
        select id, child_profile_id as "childProfileId", title, title_english as "titleEnglish", status,
          growth_points as "growthPoints", requires_evidence as "requiresEvidence",
          planned_for::text as "plannedFor", task_payload as "taskPayload",
          delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason", version
        from platform_family_tasks
        where family_id = ${input.familyId} and client_ref = ${task.clientRef}
        for update
      `;

      let changed: {
        id: string;
        childProfileId: string;
        previousChildProfileId?: string;
        version: number;
        kind: "created" | "updated";
      } | undefined;
      if (!existing[0]) {
        if (task.baseVersion !== undefined) throw new FamilyCloudError("stale_task_version");
        const inserted = await tx<{ id: string; childProfileId: string; version: number }[]>`
          insert into platform_family_tasks (
          family_id, child_profile_id, client_ref, title, title_english, status, growth_points,
          requires_evidence, planned_for, task_payload, delivery_status, quarantine_reason,
          version, created_by_guardian_id, reviewed_at
          ) values (
            ${input.familyId}, ${children[0].id}, ${task.clientRef}, ${task.title}, ${task.titleEnglish ?? null},
            ${task.status}, ${task.growthPoints}, ${task.requiresEvidence}, ${task.plannedFor ?? null},
            ${task.taskPayload === undefined ? null : sql.json(task.taskPayload as any)},
            ${task.deliveryStatus}, ${task.quarantineReason ?? null},
            1, ${input.context.guardianId}, ${task.status === "approved" || task.status === "rejected" ? sql`now()` : null}
          )
          returning id, child_profile_id as "childProfileId", version
        `;
        if (inserted[0]) {
          changed = { ...inserted[0], kind: "created" };
          if (shouldAwardTaskGrowthPoints(undefined, task.status)) {
            await awardTaskGrowthPoints(tx, {
              familyId: input.familyId,
              childProfileId: inserted[0].childProfileId,
              taskId: inserted[0].id,
              growthPoints: task.growthPoints,
            });
          }
        }
      } else {
        const current = existing[0];
        if (task.baseVersion !== undefined && task.baseVersion !== current.version) {
          throw new FamilyCloudError("stale_task_version");
        }
        if (current.status === "approved" &&
            (current.childProfileId !== children[0].id || current.growthPoints !== task.growthPoints)) {
          throw new FamilyCloudError("approved_task_award_immutable");
        }
        const resolvedStatus = resolveGuardianTaskStatus(current.status, task.status);
        const isChanged = current.childProfileId !== children[0].id || current.title !== task.title ||
          (current.titleEnglish ?? undefined) !== task.titleEnglish || current.status !== resolvedStatus ||
          current.growthPoints !== task.growthPoints || current.requiresEvidence !== task.requiresEvidence ||
          (current.plannedFor ?? undefined) !== task.plannedFor ||
          current.deliveryStatus !== task.deliveryStatus ||
          (current.quarantineReason ?? undefined) !== task.quarantineReason ||
          stableJSON(current.taskPayload ?? null) !== stableJSON(task.taskPayload ?? null);
        if (isChanged) {
          const updated = await tx<{ id: string; childProfileId: string; version: number }[]>`
            update platform_family_tasks set
              child_profile_id = ${children[0].id}, title = ${task.title}, title_english = ${task.titleEnglish ?? null},
              status = ${resolvedStatus}, growth_points = ${task.growthPoints},
              requires_evidence = ${task.requiresEvidence}, planned_for = ${task.plannedFor ?? null},
              task_payload = ${task.taskPayload === undefined ? null : sql.json(task.taskPayload as any)},
              delivery_status = ${task.deliveryStatus}, quarantine_reason = ${task.quarantineReason ?? null},
              reviewed_at = case
                when status <> ${resolvedStatus} and ${resolvedStatus} in ('approved', 'rejected') then now()
                else reviewed_at
              end,
              version = version + 1, updated_at = now()
            where id = ${current.id}
            returning id, child_profile_id as "childProfileId", version
          `;
          if (updated[0]) {
            changed = {
              ...updated[0],
              previousChildProfileId: current.childProfileId !== updated[0].childProfileId
                ? current.childProfileId
                : undefined,
              kind: "updated",
            };
            if (shouldAwardTaskGrowthPoints(current.status, resolvedStatus)) {
              await awardTaskGrowthPoints(tx, {
                familyId: input.familyId,
                childProfileId: updated[0].childProfileId,
                taskId: updated[0].id,
                growthPoints: task.growthPoints,
              });
            }
          }
        }
      }

      if (changed) {
        if (changed.previousChildProfileId) {
          await tx`
            insert into platform_family_task_changes (
              family_id, child_profile_id, task_id, task_version, change_kind
            ) values (
              ${input.familyId}, ${changed.previousChildProfileId}, ${changed.id}, ${changed.version}, 'updated'
            ) on conflict (task_id, task_version, child_profile_id) do nothing
          `;
        }
        await tx`
          insert into platform_family_task_changes (
            family_id, child_profile_id, task_id, task_version, change_kind
          ) values (
            ${input.familyId}, ${changed.childProfileId}, ${changed.id}, ${changed.version}, ${changed.kind}
          ) on conflict (task_id, task_version, child_profile_id) do nothing
        `;
      }
    }
  });
  return listGuardianTasks(input.context, input.familyId);
}

async function taskSyncPage(input: {
  familyId: string;
  afterCursor: unknown;
  childProfileId?: string;
}): Promise<FamilyTaskSyncPage> {
  const afterCursor = parseFamilyTaskCursor(input.afterCursor);
  const sql = platformDatabase();
  const changes = input.childProfileId
    ? await sql<{ cursor: string; taskId: string }[]>`
        select cursor::text as cursor, task_id as "taskId"
        from platform_family_task_changes
        where family_id = ${input.familyId} and child_profile_id = ${input.childProfileId} and cursor > ${afterCursor}
        order by cursor asc limit ${FAMILY_TASK_SYNC_PAGE_LIMIT}
      `
    : await sql<{ cursor: string; taskId: string }[]>`
        select cursor::text as cursor, task_id as "taskId"
        from platform_family_task_changes
        where family_id = ${input.familyId} and cursor > ${afterCursor}
        order by cursor asc limit ${FAMILY_TASK_SYNC_PAGE_LIMIT}
      `;
  if (changes.length === 0) {
    return { tasks: [], removedClientRefs: [], cursor: afterCursor, hasMore: false };
  }

  const taskIds = [...new Set(changes.map((change) => change.taskId))];
  const tasks = await sql<FamilyTaskCloudRecord[]>`
    select id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
      title_english as "titleEnglish", status, growth_points as "growthPoints",
      requires_evidence as "requiresEvidence", planned_for::text as "plannedFor",
      evidence_summary as "evidenceSummary", task_payload as "taskPayload",
      delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
      version, updated_at::text as "updatedAt"
    from platform_family_tasks
    where family_id = ${input.familyId} and id in ${sql(taskIds)}
      and (${input.childProfileId === undefined} or (
        child_profile_id = ${input.childProfileId ?? null} and delivery_status = 'ready'
      ))
    order by updated_at, id
  `;
  const removedClientRefs = input.childProfileId === undefined
    ? []
    : (await sql<{ id: string; clientRef: string }[]>`
        select id, client_ref as "clientRef"
        from platform_family_tasks
        where family_id = ${input.familyId} and id in ${sql(taskIds)}
      `)
      .filter((task) => !tasks.some((current) => current.id === task.id))
      .map((task) => task.clientRef);
  const cursor = Math.max(...changes.map((change) => Number(change.cursor)));
  const more = input.childProfileId
    ? await sql<{ exists: boolean }[]>`
        select exists(
          select 1 from platform_family_task_changes
          where family_id = ${input.familyId} and child_profile_id = ${input.childProfileId} and cursor > ${cursor}
        ) as exists
      `
    : await sql<{ exists: boolean }[]>`
        select exists(
          select 1 from platform_family_task_changes where family_id = ${input.familyId} and cursor > ${cursor}
        ) as exists
      `;
  return { tasks, removedClientRefs, cursor, hasMore: more[0]?.exists ?? false };
}

export async function listGuardianTaskChanges(
  context: GuardianSessionContext,
  familyId: string,
  afterCursor: unknown,
): Promise<FamilyTaskSyncPage> {
  await membership(context, familyId);
  return taskSyncPage({ familyId, afterCursor });
}

async function latestTaskCursor(familyId: string, childProfileId?: string): Promise<number> {
  const sql = platformDatabase();
  const rows = childProfileId
    ? await sql<{ cursor: string }[]>`
        select coalesce(max(cursor), 0)::text as cursor
        from platform_family_task_changes
        where family_id = ${familyId} and child_profile_id = ${childProfileId}
      `
    : await sql<{ cursor: string }[]>`
        select coalesce(max(cursor), 0)::text as cursor
        from platform_family_task_changes
        where family_id = ${familyId}
      `;
  return Number(rows[0]?.cursor ?? 0);
}

export async function listChildDeviceTaskChanges(
  context: ChildDeviceSessionContext,
  afterCursor: unknown,
): Promise<FamilyTaskSyncPage> {
  return taskSyncPage({
    familyId: context.familyId,
    childProfileId: context.childProfileId,
    afterCursor,
  });
}

export async function listGuardianTaskSnapshot(
  context: GuardianSessionContext,
  familyId: string,
): Promise<FamilyTaskSyncPage> {
  // Capture the cursor first. A task committed while the snapshot query runs may be
  // returned twice by the following delta, but can never fall between the snapshot
  // rows and a newer cursor and disappear from both responses.
  const cursor = await latestTaskCursor(familyId);
  const tasks = await listGuardianTasks(context, familyId);
  return { tasks, removedClientRefs: [], cursor, hasMore: false };
}

export async function listChildDeviceTaskSnapshot(
  context: ChildDeviceSessionContext,
): Promise<FamilyTaskSyncPage> {
  const cursor = await latestTaskCursor(context.familyId, context.childProfileId);
  const tasks = await listChildDeviceTasks(context);
  return {
    tasks,
    removedClientRefs: [],
    cursor,
    hasMore: false,
  };
}

export async function listGuardianTasks(context: GuardianSessionContext, familyId: string): Promise<FamilyTaskCloudRecord[]> {
  await membership(context, familyId);
  const sql = platformDatabase();
  return sql<FamilyTaskCloudRecord[]>`
    select id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
      title_english as "titleEnglish", status, growth_points as "growthPoints",
      requires_evidence as "requiresEvidence", planned_for::text as "plannedFor",
      evidence_summary as "evidenceSummary", task_payload as "taskPayload",
      delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
      version, updated_at::text as "updatedAt"
    from platform_family_tasks where family_id = ${familyId}
    order by planned_for nulls last, created_at
  `;
}

export async function loadFamilyConsole(
  context: GuardianSessionContext,
  familyId: string,
): Promise<FamilyConsole> {
  await membership(context, familyId);
  const sql = platformDatabase();
  const { loadGuardianChildSurfaces } = await import("./postgres-family-control.js");
  const [snapshot, tasks, ai, surfaces] = await Promise.all([
    traceFamilyConsoleStage("snapshot", () => familySnapshot(familyId, context.guardianId)),
    traceFamilyConsoleStage("tasks", () => listGuardianTasks(context, familyId)),
    traceFamilyConsoleStage("ai", () => sql<{ configured: boolean }[]>`
        select exists(
          select 1 from platform_family_ai_relays where family_id = ${familyId}
        ) as configured
      `),
    traceFamilyConsoleStage("surfaces", () => loadGuardianChildSurfaces(context, familyId)),
  ]);
  return buildFamilyConsole(snapshot, tasks, ai[0]?.configured ?? false, surfaces, {
    id: context.guardianId,
    displayName: context.displayName,
  });
}

async function traceFamilyConsoleStage<T>(stage: string, operation: () => Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    const detail = error && typeof error === "object"
      ? error as Record<string, unknown>
      : {};
    console.error("family_console_stage_failed", {
      stage,
      name: error instanceof Error ? error.name : typeof error,
      code: typeof detail.code === "string" ? detail.code : undefined,
      severity: typeof detail.severity === "string" ? detail.severity : undefined,
      table: typeof detail.table_name === "string" ? detail.table_name : undefined,
      column: typeof detail.column_name === "string" ? detail.column_name : undefined,
      constraint: typeof detail.constraint_name === "string" ? detail.constraint_name : undefined,
    });
    throw error;
  }
}

export async function listChildDeviceTasks(context: ChildDeviceSessionContext): Promise<FamilyTaskCloudRecord[]> {
  const sql = platformDatabase();
  return sql<FamilyTaskCloudRecord[]>`
    select id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
      title_english as "titleEnglish", status, growth_points as "growthPoints",
      requires_evidence as "requiresEvidence", planned_for::text as "plannedFor",
      evidence_summary as "evidenceSummary", task_payload as "taskPayload",
      delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
      version, updated_at::text as "updatedAt"
    from platform_family_tasks
    where family_id = ${context.familyId} and child_profile_id = ${context.childProfileId}
      and delivery_status = 'ready'
    order by planned_for nulls last, created_at
  `;
}

export async function submitChildDeviceTask(input: {
  context: ChildDeviceSessionContext;
  taskId: string;
  evidenceSummary?: string;
  mutationRef: string;
  expectedVersion?: number;
}): Promise<FamilyTaskCloudRecord> {
  const summary = optionalText(input.evidenceSummary, "invalid_evidence_summary", 500);
  const mutationRef = normalizeMutationRef(input.mutationRef);
  if (input.expectedVersion !== undefined && (!Number.isInteger(input.expectedVersion) || input.expectedVersion < 1)) {
    throw new FamilyCloudError("invalid_task_base_version");
  }
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const actorHash = sha256(input.context.deviceId);
    const receipt = await tx<{ id: string }[]>`
      insert into platform_family_sync_requests (family_id, actor_kind, actor_ref_hash, mutation_ref)
      values (${input.context.familyId}, 'child_device', ${actorHash}, ${mutationRef})
      on conflict (family_id, actor_kind, actor_ref_hash, mutation_ref) do nothing
      returning id
    `;
    const current = await tx<FamilyTaskCloudRecord[]>`
      select id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
        title_english as "titleEnglish", status, growth_points as "growthPoints",
        requires_evidence as "requiresEvidence", planned_for::text as "plannedFor",
        evidence_summary as "evidenceSummary", task_payload as "taskPayload",
        delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
        version, updated_at::text as "updatedAt"
      from platform_family_tasks
      where id = ${input.taskId} and family_id = ${input.context.familyId}
        and child_profile_id = ${input.context.childProfileId}
        and delivery_status = 'ready'
      for update
    `;
    if (!current[0]) throw new FamilyCloudError("task_not_submittable");
    if (!receipt[0]) return current[0];
    if (input.expectedVersion !== undefined && input.expectedVersion !== current[0].version) {
      throw new FamilyCloudError("stale_task_version");
    }
    if (!["assigned", "started", "rejected"].includes(current[0].status)) {
      throw new FamilyCloudError("task_not_submittable");
    }
    const rows = await tx<FamilyTaskCloudRecord[]>`
      update platform_family_tasks
      set status = 'submitted', evidence_summary = ${summary ?? null}, submitted_by_device_id = ${input.context.deviceId},
        submitted_at = now(), updated_at = now(), version = version + 1
      where id = ${input.taskId}
      returning id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
        title_english as "titleEnglish", status, growth_points as "growthPoints",
        requires_evidence as "requiresEvidence", planned_for::text as "plannedFor",
        evidence_summary as "evidenceSummary", task_payload as "taskPayload",
        delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
        version, updated_at::text as "updatedAt"
    `;
    const updated = rows[0];
    if (!updated) throw new FamilyCloudError("task_not_submittable");
    await tx`
      insert into platform_family_task_changes (family_id, child_profile_id, task_id, task_version, change_kind)
      values (${input.context.familyId}, ${input.context.childProfileId}, ${updated.id}, ${updated.version}, 'submitted')
      on conflict (task_id, task_version, child_profile_id) do nothing
    `;
    return updated;
  });
}

export async function withdrawChildDeviceTask(input: {
  context: ChildDeviceSessionContext;
  taskId: string;
  mutationRef: string;
  expectedVersion?: number;
}): Promise<FamilyTaskCloudRecord> {
  const mutationRef = normalizeMutationRef(input.mutationRef);
  if (input.expectedVersion !== undefined && (!Number.isInteger(input.expectedVersion) || input.expectedVersion < 1)) {
    throw new FamilyCloudError("invalid_task_base_version");
  }
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const actorHash = sha256(input.context.deviceId);
    const receipt = await tx<{ id: string }[]>`
      insert into platform_family_sync_requests (family_id, actor_kind, actor_ref_hash, mutation_ref)
      values (${input.context.familyId}, 'child_device', ${actorHash}, ${mutationRef})
      on conflict (family_id, actor_kind, actor_ref_hash, mutation_ref) do nothing
      returning id
    `;
    const current = await tx<FamilyTaskCloudRecord[]>`
      select id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
        title_english as "titleEnglish", status, growth_points as "growthPoints",
        requires_evidence as "requiresEvidence", planned_for::text as "plannedFor",
        evidence_summary as "evidenceSummary", task_payload as "taskPayload",
        delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
        version, updated_at::text as "updatedAt"
      from platform_family_tasks
      where id = ${input.taskId} and family_id = ${input.context.familyId}
        and child_profile_id = ${input.context.childProfileId}
        and delivery_status = 'ready'
      for update
    `;
    if (!current[0]) throw new FamilyCloudError("task_not_withdrawable");
    if (!receipt[0]) return current[0];
    if (input.expectedVersion !== undefined && input.expectedVersion !== current[0].version) {
      throw new FamilyCloudError("stale_task_version");
    }
    if (!canWithdrawChildTask(current[0].status)) {
      throw new FamilyCloudError("task_not_withdrawable");
    }
    const rows = await tx<FamilyTaskCloudRecord[]>`
      update platform_family_tasks
      set status = 'assigned', evidence_summary = null, submitted_by_device_id = null,
        submitted_at = null, updated_at = now(), version = version + 1
      where id = ${input.taskId}
      returning id, child_profile_id as "childProfileId", client_ref as "clientRef", title,
        title_english as "titleEnglish", status, growth_points as "growthPoints",
        requires_evidence as "requiresEvidence", planned_for::text as "plannedFor",
        evidence_summary as "evidenceSummary", task_payload as "taskPayload",
        delivery_status as "deliveryStatus", quarantine_reason as "quarantineReason",
        version, updated_at::text as "updatedAt"
    `;
    const updated = rows[0];
    if (!updated) throw new FamilyCloudError("task_not_withdrawable");
    await tx`
      insert into platform_family_task_changes (family_id, child_profile_id, task_id, task_version, change_kind)
      values (${input.context.familyId}, ${input.context.childProfileId}, ${updated.id}, ${updated.version}, 'withdrawn')
      on conflict (task_id, task_version, child_profile_id) do nothing
    `;
    return updated;
  });
}

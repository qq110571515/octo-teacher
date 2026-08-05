import { randomBytes } from "node:crypto";
import { sha256 } from "../../auth/apple-identity.js";
import { platformDatabase } from "../../database/postgres.js";
import {
  authenticateGuardianToken,
  createGuardianSessionForAccountInTransaction,
  loadCurrentFamily,
} from "../family/postgres-family-cloud.js";
import { FamilyCloudError, type FamilyCloudSnapshot } from "../family/cloud-types.js";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 8;
const REQUEST_SECONDS = 10 * 60;

type LoginRequestState = {
  id: string;
  status: "pending" | "approved" | "consumed" | "expired" | "revoked";
  expiresAt: string;
  accountId?: string;
  deviceRefHash: string;
  deviceName: string;
};

export type EmailDeviceAuthorizationStart = {
  code: string;
  requestToken: string;
  verificationURL: string;
  expiresAt: string;
};

export type EmailDeviceAuthorizationExchange =
  | { status: "pending" }
  | {
      status: "complete";
      sessionToken: string;
      expiresAt: string;
      guardian: { id: string; displayName?: string };
      family?: FamilyCloudSnapshot;
    };

function safeDeviceRef(value: unknown): string {
  if (typeof value !== "string") throw new FamilyCloudError("invalid_device_ref");
  const normalized = value.trim();
  if (!/^[A-Za-z0-9:_-]{8,160}$/.test(normalized)) throw new FamilyCloudError("invalid_device_ref");
  return normalized;
}

function safeDeviceName(value: unknown): string {
  if (typeof value !== "string") throw new FamilyCloudError("invalid_device_name");
  const normalized = value.trim();
  if (!normalized || normalized.length > 120) throw new FamilyCloudError("invalid_device_name");
  return normalized;
}

function randomCode(): string {
  const bytes = randomBytes(CODE_LENGTH);
  const raw = Array.from(bytes, (byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
  return `${raw.slice(0, 4)}-${raw.slice(4)}`;
}

export function normalizeEmailDeviceCode(value: unknown): string {
  if (typeof value !== "string") throw new FamilyCloudError("invalid_email_device_code");
  const normalized = value.toUpperCase().replace(/[\s-]/g, "");
  const pattern = new RegExp(`^[${CODE_ALPHABET}]{${CODE_LENGTH}}$`);
  if (!pattern.test(normalized)) throw new FamilyCloudError("invalid_email_device_code");
  return normalized;
}

export function resolveEmailDeviceExchange(
  state: Pick<LoginRequestState, "status" | "expiresAt" | "accountId">,
  now = new Date(),
): "pending" | "exchange" {
  if (Date.parse(state.expiresAt) <= now.getTime()) throw new FamilyCloudError("email_device_code_expired");
  if (state.status === "pending") return "pending";
  if (state.status === "approved" && state.accountId) return "exchange";
  throw new FamilyCloudError("email_device_code_unavailable");
}

export async function startEmailDeviceAuthorization(input: {
  devicePublicRef: unknown;
  deviceName: unknown;
}): Promise<EmailDeviceAuthorizationStart> {
  const sql = platformDatabase();
  const deviceRef = safeDeviceRef(input.devicePublicRef);
  const deviceName = safeDeviceName(input.deviceName);
  const deviceHash = sha256(deviceRef);
  const recent = await sql<{ count: number }[]>`
    select count(*)::int as count from platform_mobile_login_requests
    where device_ref_hash = ${deviceHash} and created_at > now() - interval '1 minute'
  `;
  if ((recent[0]?.count ?? 0) >= 5) throw new FamilyCloudError("email_device_rate_limited");

  const code = randomCode();
  const requestToken = randomBytes(48).toString("base64url");
  const rows = await sql<{ expiresAt: string }[]>`
    insert into platform_mobile_login_requests (
      code_hash, request_token_hash, device_ref_hash, device_name, expires_at
    ) values (
      ${sha256(normalizeEmailDeviceCode(code))}, ${sha256(requestToken)}, ${deviceHash}, ${deviceName},
      now() + (${REQUEST_SECONDS} * interval '1 second')
    ) returning expires_at::text as "expiresAt"
  `;
  return {
    code,
    requestToken,
    verificationURL: `https://octoteacher.com/family?app_code=${encodeURIComponent(code)}`,
    expiresAt: rows[0]?.expiresAt ?? new Date(Date.now() + REQUEST_SECONDS * 1_000).toISOString(),
  };
}

export async function approveEmailDeviceAuthorization(code: unknown, accountId: string): Promise<void> {
  const sql = platformDatabase();
  const codeHash = sha256(normalizeEmailDeviceCode(code));
  await sql.begin(async (tx) => {
    const rows = await tx<LoginRequestState[]>`
      select id, status, expires_at::text as "expiresAt",
        approved_by_account_id as "accountId", device_ref_hash as "deviceRefHash",
        device_name as "deviceName"
      from platform_mobile_login_requests where code_hash = ${codeHash} for update
    `;
    const state = rows[0];
    if (!state) throw new FamilyCloudError("email_device_code_not_found");
    if (state.status === "approved" && state.accountId === accountId && Date.parse(state.expiresAt) > Date.now()) return;
    if (state.status !== "pending") throw new FamilyCloudError("email_device_code_unavailable");
    if (Date.parse(state.expiresAt) <= Date.now()) throw new FamilyCloudError("email_device_code_expired");
    await tx`
      update platform_mobile_login_requests
      set status = 'approved', approved_by_account_id = ${accountId}, approved_at = now()
      where id = ${state.id}
    `;
  });
}

export async function exchangeEmailDeviceAuthorization(input: {
  requestToken: unknown;
  devicePublicRef: unknown;
  consentVersion: unknown;
  familySyncAccepted: unknown;
  childTaskSyncAccepted: unknown;
}): Promise<EmailDeviceAuthorizationExchange> {
  if (typeof input.requestToken !== "string" || input.requestToken.length < 32 || input.requestToken.length > 512) {
    throw new FamilyCloudError("invalid_email_device_request");
  }
  const deviceRef = safeDeviceRef(input.devicePublicRef);
  if (input.consentVersion !== "2026-07-family-sync-v1" ||
      input.familySyncAccepted !== true || input.childTaskSyncAccepted !== true) {
    throw new FamilyCloudError("guardian_consent_required");
  }
  const sql = platformDatabase();
  const result = await sql.begin(async (tx) => {
    const rows = await tx<LoginRequestState[]>`
      select id, status, expires_at::text as "expiresAt",
        approved_by_account_id as "accountId", device_ref_hash as "deviceRefHash",
        device_name as "deviceName"
      from platform_mobile_login_requests
      where request_token_hash = ${sha256(input.requestToken as string)}
      for update
    `;
    const state = rows[0];
    if (!state || state.deviceRefHash !== sha256(deviceRef)) {
      throw new FamilyCloudError("invalid_email_device_request");
    }
    if (resolveEmailDeviceExchange(state) === "pending") return { status: "pending" as const };
    const session = await createGuardianSessionForAccountInTransaction(tx, {
      accountId: state.accountId as string,
      devicePublicRef: deviceRef,
      deviceName: state.deviceName,
      consentVersion: input.consentVersion as string,
      familySyncAccepted: true,
      childTaskSyncAccepted: true,
    });
    await tx`
      update platform_mobile_login_requests set status = 'consumed', consumed_at = now()
      where id = ${state.id} and status = 'approved'
    `;
    return { status: "complete" as const, ...session };
  });
  if (result.status === "pending") return result;
  const context = await authenticateGuardianToken(result.sessionToken);
  const family = context ? await loadCurrentFamily(context) : undefined;
  return { ...result, ...(family ? { family } : {}) };
}

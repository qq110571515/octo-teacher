import { randomBytes, randomUUID } from "node:crypto";
import { platformDatabase } from "../../database/postgres.js";
import { sha256, type SupabaseAccountIdentity } from "../../auth/supabase-account-identity.js";

export type PlatformAccountStatus = "pending" | "active" | "suspended" | "deleted";

export type PlatformAccountSummary = {
  publicRef: string;
  handle: string;
  displayName: string;
  maskedEmail?: string;
  status: PlatformAccountStatus;
  createdAt: string;
};

export type ActivePlatformAccountIdentity = {
  id: string;
  publicRef: string;
};

function safeHandle(email: string): string {
  const stem = email.split("@")[0].toLowerCase().replace(/[^a-z0-9_]/g, "").slice(0, 20) || "family";
  return `${stem}_${randomBytes(3).toString("hex")}`;
}

function toSummary(row: Record<string, unknown>): PlatformAccountSummary {
  return {
    publicRef: String(row.public_ref),
    handle: String(row.handle),
    displayName: String(row.display_name),
    maskedEmail: row.email_masked ? String(row.email_masked) : undefined,
    status: String(row.status) as PlatformAccountStatus,
    createdAt: new Date(String(row.created_at)).toISOString(),
  };
}

export async function loadAccountForIdentity(
  identity: SupabaseAccountIdentity,
): Promise<PlatformAccountSummary | undefined> {
  const sql = platformDatabase();
  const rows = await sql`
    select a.public_ref, a.handle, a.display_name, a.email_masked, a.status, a.created_at
    from platform_account_identities i
    join platform_accounts a on a.id = i.account_id
    where i.provider = 'email_magic_link'
      and i.provider_subject = ${identity.subject}
      and i.status = 'active'
      and a.status <> 'deleted'
    limit 1
  `;
  return rows[0] ? toSummary(rows[0]) : undefined;
}

export async function loadActivePlatformAccountIdentity(
  identity: SupabaseAccountIdentity,
): Promise<ActivePlatformAccountIdentity | undefined> {
  const sql = platformDatabase();
  const rows = await sql<ActivePlatformAccountIdentity[]>`
    select a.id, a.public_ref as "publicRef"
    from platform_account_identities i
    join platform_accounts a on a.id = i.account_id
    where i.provider = 'email_magic_link'
      and i.provider_subject = ${identity.subject}
      and i.status = 'active'
      and a.status = 'active'
    limit 1
  `;
  return rows[0];
}

export async function bootstrapPendingAccount(
  identity: SupabaseAccountIdentity,
  input?: { handle?: string; displayName?: string },
): Promise<PlatformAccountSummary> {
  const existing = await loadAccountForIdentity(identity);
  if (existing) return existing;
  const sql = platformDatabase();
  const publicRef = `acct_${randomUUID().replace(/-/g, "").slice(0, 20)}`;
  const requestedHandle = input?.handle?.trim().toLowerCase().replace(/[^a-z0-9_]/g, "").slice(0, 28);
  const handle = requestedHandle && requestedHandle.length >= 3 ? requestedHandle : safeHandle(identity.email);
  const displayName = input?.displayName?.trim().slice(0, 60) || handle;
  const status: PlatformAccountStatus = identity.isOwnerApprover ? "active" : "pending";
  const rows = await sql.begin(async (transaction) => {
    const inserted = await transaction`
      insert into platform_accounts (public_ref, handle, display_name, email_hash, email_masked, status)
      values (${publicRef}, ${handle}, ${displayName}, ${identity.emailHash}, ${identity.maskedEmail}, ${status})
      returning id, public_ref, handle, display_name, email_masked, status, created_at
    `;
    await transaction`
      insert into platform_account_identities
        (account_id, provider, provider_subject, status, verified_at, last_used_at)
      values (${inserted[0].id}, 'email_magic_link', ${identity.subject}, 'active', now(), now())
    `;
    await transaction`
      insert into platform_account_approval_audit (account_id, action, actor_subject_hash, reason)
      values (
        ${inserted[0].id},
        ${identity.isOwnerApprover ? "approved" : "requested"},
        ${sha256(identity.subject)},
        ${identity.isOwnerApprover ? "owner_bootstrap" : "closed_beta_registration"}
      )
    `;
    return inserted;
  });
  return toSummary(rows[0]);
}

export async function listPendingAccounts(): Promise<PlatformAccountSummary[]> {
  const sql = platformDatabase();
  const rows = await sql`
    select public_ref, handle, display_name, email_masked, status, created_at
    from platform_accounts
    where status = 'pending'
    order by created_at asc
    limit 200
  `;
  return rows.map((row) => toSummary(row));
}

export async function setAccountApproval(
  publicRef: string,
  status: "active" | "suspended",
  actorSubject: string,
): Promise<PlatformAccountSummary | undefined> {
  const sql = platformDatabase();
  const rows = await sql.begin(async (transaction) => {
    const updated = await transaction`
      update platform_accounts
      set status = ${status}, updated_at = now()
      where public_ref = ${publicRef} and status <> 'deleted'
      returning id, public_ref, handle, display_name, email_masked, status, created_at
    `;
    if (!updated[0]) return updated;
    await transaction`
      insert into platform_account_approval_audit (account_id, action, actor_subject_hash, reason)
      values (
        ${updated[0].id},
        ${status === "active" ? "approved" : "suspended"},
        ${sha256(actorSubject)},
        'owner_review'
      )
    `;
    return updated;
  });
  return rows[0] ? toSummary(rows[0]) : undefined;
}

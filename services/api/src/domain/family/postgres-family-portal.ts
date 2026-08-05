import { sha256 } from "../../auth/apple-identity.js";
import type { SupabaseAccountIdentity } from "../../auth/supabase-account-identity.js";
import { platformDatabase } from "../../database/postgres.js";
import { loadActivePlatformAccountIdentity } from "../accounts/postgres-platform-accounts.js";
import type { FamilyConsole, GuardianSessionContext } from "./cloud-types.js";
import { FamilyCloudError } from "./cloud-types.js";
import {
  generatePortalLinkCode,
  portalLinkCodeHash,
  resolveAccountIdentityLink,
  resolvePortalLinkClaim,
} from "./family-portal.js";
import {
  buildPortalActivityByChild,
  emptyPortalChildActivity,
  type PortalActivityAppDailyRow,
  type PortalActivityDailyRow,
  type PortalActivityRecentRow,
  type PortalActivitySummaryRow,
} from "./family-portal-activity.js";
import { linkAccountToGuardianInTransaction } from "./guardian-identity.js";
import {
  deleteFamilyData,
  loadFamilyConsole,
  revokeFamilyDevice,
} from "./postgres-family-cloud.js";
import {
  renameFamily,
  revokeFamilyGuardian,
} from "./postgres-family-control.js";

const PORTAL_LINK_SECONDS = 10 * 60;

export type LinkedGuardian = {
  guardianId: string;
  familyId: string;
};

async function familyConsoleForLinkedGuardian(
  link: LinkedGuardian,
  timeZone = "UTC",
): Promise<FamilyConsole> {
  const context: GuardianSessionContext = {
    sessionId: "portal-account",
    guardianId: link.guardianId,
    devicePublicRef: "portal-account",
  };
  const [console, activityRows] = await Promise.all([
    tracePortalConsoleStage("console", () => loadFamilyConsole(context, link.familyId)),
    tracePortalConsoleStage("activity", () => loadFamilyPortalActivity(link.familyId, timeZone)),
  ]);
  const activityByChild = buildPortalActivityByChild(
    activityRows.summary,
    activityRows.recent,
    activityRows.daily,
    activityRows.appDaily,
  );
  return {
    ...console,
    children: console.children.map((child) => {
      return {
        ...child,
        activity: activityByChild.get(child.id) ?? emptyPortalChildActivity(),
      };
    }),
  };
}

async function tracePortalConsoleStage<T>(stage: string, operation: () => Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    const detail = error && typeof error === "object"
      ? error as Record<string, unknown>
      : {};
    console.error("portal_console_stage_failed", {
      stage,
      name: error instanceof Error ? error.name : typeof error,
      code: typeof detail.code === "string" ? detail.code : undefined,
    });
    throw error;
  }
}

type FamilyPortalActivityRows = {
  summary: PortalActivitySummaryRow[];
  recent: PortalActivityRecentRow[];
  daily: PortalActivityDailyRow[];
  appDaily: PortalActivityAppDailyRow[];
};

async function loadFamilyPortalActivity(
  familyId: string,
  timeZone: string,
): Promise<FamilyPortalActivityRows> {
  const sql = platformDatabase();
  const [summary, recent, daily, appDaily] = await Promise.all([
    sql<PortalActivitySummaryRow[]>`
      select child_profile_id as "childProfileId", kind,
        coalesce(sum(duration_seconds), 0)::int as "durationSeconds"
      from platform_family_activity_events
      where family_id = ${familyId}
        and occurred_at >= now() - interval '90 days'
      group by child_profile_id, kind
    `,
    sql<PortalActivityRecentRow[]>`
      select id as "eventId", child_profile_id as "childProfileId", kind,
        occurred_at::text as "occurredAt", duration_seconds as "durationSeconds",
        progress_percent as "progressPercent", display_name as "displayName",
        resource_ref as "resourceRef"
      from (
        select *,
          row_number() over (
            partition by child_profile_id
            order by occurred_at desc, id desc
          ) as child_rank
        from platform_family_activity_events
        where family_id = ${familyId}
          and occurred_at >= now() - interval '90 days'
      ) ranked
      where child_rank <= 20
      order by occurred_at desc, id desc
    `,
    sql<PortalActivityDailyRow[]>`
      select child_profile_id as "childProfileId",
        (occurred_at at time zone ${timeZone})::date::text as date,
        coalesce(sum(duration_seconds), 0)::int as "durationSeconds",
        count(*)::int as "eventCount"
      from platform_family_activity_events
      where family_id = ${familyId}
        and kind = 'screen_time'
        and occurred_at >= now() - interval '31 days'
      group by 1, 2
      order by date desc, child_profile_id
    `,
    sql<PortalActivityAppDailyRow[]>`
      select child_profile_id as "childProfileId",
        (occurred_at at time zone ${timeZone})::date::text as date,
        resource_ref as "resourceRef",
        coalesce(sum(duration_seconds), 0)::int as "durationSeconds",
        count(*)::int as "eventCount"
      from platform_family_activity_events
      where family_id = ${familyId}
        and kind = 'screen_time'
        and occurred_at >= now() - interval '31 days'
        and resource_ref ~ '^authority:[a-z0-9_]+:app:[a-f0-9]{32}$'
      group by 1, 2, 3
      order by date desc, child_profile_id, resource_ref
    `,
  ]);
  return { summary, recent, daily, appDaily };
}

export async function issueFamilyPortalLink(input: {
  context: GuardianSessionContext;
  familyId: string;
}): Promise<{ code: string; expiresAt: string }> {
  const code = generatePortalLinkCode();
  const sql = platformDatabase();
  const expiresAt = await sql.begin(async (tx) => {
    const memberships = await tx<{ familyId: string }[]>`
      select m.family_id as "familyId"
      from platform_family_guardians m
      join platform_families f on f.id = m.family_id
      where m.guardian_id = ${input.context.guardianId}
        and m.family_id = ${input.familyId}
        and m.status = 'active'
        and f.status = 'active'
      for update of m
    `;
    if (!memberships[0]) throw new FamilyCloudError("family_access_denied");
    await tx`
      update platform_family_portal_link_codes
      set status = 'revoked'
      where guardian_id = ${input.context.guardianId}
        and family_id = ${input.familyId}
        and status = 'issued'
    `;
    const rows = await tx<{ expiresAt: string }[]>`
      insert into platform_family_portal_link_codes (
        family_id, guardian_id, code_hash, expires_at
      ) values (
        ${input.familyId}, ${input.context.guardianId}, ${portalLinkCodeHash(code)},
        now() + (${PORTAL_LINK_SECONDS} * interval '1 second')
      )
      returning expires_at::text as "expiresAt"
    `;
    await tx`
      insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref, detail)
      values (
        ${input.familyId}, 'family_portal_link_issued', 'guardian', ${sha256(input.context.guardianId)},
        null, ${tx.json({ expiresInSeconds: PORTAL_LINK_SECONDS })}
      )
    `;
    return rows[0]?.expiresAt;
  });
  if (!expiresAt) throw new FamilyCloudError("portal_link_issue_failed");
  return { code, expiresAt: new Date(expiresAt).toISOString() };
}

async function activeAccount(identity: SupabaseAccountIdentity): Promise<{ id: string; publicRef: string }> {
  const account = await loadActivePlatformAccountIdentity(identity);
  if (!account) throw new FamilyCloudError("portal_account_not_active");
  return account;
}

export async function claimFamilyPortalLink(
  identity: SupabaseAccountIdentity,
  code: unknown,
): Promise<FamilyConsole> {
  const account = await activeAccount(identity);
  const codeHash = portalLinkCodeHash(code);
  const sql = platformDatabase();
  const linked = await sql.begin(async (tx): Promise<LinkedGuardian> => {
    const rows = await tx<{
      id: string;
      familyId: string;
      guardianId: string;
      status: "issued" | "consumed" | "revoked" | "expired";
      expiresAt: string;
      consumedByAccountId?: string;
      guardianAccountId?: string;
      guardianAppleSubject: string;
    }[]>`
      select c.id, c.family_id as "familyId", c.guardian_id as "guardianId", c.status,
        c.expires_at::text as "expiresAt", c.consumed_by_account_id as "consumedByAccountId",
        g.account_id as "guardianAccountId", g.external_subject as "guardianAppleSubject"
      from platform_family_portal_link_codes c
      join platform_guardian_accounts g on g.id = c.guardian_id and g.status = 'active'
      join platform_family_guardians m on m.family_id = c.family_id and m.guardian_id = c.guardian_id
      join platform_families f on f.id = c.family_id
      where c.code_hash = ${codeHash}
        and m.status = 'active'
        and f.status = 'active'
      for update of c, g
    `;
    const row = rows[0];
    const decision = resolvePortalLinkClaim(row, account.id);
    if (!row) throw new FamilyCloudError("portal_link_not_found");
    if (row.guardianAccountId && row.guardianAccountId !== account.id) {
      throw new FamilyCloudError("portal_guardian_already_linked");
    }
    const isAppleGuardian = !row.guardianAppleSubject.startsWith("email-account:");
    const appleIdentities = isAppleGuardian
      ? await tx<{ accountId: string }[]>`
          select account_id as "accountId"
          from platform_account_identities
          where provider = 'apple' and provider_subject = ${row.guardianAppleSubject}
          for update
        `
      : [];
    const appleIdentityDecision = isAppleGuardian
      ? resolveAccountIdentityLink(appleIdentities[0]?.accountId, account.id)
      : undefined;
    await linkAccountToGuardianInTransaction(tx, {
      accountId: account.id,
      targetGuardianId: row.guardianId,
      requiredFamilyId: row.familyId,
    });
    if (decision === "consume") {
      await tx`
        update platform_family_portal_link_codes
        set status = 'consumed', consumed_by_account_id = ${account.id}, consumed_at = now()
        where id = ${row.id} and status = 'issued'
      `;
      await tx`
        insert into platform_family_audit (family_id, action, actor_kind, actor_ref_hash, target_public_ref, detail)
        values (
          ${row.familyId}, 'family_portal_link_claimed', 'guardian', ${sha256(row.guardianId)},
          ${account.publicRef}, '{}'::jsonb
        )
      `;
    }
    if (appleIdentityDecision === "insert") {
      await tx`
        insert into platform_account_identities (
          account_id, provider, provider_subject, status, verified_at, last_used_at
        ) values (
          ${account.id}, 'apple', ${row.guardianAppleSubject}, 'active', now(), now()
        )
      `;
    } else if (appleIdentityDecision === "refresh") {
      await tx`
        update platform_account_identities
        set status = 'active', verified_at = coalesce(verified_at, now()),
          last_used_at = now(), revoked_at = null
        where provider = 'apple'
          and provider_subject = ${row.guardianAppleSubject}
          and account_id = ${account.id}
      `;
    }
    return { guardianId: row.guardianId, familyId: row.familyId };
  });
  return familyConsoleForLinkedGuardian(linked);
}

export async function loadLinkedFamilyConsole(
  identity: SupabaseAccountIdentity,
  timeZone = "UTC",
): Promise<FamilyConsole> {
  const linked = await loadLinkedGuardian(identity);
  return familyConsoleForLinkedGuardian(linked, timeZone);
}

export async function loadLinkedGuardian(
  identity: SupabaseAccountIdentity,
): Promise<LinkedGuardian> {
  const account = await activeAccount(identity);
  const sql = platformDatabase();
  const rows = await sql<LinkedGuardian[]>`
    select g.id as "guardianId", m.family_id as "familyId"
    from platform_guardian_accounts g
    join platform_family_guardians m on m.guardian_id = g.id and m.status = 'active'
    join platform_families f on f.id = m.family_id and f.status = 'active'
    where g.account_id = ${account.id} and g.status = 'active'
    order by m.is_creator desc, m.joined_at nulls last
    limit 2
  `;
  if (!rows[0]) throw new FamilyCloudError("portal_family_not_linked");
  if (rows.length > 1) throw new FamilyCloudError("guardian_multiple_active_families");
  return rows[0];
}

function portalGuardianContext(link: LinkedGuardian): GuardianSessionContext {
  return {
    sessionId: "portal-account",
    guardianId: link.guardianId,
    devicePublicRef: "portal-account",
  };
}

export async function renameLinkedFamily(
  identity: SupabaseAccountIdentity,
  displayName: unknown,
): Promise<{ id: string; publicRef: string; displayName: string; syncVersion: number }> {
  const link = await loadLinkedGuardian(identity);
  return renameFamily({
    context: portalGuardianContext(link),
    familyId: link.familyId,
    displayName,
  });
}

export async function revokeLinkedFamilyDevice(
  identity: SupabaseAccountIdentity,
  deviceId: string,
): Promise<{ revoked: boolean }> {
  const link = await loadLinkedGuardian(identity);
  await revokeFamilyDevice({
    context: portalGuardianContext(link),
    familyId: link.familyId,
    deviceId,
  });
  return { revoked: true };
}

export async function revokeLinkedFamilyGuardian(
  identity: SupabaseAccountIdentity,
  guardianId: string,
): Promise<{ revoked: boolean }> {
  const link = await loadLinkedGuardian(identity);
  return revokeFamilyGuardian({
    context: portalGuardianContext(link),
    familyId: link.familyId,
    guardianId,
  });
}

export async function deleteLinkedFamily(
  identity: SupabaseAccountIdentity,
  confirmation: unknown,
): Promise<{ receiptId: string; deletedAt: string }> {
  const link = await loadLinkedGuardian(identity);
  return deleteFamilyData({
    context: portalGuardianContext(link),
    familyId: link.familyId,
    confirmation,
  });
}

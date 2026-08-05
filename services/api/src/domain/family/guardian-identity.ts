import type { TransactionSql } from "postgres";
import { FamilyCloudError } from "./cloud-types.js";

type GuardianIdentityRow = {
  id: string;
  externalSubject: string;
  displayName?: string;
  accountId?: string;
  status: string;
};

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

export function requireCompatibleGuardianFamilies(
  targetFamilyIds: string[],
  aliasFamilyIds: string[],
  requiredFamilyId?: string,
): void {
  const activeFamilyIds = unique([...targetFamilyIds, ...aliasFamilyIds]);
  if (activeFamilyIds.length > 1) {
    throw new FamilyCloudError("guardian_identity_family_conflict");
  }
  if (requiredFamilyId && activeFamilyIds.some((familyId) => familyId !== requiredFamilyId)) {
    throw new FamilyCloudError("guardian_identity_family_conflict");
  }
}

async function activeFamilyIds(tx: TransactionSql, guardianId: string): Promise<string[]> {
  const rows = await tx<{ familyId: string }[]>`
    select m.family_id as "familyId"
    from platform_family_guardians m
    join platform_families f on f.id = m.family_id and f.status = 'active'
    where m.guardian_id = ${guardianId} and m.status = 'active'
    order by m.created_at
    for update of m
  `;
  return rows.map((row) => row.familyId);
}

async function retireEmailGuardianAlias(
  tx: TransactionSql,
  target: GuardianIdentityRow,
  alias: GuardianIdentityRow,
  requiredFamilyId?: string,
): Promise<void> {
  if (!alias.externalSubject.startsWith("email-account:")) {
    throw new FamilyCloudError("guardian_identity_account_conflict");
  }
  const [targetFamilyIds, aliasFamilyIds] = await Promise.all([
    activeFamilyIds(tx, target.id),
    activeFamilyIds(tx, alias.id),
  ]);
  requireCompatibleGuardianFamilies(targetFamilyIds, aliasFamilyIds, requiredFamilyId);

  await tx`
    insert into platform_family_guardians (
      family_id, guardian_id, membership_role, is_creator, status, joined_at, created_at
    )
    select family_id, ${target.id}, membership_role, is_creator, status, joined_at, created_at
    from platform_family_guardians
    where guardian_id = ${alias.id} and status = 'active'
    on conflict (family_id, guardian_id) do update set
      is_creator = platform_family_guardians.is_creator or excluded.is_creator,
      status = 'active',
      joined_at = coalesce(
        least(platform_family_guardians.joined_at, excluded.joined_at),
        platform_family_guardians.joined_at,
        excluded.joined_at,
        now()
      ),
      revoked_at = null,
      updated_at = now()
  `;
  await tx`
    update platform_families
    set created_by_guardian_id = ${target.id}, updated_at = now()
    where created_by_guardian_id = ${alias.id}
  `;
  await tx`
    update platform_family_devices
    set guardian_id = ${target.id}, updated_at = now()
    where guardian_id = ${alias.id} and role = 'guardian'
  `;
  await tx`
    insert into platform_guardian_consents (
      guardian_id, consent_version, family_sync_accepted, child_task_sync_accepted,
      accepted_at, revoked_at
    )
    select ${target.id}, consent_version, family_sync_accepted, child_task_sync_accepted,
      accepted_at, revoked_at
    from platform_guardian_consents
    where guardian_id = ${alias.id}
    on conflict (guardian_id, consent_version) do update set
      family_sync_accepted = platform_guardian_consents.family_sync_accepted or excluded.family_sync_accepted,
      child_task_sync_accepted = platform_guardian_consents.child_task_sync_accepted or excluded.child_task_sync_accepted,
      accepted_at = greatest(platform_guardian_consents.accepted_at, excluded.accepted_at),
      revoked_at = case
        when platform_guardian_consents.revoked_at is null or excluded.revoked_at is null then null
        else greatest(platform_guardian_consents.revoked_at, excluded.revoked_at)
      end
  `;
  await tx`
    update platform_family_guardians
    set status = 'revoked', revoked_at = now(), updated_at = now()
    where guardian_id = ${alias.id} and status <> 'revoked'
  `;
  await tx`
    update platform_guardian_sessions
    set revoked_at = now()
    where guardian_id = ${alias.id} and revoked_at is null
  `;
  await tx`
    update platform_guardian_accounts
    set account_id = null, status = 'deleted', updated_at = now()
    where id = ${alias.id}
  `;
}

export async function linkAccountToGuardianInTransaction(
  tx: TransactionSql,
  input: {
    accountId: string;
    targetGuardianId: string;
    requiredFamilyId?: string;
  },
): Promise<{ id: string; displayName?: string }> {
  await tx`select pg_advisory_xact_lock(hashtextextended(${`guardian-account:${input.accountId}`}, 0))`;
  const targets = await tx<GuardianIdentityRow[]>`
    select id, external_subject as "externalSubject", display_name as "displayName",
      account_id as "accountId", status
    from platform_guardian_accounts
    where id = ${input.targetGuardianId}
    for update
  `;
  const target = targets[0];
  if (!target || target.status !== "active") throw new FamilyCloudError("guardian_account_inactive");
  if (target.accountId && target.accountId !== input.accountId) {
    throw new FamilyCloudError("guardian_identity_account_conflict");
  }

  const aliases = await tx<GuardianIdentityRow[]>`
    select id, external_subject as "externalSubject", display_name as "displayName",
      account_id as "accountId", status
    from platform_guardian_accounts
    where account_id = ${input.accountId} and id <> ${target.id}
    for update
  `;
  if (aliases.length > 1) throw new FamilyCloudError("guardian_identity_account_conflict");
  if (aliases[0]) {
    await retireEmailGuardianAlias(tx, target, aliases[0], input.requiredFamilyId);
  }
  await tx`
    update platform_guardian_accounts
    set account_id = ${input.accountId}, updated_at = now()
    where id = ${target.id}
  `;
  return { id: target.id, ...(target.displayName ? { displayName: target.displayName } : {}) };
}

export async function guardianForAccountInTransaction(
  tx: TransactionSql,
  input: { accountId: string; displayName: string },
): Promise<{ id: string; displayName?: string }> {
  const appleGuardians = await tx<GuardianIdentityRow[]>`
    select g.id, g.external_subject as "externalSubject", g.display_name as "displayName",
      g.account_id as "accountId", g.status
    from platform_account_identities i
    join platform_guardian_accounts g
      on g.external_subject = i.provider_subject and g.status = 'active'
    where i.account_id = ${input.accountId}
      and i.provider = 'apple'
      and i.status = 'active'
    order by i.last_used_at desc nulls last, i.created_at
    limit 2
    for update of i, g
  `;
  if (appleGuardians.length > 1) throw new FamilyCloudError("guardian_identity_account_conflict");
  if (appleGuardians[0]) {
    return linkAccountToGuardianInTransaction(tx, {
      accountId: input.accountId,
      targetGuardianId: appleGuardians[0].id,
    });
  }

  const linked = await tx<GuardianIdentityRow[]>`
    select id, external_subject as "externalSubject", display_name as "displayName",
      account_id as "accountId", status
    from platform_guardian_accounts
    where account_id = ${input.accountId} and status = 'active'
    for update
  `;
  if (linked.length > 1) throw new FamilyCloudError("guardian_identity_account_conflict");
  if (linked[0]) {
    return { id: linked[0].id, ...(linked[0].displayName ? { displayName: linked[0].displayName } : {}) };
  }

  const created = await tx<{ id: string; displayName?: string }[]>`
    insert into platform_guardian_accounts (external_subject, display_name, account_id)
    values (${`email-account:${input.accountId}`}, ${input.displayName}, ${input.accountId})
    on conflict (external_subject) do update set
      display_name = coalesce(platform_guardian_accounts.display_name, excluded.display_name),
      account_id = excluded.account_id,
      status = 'active',
      updated_at = now()
    returning id, display_name as "displayName"
  `;
  if (!created[0]) throw new FamilyCloudError("guardian_session_create_failed");
  return created[0];
}

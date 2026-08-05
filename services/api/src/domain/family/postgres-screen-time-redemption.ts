import { sha256 } from "../../auth/apple-identity.js";
import { platformDatabase } from "../../database/postgres.js";
import {
  FamilyCloudError,
  type ChildDeviceSessionContext,
  type ScreenTimeRedemptionReservation,
} from "./cloud-types.js";
import {
  normalizeScreenTimeStatus,
  normalizeStoredScreenTimePolicy,
} from "./postgres-family-cloud.js";
import {
  assertCurrentScreenTimeRedemption,
  assertCurrentScreenTimeRedemptionAuthority,
  normalizeScreenTimeRedemptionReceipt,
  type ScreenTimeRedemptionReceipt,
} from "./screen-time-redemption.js";

type RedemptionRow = {
  id: string;
  redemptionRef: string;
  receiptHash: string;
  state: ScreenTimeRedemptionReservation["state"];
  points: number;
  expiresAt: string;
  policyRevision: number;
  selectionHash: string;
  controlCommandId: string;
  targetTokenHash: string;
  unlockUntil: string;
  policy: unknown;
  status: unknown;
  balance: number;
};

function receiptHash(receipt: ScreenTimeRedemptionReceipt): string {
  return sha256(JSON.stringify(receipt));
}

function reservationResult(row: RedemptionRow): ScreenTimeRedemptionReservation {
  return {
    id: row.id,
    redemptionRef: row.redemptionRef,
    state: row.state,
    points: row.points,
    expiresAt: new Date(row.expiresAt).toISOString(),
    balance: row.balance,
  };
}

function assertMatchingReceipt(row: RedemptionRow, receipt: ScreenTimeRedemptionReceipt): void {
  if (row.receiptHash !== receiptHash(receipt) ||
      row.redemptionRef !== receipt.redemptionRef ||
      row.points !== receipt.points ||
      row.policyRevision !== receipt.policyRevision ||
      row.selectionHash !== receipt.selectionHash ||
      row.controlCommandId !== receipt.controlCommandId ||
      row.targetTokenHash !== receipt.targetTokenHash ||
      new Date(row.unlockUntil).toISOString() !== new Date(receipt.unlockUntil).toISOString()) {
    throw new FamilyCloudError("screen_time_redemption_ref_conflict");
  }
}

export async function reserveScreenTimeRedemption(input: {
  context: ChildDeviceSessionContext;
  receipt: unknown;
}): Promise<ScreenTimeRedemptionReservation> {
  const receipt = normalizeScreenTimeRedemptionReceipt(input.receipt);
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    await tx`
      update platform_screen_time_redemptions
      set state = 'expired', updated_at = now()
      where child_profile_id = ${input.context.childProfileId}
        and state = 'reserved' and expires_at <= now()
    `;
    const existing = await tx<RedemptionRow[]>`
      select r.id, r.redemption_ref::text as "redemptionRef", r.receipt_hash as "receiptHash",
        r.state, r.points, r.expires_at::text as "expiresAt",
        r.policy_revision as "policyRevision", r.selection_hash as "selectionHash",
        r.control_command_id as "controlCommandId", r.target_token_hash as "targetTokenHash",
        r.unlock_until::text as "unlockUntil", c.screen_time_policy as policy,
        c.screen_time_status as status, c.growth_point_balance as balance
      from platform_screen_time_redemptions r
      join platform_child_profiles c on c.id = r.child_profile_id
      where r.family_id = ${input.context.familyId}
        and r.child_profile_id = ${input.context.childProfileId}
        and r.device_id = ${input.context.deviceId}
        and r.redemption_ref = ${receipt.redemptionRef}::uuid
      for update of r, c
    `;
    if (existing[0]) {
      assertMatchingReceipt(existing[0], receipt);
      return reservationResult(existing[0]);
    }

    const children = await tx<Array<{ policy: unknown; status: unknown; balance: number }>>`
      select c.screen_time_policy as policy, c.screen_time_status as status,
        c.growth_point_balance as balance
      from platform_child_profiles c
      join platform_family_devices d on d.id = ${input.context.deviceId}
        and d.family_id = c.family_id and d.child_profile_id = c.id
        and d.role = 'child' and d.status = 'active'
      where c.id = ${input.context.childProfileId}
        and c.family_id = ${input.context.familyId} and c.status = 'active'
      for update of c, d
    `;
    const child = children[0];
    if (!child) throw new FamilyCloudError("child_profile_not_found");
    const policy = child.policy === null || child.policy === undefined
      ? undefined : normalizeStoredScreenTimePolicy(child.policy);
    const status = child.status === null || child.status === undefined
      ? undefined : normalizeScreenTimeStatus(child.status);
    assertCurrentScreenTimeRedemption(receipt, policy, status);

    const reservations = await tx<Array<{ points: number }>>`
      select coalesce(sum(points), 0)::integer as points
      from platform_screen_time_redemptions
      where child_profile_id = ${input.context.childProfileId}
        and state = 'reserved' and expires_at > now()
    `;
    const reservedPoints = reservations[0]?.points ?? 0;
    if (child.balance - reservedPoints < receipt.points) {
      throw new FamilyCloudError("insufficient_growth_points");
    }

    const rows = await tx<RedemptionRow[]>`
      insert into platform_screen_time_redemptions (
        family_id, child_profile_id, device_id, redemption_ref, receipt_hash,
        points, minutes, policy_revision, selection_hash, control_command_id,
        target_token_hash, unlock_until, expires_at
      ) values (
        ${input.context.familyId}, ${input.context.childProfileId}, ${input.context.deviceId},
        ${receipt.redemptionRef}::uuid, ${receiptHash(receipt)}, ${receipt.points},
        ${receipt.minutes}, ${receipt.policyRevision}, ${receipt.selectionHash},
        ${receipt.controlCommandId}, ${receipt.targetTokenHash}, ${receipt.unlockUntil}::timestamptz,
        now() + interval '5 minutes'
      )
      returning id, redemption_ref::text as "redemptionRef", receipt_hash as "receiptHash",
        state, points, expires_at::text as "expiresAt", policy_revision as "policyRevision",
        selection_hash as "selectionHash", control_command_id as "controlCommandId",
        target_token_hash as "targetTokenHash", unlock_until::text as "unlockUntil",
        null::jsonb as policy, null::jsonb as status, ${child.balance}::integer as balance
    `;
    const row = rows[0];
    if (!row) throw new FamilyCloudError("screen_time_redemption_reserve_failed");
    return reservationResult(row);
  });
}

async function loadRedemptionForUpdate(
  tx: any,
  context: ChildDeviceSessionContext,
  redemptionId: string,
): Promise<RedemptionRow> {
  if (!/^[0-9a-f-]{36}$/i.test(redemptionId)) {
    throw new FamilyCloudError("invalid_screen_time_redemption_id");
  }
  const rows = await tx<RedemptionRow[]>`
    select r.id, r.redemption_ref::text as "redemptionRef", r.receipt_hash as "receiptHash",
      r.state, r.points, r.expires_at::text as "expiresAt",
      r.policy_revision as "policyRevision", r.selection_hash as "selectionHash",
      r.control_command_id as "controlCommandId", r.target_token_hash as "targetTokenHash",
      r.unlock_until::text as "unlockUntil", c.screen_time_policy as policy,
      c.screen_time_status as status, c.growth_point_balance as balance
    from platform_screen_time_redemptions r
    join platform_child_profiles c on c.id = r.child_profile_id
    where r.id = ${redemptionId}::uuid and r.family_id = ${context.familyId}
      and r.child_profile_id = ${context.childProfileId} and r.device_id = ${context.deviceId}
    for update of r, c
  `;
  const row = rows[0];
  if (!row) throw new FamilyCloudError("screen_time_redemption_not_found");
  return row;
}

export async function commitScreenTimeRedemption(input: {
  context: ChildDeviceSessionContext;
  redemptionId: string;
  receipt: unknown;
}): Promise<ScreenTimeRedemptionReservation> {
  const receipt = normalizeScreenTimeRedemptionReceipt(input.receipt);
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const row = await loadRedemptionForUpdate(tx, input.context, input.redemptionId);
    assertMatchingReceipt(row, receipt);
    if (row.state === "committed") return reservationResult(row);
    if (row.state !== "reserved") throw new FamilyCloudError("screen_time_redemption_not_reserved");
    if (new Date(row.expiresAt) <= new Date()) {
      await tx`update platform_screen_time_redemptions set state = 'expired', updated_at = now() where id = ${row.id}`;
      throw new FamilyCloudError("screen_time_redemption_expired");
    }
    const policy = normalizeStoredScreenTimePolicy(row.policy);
    const status = normalizeScreenTimeStatus(row.status);
    assertCurrentScreenTimeRedemptionAuthority(receipt, policy, status);
    const balanceAfter = row.balance - row.points;
    if (balanceAfter < 0) throw new FamilyCloudError("insufficient_growth_points");
    const sourceRef = `screen-time-session:${receipt.redemptionRef}`;
    await tx`
      insert into platform_family_growth_point_ledger (
        family_id, child_profile_id, entry_kind, delta, balance_after, mutation_ref, source_ref
      ) values (
        ${input.context.familyId}, ${input.context.childProfileId}, 'screen_time_spend',
        ${-row.points}, ${balanceAfter}, ${`spend:${sourceRef}`}, ${sourceRef}
      )
    `;
    await tx`
      update platform_child_profiles set growth_point_balance = ${balanceAfter}, updated_at = now()
      where id = ${input.context.childProfileId} and family_id = ${input.context.familyId}
    `;
    await tx`
      update platform_screen_time_redemptions
      set state = 'committed', committed_at = now(), updated_at = now()
      where id = ${row.id}
    `;
    return { ...reservationResult(row), state: "committed", balance: balanceAfter };
  });
}

export async function cancelScreenTimeRedemption(input: {
  context: ChildDeviceSessionContext;
  redemptionId: string;
}): Promise<ScreenTimeRedemptionReservation> {
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const row = await loadRedemptionForUpdate(tx, input.context, input.redemptionId);
    if (row.state === "reserved") {
      await tx`
        update platform_screen_time_redemptions
        set state = 'cancelled', cancelled_at = now(), updated_at = now()
        where id = ${row.id}
      `;
      return { ...reservationResult(row), state: "cancelled" };
    }
    return reservationResult(row);
  });
}

import { platformDatabase } from "../../database/postgres.js";
import { GuestbookError, guestbookContentHash } from "./guestbook.js";

export type PublicGuestbookMessage = {
  id: string;
  displayName: string;
  message: string;
  createdAt: string;
};

type GuestbookRow = {
  id: string;
  displayName: string;
  message: string;
  createdAt: string;
};

export async function listGuestbookMessages(limit = 24): Promise<PublicGuestbookMessage[]> {
  const safeLimit = Math.max(1, Math.min(limit, 50));
  const sql = platformDatabase();
  return sql<GuestbookRow[]>`
    select id::text, display_name as "displayName", message, created_at::text as "createdAt"
    from public_guestbook_messages
    where moderation_status = 'visible'
    order by created_at desc
    limit ${safeLimit}
  `;
}

export async function createGuestbookMessage(input: {
  displayName: string;
  message: string;
  ipHash: string;
}): Promise<PublicGuestbookMessage> {
  const sql = platformDatabase();
  return sql.begin(async (transaction) => {
    await transaction`select pg_advisory_xact_lock(hashtextextended(${input.ipHash}, 0))`;
    const [rate] = await transaction<Array<{ hourCount: number; dayCount: number }>>`
      select
        count(*) filter (where created_at > now() - interval '1 hour')::int as "hourCount",
        count(*) filter (where created_at > now() - interval '24 hours')::int as "dayCount"
      from public_guestbook_messages
      where ip_hash = ${input.ipHash}
    `;
    if ((rate?.hourCount ?? 0) >= 3 || (rate?.dayCount ?? 0) >= 10) {
      throw new GuestbookError("guestbook_rate_limited");
    }

    const contentHash = guestbookContentHash(input.message);
    const duplicate = await transaction<Array<{ exists: boolean }>>`
      select exists(
        select 1 from public_guestbook_messages
        where ip_hash = ${input.ipHash}
          and content_hash = ${contentHash}
          and created_at > now() - interval '24 hours'
      ) as "exists"
    `;
    if (duplicate[0]?.exists) throw new GuestbookError("guestbook_duplicate");

    const [created] = await transaction<GuestbookRow[]>`
      insert into public_guestbook_messages (display_name, message, ip_hash, content_hash)
      values (${input.displayName}, ${input.message}, ${input.ipHash}, ${contentHash})
      returning id::text, display_name as "displayName", message, created_at::text as "createdAt"
    `;
    if (!created) throw new Error("guestbook_insert_failed");
    return created;
  });
}

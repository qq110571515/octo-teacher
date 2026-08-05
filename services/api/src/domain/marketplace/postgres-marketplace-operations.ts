import { createHash } from "node:crypto";
import { platformDatabase } from "../../database/postgres.js";
import {
  MarketplaceSubmissionValidationError,
  parseMarketplaceSubmission,
  reviewStatus,
  type MarketplaceReviewDecision,
  type ParsedMarketplaceSubmission,
} from "./submission.js";

export type MarketplaceSubmissionSummary = {
  id: string;
  creatorId: string;
  listingId: string;
  version: string;
  status: string;
  submissionHash: string;
  submittedAt: string;
  reviewedAt?: string;
  publishedAt?: string;
};

type SubmissionRow = MarketplaceSubmissionSummary & {
  payload: unknown;
  reviewNotes?: string;
};

function actorHash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export async function createMarketplaceSubmission(
  parsed: ParsedMarketplaceSubmission,
): Promise<MarketplaceSubmissionSummary> {
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const creators = await tx<{ id: string }[]>`
      select id from marketplace_creators where id = ${parsed.creatorId} and status = 'active' limit 1
    `;
    if (!creators[0]) throw new MarketplaceSubmissionValidationError("creator_not_available");

    const rows = await tx<MarketplaceSubmissionSummary[]>`
      insert into marketplace_submissions (
        creator_id, listing_id, version, payload, status, terms_version, terms_accepted_at, submission_hash
      ) values (
        ${parsed.creatorId}, ${parsed.listing.id}, ${parsed.listing.version}, ${tx.json(parsed)}, 'submitted',
        ${parsed.termsVersion}, now(), ${parsed.submissionHash}
      )
      returning
        id, creator_id as "creatorId", listing_id as "listingId", version, status,
        submission_hash as "submissionHash", submitted_at as "submittedAt",
        reviewed_at as "reviewedAt", published_at as "publishedAt"
    `;
    const created = rows[0];
    if (!created) throw new Error("marketplace_submission_create_failed");
    await tx`
      insert into marketplace_submission_audit (
        submission_id, action, actor_type, actor_ref_hash, from_status, to_status
      ) values (${created.id}, 'submitted', 'creator', ${actorHash(parsed.creatorId)}, null, 'submitted')
    `;
    return created;
  });
}

export async function listMarketplaceSubmissions(): Promise<SubmissionRow[]> {
  const sql = platformDatabase();
  return sql<SubmissionRow[]>`
    select
      id, creator_id as "creatorId", listing_id as "listingId", version, status, payload,
      submission_hash as "submissionHash", review_notes as "reviewNotes",
      submitted_at as "submittedAt", reviewed_at as "reviewedAt", published_at as "publishedAt"
    from marketplace_submissions
    order by submitted_at desc
    limit 100
  `;
}

export async function reviewMarketplaceSubmission(
  id: string,
  decision: MarketplaceReviewDecision,
  notes: string | undefined,
  operatorRef: string,
): Promise<MarketplaceSubmissionSummary> {
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const currentRows = await tx<{ status: string }[]>`
      select status from marketplace_submissions where id = ${id} for update
    `;
    const current = currentRows[0];
    if (!current) throw new MarketplaceSubmissionValidationError("submission_not_found");
    if (!new Set(["submitted", "changes_requested"]).has(current.status)) {
      throw new MarketplaceSubmissionValidationError("invalid_review_transition");
    }
    const next = reviewStatus(decision);
    const rows = await tx<MarketplaceSubmissionSummary[]>`
      update marketplace_submissions
      set status = ${next}, review_notes = ${notes ?? null}, reviewer_ref = ${operatorRef}, reviewed_at = now(), updated_at = now()
      where id = ${id}
      returning
        id, creator_id as "creatorId", listing_id as "listingId", version, status,
        submission_hash as "submissionHash", submitted_at as "submittedAt",
        reviewed_at as "reviewedAt", published_at as "publishedAt"
    `;
    await tx`
      insert into marketplace_submission_audit (
        submission_id, action, actor_type, actor_ref_hash, from_status, to_status, detail
      ) values (
        ${id}, ${decision}, 'operator', ${actorHash(operatorRef)}, ${current.status}, ${next},
        ${tx.json(notes ? { notes } : {})}
      )
    `;
    return rows[0] as MarketplaceSubmissionSummary;
  });
}

export async function publishMarketplaceSubmission(id: string, operatorRef: string): Promise<MarketplaceSubmissionSummary> {
  const sql = platformDatabase();
  return sql.begin(async (tx) => {
    const currentRows = await tx<SubmissionRow[]>`
      select
        id, creator_id as "creatorId", listing_id as "listingId", version, status, payload,
        submission_hash as "submissionHash", submitted_at as "submittedAt",
        reviewed_at as "reviewedAt", published_at as "publishedAt"
      from marketplace_submissions where id = ${id} for update
    `;
    const current = currentRows[0];
    if (!current) throw new MarketplaceSubmissionValidationError("submission_not_found");
    if (current.status !== "approved") throw new MarketplaceSubmissionValidationError("submission_not_approved");
    const parsed = parseMarketplaceSubmission({ ...(current.payload as Record<string, unknown>), termsAccepted: true });
    if (parsed.submissionHash !== current.submissionHash) {
      throw new MarketplaceSubmissionValidationError("submission_integrity_failed");
    }
    const listing = parsed.listing;
    if (listing.resourceIDs.length > 0) {
      const availableResources = await tx<{ id: string }[]>`
        select id from marketplace_content_resources
        where id in ${tx(listing.resourceIDs)} and status = 'published'
      `;
      if (availableResources.length !== new Set(listing.resourceIDs).size) {
        throw new MarketplaceSubmissionValidationError("resource_not_available");
      }
    }

    await tx`
      insert into marketplace_listings (
        id, version, kind, category, title_zh, title_en, summary_zh, summary_en, detail_zh, detail_en,
        min_age, max_age, duration_days, creator_id, availability_kind, price_preview,
        tags_zh, tags_en, status, content_hash, critical_update, revoked_at, published_at, updated_at
      ) values (
        ${listing.id}, ${listing.version}, ${listing.kind}, ${listing.category}, ${listing.title}, ${listing.titleEnglish},
        ${listing.summary}, ${listing.summaryEnglish}, ${listing.detail}, ${listing.detailEnglish},
        ${listing.minAge}, ${listing.maxAge}, ${listing.durationDays}, ${parsed.creatorId}, ${listing.availability.kind},
        ${listing.availability.pricePreview ?? null}, ${listing.tags}, ${listing.tagsEnglish}, 'published',
        ${parsed.submissionHash}, ${listing.criticalUpdate}, null, now(), now()
      )
      on conflict (id) do update set
        version = excluded.version,
        kind = excluded.kind,
        category = excluded.category,
        title_zh = excluded.title_zh,
        title_en = excluded.title_en,
        summary_zh = excluded.summary_zh,
        summary_en = excluded.summary_en,
        detail_zh = excluded.detail_zh,
        detail_en = excluded.detail_en,
        min_age = excluded.min_age,
        max_age = excluded.max_age,
        duration_days = excluded.duration_days,
        creator_id = excluded.creator_id,
        availability_kind = excluded.availability_kind,
        price_preview = excluded.price_preview,
        tags_zh = excluded.tags_zh,
        tags_en = excluded.tags_en,
        status = 'published',
        content_hash = excluded.content_hash,
        critical_update = excluded.critical_update,
        revoked_at = null,
        published_at = now(),
        updated_at = now()
    `;
    await tx`delete from marketplace_plan_items where listing_id = ${listing.id}`;
    for (const [position, item] of listing.planItems.entries()) {
      await tx`
        insert into marketplace_plan_items (listing_id, position, pack_type, template_id, day_offset)
        values (${listing.id}, ${position}, ${item.packType}, ${item.templateID}, ${item.dayOffset})
      `;
    }
    await tx`delete from marketplace_listing_resources where listing_id = ${listing.id}`;
    for (const [position, resourceID] of [...new Set(listing.resourceIDs)].entries()) {
      await tx`
        insert into marketplace_listing_resources (listing_id, resource_id, position, install_behavior)
        select
          ${listing.id}, id, ${position},
          case kind
            when 'book' then 'library_reference'
            when 'video' then 'video_reference'
            else 'creation_template'
          end
        from marketplace_content_resources
        where id = ${resourceID} and status = 'published'
      `;
    }
    const rows = await tx<MarketplaceSubmissionSummary[]>`
      update marketplace_submissions
      set status = 'published', published_at = now(), updated_at = now()
      where id = ${id}
      returning
        id, creator_id as "creatorId", listing_id as "listingId", version, status,
        submission_hash as "submissionHash", submitted_at as "submittedAt",
        reviewed_at as "reviewedAt", published_at as "publishedAt"
    `;
    await tx`
      insert into marketplace_submission_audit (
        submission_id, action, actor_type, actor_ref_hash, from_status, to_status
      ) values (${id}, 'published', 'operator', ${actorHash(operatorRef)}, 'approved', 'published')
    `;
    return rows[0] as MarketplaceSubmissionSummary;
  });
}

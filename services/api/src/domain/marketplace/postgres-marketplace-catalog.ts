import { platformDatabase } from "../../database/postgres.js";
import type { MarketplaceDatabaseListing } from "./types.js";

type PublicRow = {
  id: string;
  version: string;
  kind: MarketplaceDatabaseListing["kind"];
  category: MarketplaceDatabaseListing["category"];
  title: string;
  titleEnglish: string;
  summary: string;
  summaryEnglish: string;
  detail: string;
  detailEnglish: string;
  minAge: number;
  maxAge: number;
  durationDays: number;
  creator: MarketplaceDatabaseListing["creator"];
  availability: MarketplaceDatabaseListing["availability"];
  rating: number;
  ratingCount: number;
  tags: string[];
  tagsEnglish: string[];
  planItems: MarketplaceDatabaseListing["planItems"];
  resources: MarketplaceDatabaseListing["resources"];
  reviews: MarketplaceDatabaseListing["reviews"];
  contentHash: string;
  criticalUpdate: boolean;
  status: MarketplaceDatabaseListing["status"];
  revokedAt?: string;
};

export async function loadPublishedMarketplaceListings(): Promise<MarketplaceDatabaseListing[]> {
  const sql = platformDatabase();
  const rows = await sql<PublicRow[]>`
    select
      l.id,
      l.version,
      l.kind,
      l.category,
      l.title_zh as "title",
      l.title_en as "titleEnglish",
      l.summary_zh as "summary",
      l.summary_en as "summaryEnglish",
      l.detail_zh as "detail",
      l.detail_en as "detailEnglish",
      l.min_age as "minAge",
      l.max_age as "maxAge",
      l.duration_days as "durationDays",
      json_build_object(
        'id', c.id,
        'displayName', c.display_name_zh,
        'displayNameEnglish', c.display_name_en,
        'bio', c.bio_zh,
        'bioEnglish', c.bio_en,
        'isVerified', c.is_verified,
        'rating', c.rating::float8,
        'verifiedFamilyCount', c.verified_family_count
      ) as creator,
      json_build_object(
        'kind', l.availability_kind,
        'pricePreview', l.price_preview
      ) as availability,
      l.rating::float8 as "rating",
      l.rating_count as "ratingCount",
      l.tags_zh as tags,
      l.tags_en as "tagsEnglish",
      coalesce((
        select json_agg(json_build_object(
          'packType', p.pack_type,
          'templateID', p.template_id,
          'dayOffset', p.day_offset
        ) order by p.position)
        from marketplace_plan_items p
        where p.listing_id = l.id
      ), '[]'::json) as "planItems",
      coalesce((
        select json_agg(json_build_object(
          'id', resource.id,
          'kind', resource.kind,
          'title', resource.title_zh,
          'titleEnglish', resource.title_en,
          'summary', resource.summary_zh,
          'summaryEnglish', resource.summary_en,
          'sourceName', resource.source_name,
          'sourceURL', resource.source_url,
          'thumbnailURL', resource.thumbnail_url,
          'languageCode', resource.language_code,
          'minAge', resource.min_age,
          'maxAge', resource.max_age,
          'durationSeconds', resource.duration_seconds,
          'categories', resource.categories_zh,
          'categoriesEnglish', resource.categories_en,
          'installBehavior', link.install_behavior,
          'metadata', resource.metadata
        ) order by link.position)
        from marketplace_listing_resources link
        join marketplace_content_resources resource on resource.id = link.resource_id
        where link.listing_id = l.id and resource.status = 'published'
      ), '[]'::json) as resources,
      coalesce((
        select json_agg(json_build_object(
          'id', r.id,
          'title', r.title_zh,
          'titleEnglish', r.title_en,
          'body', r.body_zh,
          'bodyEnglish', r.body_en,
          'rating', r.rating,
          'verifiedUse', r.verified_use
        ) order by r.created_at desc)
        from marketplace_reviews r
        where r.listing_id = l.id and r.status = 'published'
      ), '[]'::json) as reviews,
      l.content_hash as "contentHash",
      l.critical_update as "criticalUpdate",
      l.status,
      l.revoked_at as "revokedAt"
    from marketplace_listings l
    join marketplace_creators c on c.id = l.creator_id
    where l.status = 'published' and l.revoked_at is null
    order by l.published_at desc nulls last, l.id
    limit 100
  `;
  return rows as MarketplaceDatabaseListing[];
}

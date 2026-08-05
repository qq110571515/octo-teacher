import { createHash } from "node:crypto";
import type {
  MarketplaceAvailabilityKind,
  MarketplaceCategory,
  MarketplaceListingKind,
  MarketplacePackType,
  PublicMarketplacePlanItem,
} from "./types.js";

export const MARKETPLACE_TERMS_VERSION = "2026-07-marketplace-v1";

const listingKinds = new Set<MarketplaceListingKind>([
  "library_asset", "single_content_pack", "course_pack", "mixed_growth_pack", "official_program",
]);
const categories = new Set<MarketplaceCategory>(["routines", "family", "learning", "outdoor", "creativity", "library"]);
const availabilityKinds = new Set<MarketplaceAvailabilityKind>(["free", "beta_access", "price_preview", "unavailable"]);
const packTypes = new Set<MarketplacePackType>([
  "basic_habits", "chores", "outdoor_sports", "learning", "skill_extension", "finance_literacy", "creative_works",
  "family_responsibility",
]);
const forbiddenKeys = new Set([
  "childid", "child_id", "familyid", "family_id", "deviceid", "device_id", "email", "internalnotes", "internal_notes",
  "apikey", "api_key", "token", "secret",
]);

export type MarketplaceSubmissionListing = {
  id: string;
  version: string;
  kind: MarketplaceListingKind;
  category: MarketplaceCategory;
  title: string;
  titleEnglish: string;
  summary: string;
  summaryEnglish: string;
  detail: string;
  detailEnglish: string;
  minAge: number;
  maxAge: number;
  durationDays: number;
  availability: { kind: MarketplaceAvailabilityKind; pricePreview?: string };
  tags: string[];
  tagsEnglish: string[];
  planItems: PublicMarketplacePlanItem[];
  resourceIDs: string[];
  criticalUpdate: boolean;
};

export type ParsedMarketplaceSubmission = {
  creatorId: string;
  termsVersion: string;
  listing: MarketplaceSubmissionListing;
  submissionHash: string;
};

export class MarketplaceSubmissionValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "MarketplaceSubmissionValidationError";
  }
}

function record(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new MarketplaceSubmissionValidationError(code);
  return value as Record<string, unknown>;
}

function text(value: unknown, code: string, max: number): string {
  if (typeof value !== "string") throw new MarketplaceSubmissionValidationError(code);
  const normalized = value.trim();
  if (!normalized || normalized.length > max) throw new MarketplaceSubmissionValidationError(code);
  return normalized;
}

function integer(value: unknown, code: string, min: number, max: number): number {
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) {
    throw new MarketplaceSubmissionValidationError(code);
  }
  return value as number;
}

function boolean(value: unknown, code: string): boolean {
  if (typeof value !== "boolean") throw new MarketplaceSubmissionValidationError(code);
  return value;
}

function strings(value: unknown, code: string, maxItems = 20, maxLength = 80): string[] {
  if (!Array.isArray(value) || value.length > maxItems) throw new MarketplaceSubmissionValidationError(code);
  return value.map((item) => text(item, code, maxLength));
}

function rejectForbiddenKeys(value: unknown): void {
  if (Array.isArray(value)) {
    value.forEach(rejectForbiddenKeys);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (forbiddenKeys.has(key.toLowerCase())) throw new MarketplaceSubmissionValidationError("sensitive_field_forbidden");
    rejectForbiddenKeys(child);
  }
}

function parsePlanItems(value: unknown): PublicMarketplacePlanItem[] {
  if (!Array.isArray(value) || value.length > 100) throw new MarketplaceSubmissionValidationError("invalid_plan_items");
  return value.map((raw) => {
    const item = record(raw, "invalid_plan_item");
    const packType = text(item.packType, "invalid_pack_type", 40) as MarketplacePackType;
    if (!packTypes.has(packType)) throw new MarketplaceSubmissionValidationError("invalid_pack_type");
    return {
      packType,
      templateID: text(item.templateID, "invalid_template_id", 120),
      dayOffset: integer(item.dayOffset, "invalid_day_offset", 0, 365),
    };
  });
}

function stablePayload(creatorId: string, termsVersion: string, listing: MarketplaceSubmissionListing): string {
  return JSON.stringify({ creatorId, termsVersion, listing });
}

export function parseMarketplaceSubmission(value: unknown): ParsedMarketplaceSubmission {
  rejectForbiddenKeys(value);
  const root = record(value, "invalid_submission");
  if (root.termsAccepted !== true) throw new MarketplaceSubmissionValidationError("terms_not_accepted");

  const creatorId = text(root.creatorId, "invalid_creator_id", 100);
  if (!/^[a-z0-9][a-z0-9_-]{2,99}$/i.test(creatorId)) throw new MarketplaceSubmissionValidationError("invalid_creator_id");
  const termsVersion = text(root.termsVersion, "invalid_terms_version", 80);
  if (termsVersion !== MARKETPLACE_TERMS_VERSION) throw new MarketplaceSubmissionValidationError("terms_version_outdated");

  const raw = record(root.listing, "invalid_listing");
  const id = text(raw.id, "invalid_listing_id", 100);
  if (!/^[a-z0-9][a-z0-9-]{2,99}$/.test(id)) throw new MarketplaceSubmissionValidationError("invalid_listing_id");
  const version = text(raw.version, "invalid_version", 40);
  if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(version)) throw new MarketplaceSubmissionValidationError("invalid_version");
  const kind = text(raw.kind, "invalid_kind", 40) as MarketplaceListingKind;
  const category = text(raw.category, "invalid_category", 40) as MarketplaceCategory;
  if (!listingKinds.has(kind)) throw new MarketplaceSubmissionValidationError("invalid_kind");
  if (!categories.has(category)) throw new MarketplaceSubmissionValidationError("invalid_category");

  const availabilityRaw = record(raw.availability, "invalid_availability");
  const availabilityKind = text(availabilityRaw.kind, "invalid_availability", 40) as MarketplaceAvailabilityKind;
  if (!availabilityKinds.has(availabilityKind)) throw new MarketplaceSubmissionValidationError("invalid_availability");
  const pricePreview = availabilityRaw.pricePreview === undefined ? undefined : text(availabilityRaw.pricePreview, "invalid_price_preview", 80);
  if (availabilityKind === "price_preview" && !pricePreview) throw new MarketplaceSubmissionValidationError("price_preview_required");

  const minAge = integer(raw.minAge, "invalid_min_age", 2, 18);
  const maxAge = integer(raw.maxAge, "invalid_max_age", minAge, 18);
  const listing: MarketplaceSubmissionListing = {
    id,
    version,
    kind,
    category,
    title: text(raw.title, "invalid_title", 160),
    titleEnglish: text(raw.titleEnglish, "invalid_title_english", 160),
    summary: text(raw.summary, "invalid_summary", 500),
    summaryEnglish: text(raw.summaryEnglish, "invalid_summary_english", 500),
    detail: text(raw.detail, "invalid_detail", 10_000),
    detailEnglish: text(raw.detailEnglish, "invalid_detail_english", 10_000),
    minAge,
    maxAge,
    durationDays: integer(raw.durationDays, "invalid_duration_days", 0, 365),
    availability: { kind: availabilityKind, ...(pricePreview ? { pricePreview } : {}) },
    tags: strings(raw.tags, "invalid_tags"),
    tagsEnglish: strings(raw.tagsEnglish, "invalid_tags_english"),
    planItems: parsePlanItems(raw.planItems),
    resourceIDs: raw.resourceIDs === undefined ? [] : strings(raw.resourceIDs, "invalid_resource_ids", 500, 160),
    criticalUpdate: boolean(raw.criticalUpdate ?? false, "invalid_critical_update"),
  };
  if (listing.planItems.length === 0 && listing.resourceIDs.length === 0) {
    throw new MarketplaceSubmissionValidationError("plan_items_required");
  }

  return {
    creatorId,
    termsVersion,
    listing,
    submissionHash: createHash("sha256").update(stablePayload(creatorId, termsVersion, listing)).digest("hex"),
  };
}

export type MarketplaceReviewDecision = "approve" | "request_changes" | "reject";

export function reviewStatus(decision: MarketplaceReviewDecision): "approved" | "changes_requested" | "rejected" {
  if (decision === "approve") return "approved";
  if (decision === "request_changes") return "changes_requested";
  return "rejected";
}

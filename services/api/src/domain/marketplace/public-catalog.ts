import type {
  MarketplaceDatabaseListing,
  PublicMarketplaceCatalog,
  PublicMarketplaceListing,
} from "./types.js";

const maxListings = 100;

function clip(value: string, limit: number): string {
  return value.trim().slice(0, limit);
}

function finite(value: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) return minimum;
  return Math.min(maximum, Math.max(minimum, value));
}

export function buildPublicMarketplaceCatalog(
  rows: MarketplaceDatabaseListing[],
  generatedAt = new Date(),
): PublicMarketplaceCatalog {
  const listings: PublicMarketplaceListing[] = rows
    .filter((row) => row.status === "published" && !row.revokedAt)
    .slice(0, maxListings)
    .map((row) => ({
      id: clip(row.id, 120),
      version: clip(row.version, 40),
      kind: row.kind,
      category: row.category,
      title: clip(row.title, 120),
      titleEnglish: clip(row.titleEnglish, 120),
      summary: clip(row.summary, 360),
      summaryEnglish: clip(row.summaryEnglish, 360),
      detail: clip(row.detail, 2_000),
      detailEnglish: clip(row.detailEnglish, 2_000),
      minAge: finite(row.minAge, 2, 18),
      maxAge: finite(row.maxAge, 2, 18),
      durationDays: finite(row.durationDays, 0, 365),
      creator: {
        id: clip(row.creator.id, 120),
        displayName: clip(row.creator.displayName, 120),
        displayNameEnglish: clip(row.creator.displayNameEnglish, 120),
        bio: clip(row.creator.bio, 500),
        bioEnglish: clip(row.creator.bioEnglish, 500),
        isVerified: row.creator.isVerified,
        rating: finite(row.creator.rating, 0, 5),
        verifiedFamilyCount: finite(row.creator.verifiedFamilyCount, 0, 1_000_000),
      },
      availability: {
        kind: row.availability.kind,
        ...(row.availability.pricePreview ? { pricePreview: clip(row.availability.pricePreview, 40) } : {}),
      },
      rating: finite(row.rating, 0, 5),
      ratingCount: finite(row.ratingCount, 0, 1_000_000),
      tags: row.tags.slice(0, 20).map((value) => clip(value, 60)),
      tagsEnglish: row.tagsEnglish.slice(0, 20).map((value) => clip(value, 60)),
      planItems: row.planItems.slice(0, 100).map((item) => ({
        packType: item.packType,
        templateID: clip(item.templateID, 120),
        dayOffset: finite(item.dayOffset, 0, 365),
      })),
      resources: row.resources.slice(0, 500).map((resource) => ({
        id: clip(resource.id, 120),
        kind: resource.kind,
        title: clip(resource.title, 180),
        titleEnglish: clip(resource.titleEnglish, 180),
        summary: clip(resource.summary, 1_000),
        summaryEnglish: clip(resource.summaryEnglish, 1_000),
        sourceName: clip(resource.sourceName, 160),
        sourceURL: clip(resource.sourceURL, 2_000),
        ...(resource.thumbnailURL ? { thumbnailURL: clip(resource.thumbnailURL, 2_000) } : {}),
        languageCode: clip(resource.languageCode, 20),
        minAge: finite(resource.minAge, 2, 18),
        maxAge: finite(resource.maxAge, 2, 18),
        durationSeconds: finite(resource.durationSeconds, 0, 86_400),
        categories: resource.categories.slice(0, 12).map((value) => clip(value, 80)),
        categoriesEnglish: resource.categoriesEnglish.slice(0, 12).map((value) => clip(value, 80)),
        installBehavior: resource.installBehavior,
        metadata: resource.metadata,
      })),
      reviews: row.reviews.slice(0, 20).map((review) => ({
        id: clip(review.id, 120),
        title: clip(review.title, 120),
        titleEnglish: clip(review.titleEnglish, 120),
        body: clip(review.body, 800),
        bodyEnglish: clip(review.bodyEnglish, 800),
        rating: finite(review.rating, 1, 5),
        verifiedUse: review.verifiedUse,
      })),
      contentHash: row.contentHash,
      criticalUpdate: row.criticalUpdate,
    }));

  return { schemaVersion: 1, generatedAt: generatedAt.toISOString(), listings };
}

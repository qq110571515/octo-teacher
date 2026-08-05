export type MarketplaceListingKind =
  | "library_asset"
  | "single_content_pack"
  | "course_pack"
  | "mixed_growth_pack"
  | "official_program";

export type MarketplaceCategory = "routines" | "family" | "learning" | "outdoor" | "creativity" | "library";

export type MarketplaceAvailabilityKind = "free" | "beta_access" | "price_preview" | "unavailable";

export type MarketplacePackType =
  | "basic_habits"
  | "chores"
  | "outdoor_sports"
  | "learning"
  | "skill_extension"
  | "finance_literacy"
  | "creative_works"
  | "family_responsibility";

export type PublicMarketplaceCreator = {
  id: string;
  displayName: string;
  displayNameEnglish: string;
  bio: string;
  bioEnglish: string;
  isVerified: boolean;
  rating: number;
  verifiedFamilyCount: number;
};

export type PublicMarketplaceReview = {
  id: string;
  title: string;
  titleEnglish: string;
  body: string;
  bodyEnglish: string;
  rating: number;
  verifiedUse: boolean;
};

export type PublicMarketplacePlanItem = {
  packType: MarketplacePackType;
  templateID: string;
  dayOffset: number;
};

export type MarketplaceResourceKind = "book" | "video" | "creation_template";
export type MarketplaceResourceInstallBehavior = "library_reference" | "video_reference" | "creation_template";

export type PublicMarketplaceResource = {
  id: string;
  kind: MarketplaceResourceKind;
  title: string;
  titleEnglish: string;
  summary: string;
  summaryEnglish: string;
  sourceName: string;
  sourceURL: string;
  thumbnailURL?: string;
  languageCode: string;
  minAge: number;
  maxAge: number;
  durationSeconds: number;
  categories: string[];
  categoriesEnglish: string[];
  installBehavior: MarketplaceResourceInstallBehavior;
  metadata: Record<string, unknown>;
};

export type PublicMarketplaceListing = {
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
  creator: PublicMarketplaceCreator;
  availability: { kind: MarketplaceAvailabilityKind; pricePreview?: string };
  rating: number;
  ratingCount: number;
  tags: string[];
  tagsEnglish: string[];
  planItems: PublicMarketplacePlanItem[];
  resources: PublicMarketplaceResource[];
  reviews: PublicMarketplaceReview[];
  contentHash: string;
  criticalUpdate: boolean;
};

export type PublicMarketplaceCatalog = {
  schemaVersion: 1;
  generatedAt: string;
  listings: PublicMarketplaceListing[];
};

export type MarketplaceDatabaseListing = PublicMarketplaceListing & {
  status: "draft" | "review" | "published" | "suspended" | "revoked";
  revokedAt?: string;
  creatorInternalContact?: string;
  internalNotes?: string;
};

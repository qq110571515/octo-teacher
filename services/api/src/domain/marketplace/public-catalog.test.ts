import assert from "node:assert/strict";
import test from "node:test";
import { buildPublicMarketplaceCatalog } from "./public-catalog.js";
import type { MarketplaceDatabaseListing } from "./types.js";

function listing(overrides: Partial<MarketplaceDatabaseListing> = {}): MarketplaceDatabaseListing {
  return {
    id: "safe-pack",
    version: "1.0.0",
    kind: "course_pack",
    category: "learning",
    title: "安全课程",
    titleEnglish: "Safe Course",
    summary: "摘要",
    summaryEnglish: "Summary",
    detail: "详情",
    detailEnglish: "Detail",
    minAge: 6,
    maxAge: 10,
    durationDays: 7,
    creator: {
      id: "creator-public",
      displayName: "公开昵称",
      displayNameEnglish: "Public Name",
      bio: "公开简介",
      bioEnglish: "Public bio",
      isVerified: true,
      rating: 4.8,
      verifiedFamilyCount: 12,
    },
    availability: { kind: "beta_access" },
    rating: 4.8,
    ratingCount: 12,
    tags: ["学习"],
    tagsEnglish: ["Learning"],
    planItems: [{ packType: "learning", templateID: "learn-mental-math", dayOffset: 0 }],
    resources: [],
    reviews: [],
    contentHash: "a".repeat(64),
    criticalUpdate: false,
    status: "published",
    creatorInternalContact: "private@example.com",
    internalNotes: "childId=child-secret familyId=family-secret",
    ...overrides,
  };
}

test("public catalog includes only published non-revoked listings and strips internal fields", () => {
  const catalog = buildPublicMarketplaceCatalog([
    listing(),
    listing({ id: "draft", status: "draft" }),
    listing({ id: "revoked", revokedAt: "2026-07-10T00:00:00Z" }),
  ], new Date("2026-07-10T12:00:00Z"));

  assert.equal(catalog.schemaVersion, 1);
  assert.deepEqual(catalog.listings.map((item) => item.id), ["safe-pack"]);
  const serialized = JSON.stringify(catalog);
  assert.equal(serialized.includes("private@example.com"), false);
  assert.equal(serialized.includes("child-secret"), false);
  assert.equal(serialized.includes("family-secret"), false);
});

test("public catalog clips untrusted copy and clamps public numbers", () => {
  const item = buildPublicMarketplaceCatalog([
    listing({
      title: "x".repeat(300),
      rating: 99,
      durationDays: 999,
      reviews: [{
        id: "review",
        title: "review",
        titleEnglish: "review",
        body: "body",
        bodyEnglish: "body",
        rating: 9,
        verifiedUse: true,
      }],
    }),
  ]).listings[0];

  assert.equal(item.title.length, 120);
  assert.equal(item.rating, 5);
  assert.equal(item.durationDays, 365);
  assert.equal(item.reviews[0]?.rating, 5);
});

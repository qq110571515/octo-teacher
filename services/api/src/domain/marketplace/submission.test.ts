import assert from "node:assert/strict";
import test from "node:test";
import { MARKETPLACE_TERMS_VERSION, MarketplaceSubmissionValidationError, parseMarketplaceSubmission, reviewStatus } from "./submission.js";

function validSubmission(): Record<string, unknown> {
  return {
    creatorId: "creator-one",
    termsAccepted: true,
    termsVersion: MARKETPLACE_TERMS_VERSION,
    listing: {
      id: "reading-foundations",
      version: "1.0.0",
      kind: "course_pack",
      category: "learning",
      title: "阅读启蒙",
      titleEnglish: "Reading Foundations",
      summary: "适合家庭使用的阅读启蒙计划。",
      summaryEnglish: "A family reading foundations plan.",
      detail: "每天完成一项阅读活动，并由家长确认。",
      detailEnglish: "Complete one reading activity each day with guardian review.",
      minAge: 5,
      maxAge: 8,
      durationDays: 7,
      availability: { kind: "free" },
      tags: ["阅读"],
      tagsEnglish: ["reading"],
      planItems: [{ packType: "learning", templateID: "read-together", dayOffset: 0 }],
      resourceIDs: [],
      criticalUpdate: false,
    },
  };
}

test("submission parser normalizes a complete bilingual listing and hashes it", () => {
  const parsed = parseMarketplaceSubmission(validSubmission());
  assert.equal(parsed.listing.id, "reading-foundations");
  assert.match(parsed.submissionHash, /^[0-9a-f]{64}$/);
});

test("resource-only library submissions can reference moderated resources", () => {
  const submission = validSubmission();
  const listing = submission.listing as Record<string, unknown>;
  listing.kind = "library_asset";
  listing.planItems = [];
  listing.resourceIDs = ["book-gutenberg-11", "video-numberblocks-one"];
  const parsed = parseMarketplaceSubmission(submission);
  assert.deepEqual(parsed.listing.resourceIDs, ["book-gutenberg-11", "video-numberblocks-one"]);
});

test("empty submissions cannot publish an isolated marketplace shell", () => {
  const submission = validSubmission();
  const listing = submission.listing as Record<string, unknown>;
  listing.kind = "library_asset";
  listing.planItems = [];
  listing.resourceIDs = [];
  assert.throws(() => parseMarketplaceSubmission(submission), /plan_items_required/);
});

test("submission parser blocks child, family, device and credential data recursively", () => {
  const submission = validSubmission();
  (submission.listing as Record<string, unknown>).metadata = { childId: "child-private" };
  assert.throws(() => parseMarketplaceSubmission(submission), (error) => {
    return error instanceof MarketplaceSubmissionValidationError && error.code === "sensitive_field_forbidden";
  });
});

test("submission parser requires explicit current terms acceptance", () => {
  const submission = validSubmission();
  submission.termsAccepted = false;
  assert.throws(() => parseMarketplaceSubmission(submission), /terms_not_accepted/);
});

test("review decisions map only to controlled states", () => {
  assert.equal(reviewStatus("approve"), "approved");
  assert.equal(reviewStatus("request_changes"), "changes_requested");
  assert.equal(reviewStatus("reject"), "rejected");
});

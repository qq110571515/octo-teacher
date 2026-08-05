import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import {
  childCanSeeFamilyChange,
  normalizeFamilyContent,
  normalizeFamilySyncCursor,
  requireSafeGuardianRevocation,
  resolveUniqueActiveGuardianFamily,
  type FamilySyncChange,
} from "./family-control.js";

test("family sync cursor is opaque, monotonic bigint text", () => {
  assert.equal(normalizeFamilySyncCursor(undefined), "0");
  assert.equal(normalizeFamilySyncCursor("00042"), "42");
  assert.throws(() => normalizeFamilySyncCursor("-1"), /invalid_family_sync_cursor/);
  assert.throws(() => normalizeFamilySyncCursor("9223372036854775808"), /invalid_family_sync_cursor/);
});

test("guardian login never chooses arbitrarily between duplicate active families", () => {
  assert.equal(resolveUniqueActiveGuardianFamily([{ familyId: "family-a", isCreator: true }]).familyId, "family-a");
  assert.throws(() => resolveUniqueActiveGuardianFamily([
    { familyId: "family-a" }, { familyId: "family-b" },
  ]), /guardian_multiple_active_families/);
  assert.throws(() => resolveUniqueActiveGuardianFamily([{ familyId: "family-a" }], "family-b"), /family_access_denied/);
});

test("content idempotency hash is independent of metadata key order", () => {
  const base = { mutationRef: "mutation:content:003", clientRef: "content:book:003",
    kind: "book", title: "Safe Book", sourceKind: "cloud_library", availability: "ready" };
  const left = normalizeFamilyContent({ ...base, metadata: { chapterCount: 4, format: "epub" } });
  const right = normalizeFamilyContent({ ...base, metadata: { format: "epub", chapterCount: 4 } });
  assert.equal(left.payloadHash, right.payloadHash);
});

test("family content normalizes the operational metadata envelope", () => {
  const content = normalizeFamilyContent({
    mutationRef: "mutation:content:001",
    clientRef: "content:book:001",
    kind: "book",
    title: "The Picture Alphabet",
    sourceKind: "cloud_library",
    availability: "ready",
    metadata: { format: "epub", chapterCount: 32, bilingual: true },
  });
  assert.equal(content.kind, "book");
  assert.equal(content.metadata.chapterCount, 32);
  assert.match(content.payloadHash, /^[a-f0-9]{64}$/);
});

test("family content rejects child evidence, chat, secrets, and raw media", () => {
  for (const metadata of [
    { apiKey: "sk-secret-secret-secret" },
    { chatHistory: "child said something" },
    { evidencePhoto: "data:image/png;base64,AAAA" },
    { emailBody: "school email" },
  ]) {
    assert.throws(() => normalizeFamilyContent({
      mutationRef: "mutation:content:002",
      clientRef: "content:book:002",
      kind: "book",
      title: "Safe Book",
      sourceKind: "guardian_upload",
      metadata,
    }), FamilyCloudError);
  }
});

test("child delta visibility is scoped to family rename and the child's own rows", () => {
  const base = {
    cursor: "9", entityRef: "ref", operation: "upsert", entityVersion: 1,
    changedAt: "2026-07-17T00:00:00.000Z",
  } satisfies Omit<FamilySyncChange, "entityKind">;
  assert.equal(childCanSeeFamilyChange({ ...base, entityKind: "family" }, "child-a"), true);
  assert.equal(childCanSeeFamilyChange({ ...base, entityKind: "guardian" }, "child-a"), false);
  assert.equal(childCanSeeFamilyChange({ ...base, entityKind: "content" }, "child-a"), false);
  assert.equal(childCanSeeFamilyChange({ ...base, entityKind: "task", childProfileId: "child-a" }, "child-a"), true);
  assert.equal(childCanSeeFamilyChange({ ...base, entityKind: "points", childProfileId: "child-b" }, "child-a"), false);
});

test("creator and self revocation are refused", () => {
  assert.throws(() => requireSafeGuardianRevocation({
    actorGuardianId: "g1", targetGuardianId: "g1", targetIsCreator: false,
  }), /guardian_self_revoke_forbidden/);
  assert.throws(() => requireSafeGuardianRevocation({
    actorGuardianId: "g1", targetGuardianId: "g2", targetIsCreator: true,
  }), /family_creator_revoke_forbidden/);
});

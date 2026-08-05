import assert from "node:assert/strict";
import test from "node:test";
import type { FamilyCloudSnapshot, FamilyTaskCloudRecord } from "./cloud-types.js";
import { buildFamilyConsole, classifyFamilyTaskDelivery } from "./family-task-delivery.js";

function v2Payload(input: {
  reading: unknown;
  readingMode: unknown;
  contentReadiness: unknown;
  sourceURLString?: string;
}): unknown {
  return {
    version: 2,
    task: { reading: input.reading },
    readingMode: input.readingMode,
    contentReadiness: input.contentReadiness,
    ...(input.sourceURLString === undefined ? {} : {
      bookResource: { sourceURLString: input.sourceURLString },
    }),
  };
}

test("task payload v2 delivers only executable reading modes", () => {
  assert.deepEqual(classifyFamilyTaskDelivery(v2Payload({
    reading: { bookTitle: "A" },
    readingMode: "digital_loaded",
    contentReadiness: "ready",
    sourceURLString: "https://example.com/book.epub",
  })), { status: "ready" });
  assert.equal(classifyFamilyTaskDelivery(v2Payload({
    reading: { bookTitle: "A" },
    readingMode: "digital_loaded",
    contentReadiness: "ready",
    sourceURLString: "http://example.com/book.epub",
  })).status, "quarantined");
  assert.deepEqual(classifyFamilyTaskDelivery(v2Payload({
    reading: { bookTitle: "A" },
    readingMode: "physical_manual",
    contentReadiness: "not_required",
  })), { status: "ready" });
  assert.equal(classifyFamilyTaskDelivery(v2Payload({
    reading: { bookTitle: "A" },
    readingMode: "physical_manual",
    contentReadiness: "ready",
  })).status, "quarantined");
  assert.equal(classifyFamilyTaskDelivery({
    version: 2,
    task: { reading: { bookTitle: "A" } },
    readingMode: "physical_manual",
    contentReadiness: "not_required",
    bookResource: { sourceURLString: "https://example.com/book.epub" },
  }).status, "quarantined");
});

test("non-reading v2 tasks accept omitted nil fields while rejecting reading residue", () => {
  assert.deepEqual(classifyFamilyTaskDelivery(v2Payload({
    reading: null,
    readingMode: null,
    contentReadiness: "not_required",
  })), { status: "ready" });
  assert.deepEqual(classifyFamilyTaskDelivery({
    version: 2,
    task: { reading: null },
    contentReadiness: "not_required",
  }), { status: "ready" });
  assert.deepEqual(classifyFamilyTaskDelivery({
    version: 2,
    task: { title: "Tidy the desk" },
  }), { status: "ready" });
  assert.equal(classifyFamilyTaskDelivery({
    version: 2,
    task: { title: "Tidy the desk" },
    readingMode: "digital_loaded",
    contentReadiness: "not_required",
  }).status, "quarantined");
  assert.equal(classifyFamilyTaskDelivery({
    version: 2,
    task: { title: "Tidy the desk" },
    bookResource: { sourceURLString: "https://example.com/book.epub" },
  }).status, "quarantined");
});

test("legacy payloads that imply electronic reading are quarantined", () => {
  assert.deepEqual(classifyFamilyTaskDelivery({
    version: 1,
    task: { reading: { deliveryMode: "physical_manual" } },
  }), { status: "ready" });
  assert.equal(classifyFamilyTaskDelivery({
    version: 1,
    task: { reading: { importedBookId: "book-123" } },
  }).status, "quarantined");
  assert.equal(classifyFamilyTaskDelivery({
    version: 1,
    task: { reading: { deliveryMode: "digital_loaded" } },
    bookResource: { sourceURLString: "https://example.com/book.epub" },
  }).status, "quarantined");
});

test("guardian console summarizes tasks, availability, quarantine, points, and AI configuration", () => {
  const snapshot: FamilyCloudSnapshot = {
    family: { id: "family-1", publicRef: "family_public", displayName: "Home", isCreator: true },
    guardians: [],
    children: [{
      id: "child-1",
      publicRef: "child_public",
      displayName: "Ari",
      preReaderMode: false,
      interfaceLanguage: "english",
      contentLanguage: "bilingual",
      dailyLimitMinutes: 60,
      exchangePolicy: {
        baseMonthlyAllowance: 0,
        allowanceDayOfMonth: 1,
        screenRate: "one_point_per_minute",
        pointsPerCurrencyUnit: 10,
        pocketMoneyRequiresApproval: true,
        currencySymbol: "$",
      },
      screenTimeCatalog: {
        schemaVersion: 1,
        revision: 4,
        selectionData: "ZWZnaA==",
        selectionHash: "a8dc9bb12d51b977830f97c03fb22be36c2a1449ec0389648fd3db2bff6cbb11",
        applicationCount: 6,
        categoryCount: 0,
        webDomainCount: 0,
        capturedAt: "2026-07-15T00:00:00.000Z",
        sourceDevicePublicRef: "device_child_1",
      },
      screenTimePolicy: {
        schemaVersion: 3,
        revision: 1,
        selectionData: "YWJjZA==",
        selectionHash: "db3eaf9a79dc18d098e632573be3e3bf8467688e271dfcb77b2a6c584d422ae4",
        applicationCount: 2,
        categoryCount: 1,
        webDomainCount: 0,
        control: {
          schemaVersion: 1,
          commandId: "policy:1:db3eaf9a79dc18d0",
          mode: "locked",
          issuedAt: "2026-07-15T00:00:00.000Z",
        },
        updatedAt: "2026-07-15T00:00:00.000Z",
      },
      screenTimeStatus: {
        authorization: "approved",
        enforcement: "applied",
        appliedPolicyRevision: 1,
        appliedSelectionHash: "db3eaf9a79dc18d098e632573be3e3bf8467688e271dfcb77b2a6c584d422ae4",
        appliedControlCommandId: "policy:1:db3eaf9a79dc18d0",
        controlMode: "locked",
        applicationCount: 2,
        categoryCount: 1,
        webDomainCount: 0,
        updatedAt: "2026-07-15T00:00:00.000Z",
      },
      screenTimeEmergency: { schemaVersion: 1, status: "idle", updatedAt: "2026-07-15T00:00:00.000Z" },
      growthPointBalance: 45,
      profileVersion: 1,
    }],
    devices: [{
      id: "device-1",
      publicRef: "device_child_1",
      displayName: "Ari's iPhone",
      role: "child",
      childProfileId: "child-1",
      status: "active",
      boundAt: "2026-07-15T00:00:00.000Z",
    }],
  };
  const common = {
    childProfileId: "child-1",
    titleEnglish: undefined,
    requiresEvidence: false,
    plannedFor: undefined,
    evidenceSummary: undefined,
    quarantineReason: undefined,
    version: 1,
    updatedAt: "2026-07-15T00:00:00.000Z",
  };
  const tasks: FamilyTaskCloudRecord[] = [{
    ...common,
    id: "task-reading",
    clientRef: "reading-ref",
    title: "Read",
    status: "assigned",
    growthPoints: 10,
    taskPayload: v2Payload({
      reading: { bookTitle: "A" },
      readingMode: "digital_loaded",
      contentReadiness: "ready",
      sourceURLString: "https://example.com/book.epub",
    }),
    deliveryStatus: "ready",
  }, {
    ...common,
    id: "task-video",
    clientRef: "video-ref",
    title: "Watch",
    status: "submitted",
    growthPoints: 5,
    taskPayload: {
      version: 2,
      task: { reading: null, video: { urlString: "https://example.com/video" } },
      readingMode: null,
      contentReadiness: "not_required",
    },
    deliveryStatus: "quarantined",
    quarantineReason: "manual_review",
  }];

  const console = buildFamilyConsole(snapshot, tasks, true);
  assert.equal(console.ai.configured, true);
  assert.equal(console.children[0]?.growthPointBalance, 45);
  assert.equal(console.children[0]?.taskStatusSummary.submitted, 1);
  assert.deepEqual(console.children[0]?.availability.reading, {
    total: 1, available: 1, digitalReady: 1, physicalManual: 0,
  });
  assert.deepEqual(console.children[0]?.availability.video, { total: 1, available: 0 });
  assert.equal(console.children[0]?.availability.screenTime.available, true);
  assert.equal(console.children[0]?.availability.screenTime.catalogApplicationCount, 6);
  assert.equal(console.children[0]?.availability.screenTime.catalogRevision, 4);
  assert.equal(console.children[0]?.quarantine.count, 1);

  const sourceDevice = snapshot.devices[0];
  if (!sourceDevice) {
    assert.fail("expected the catalog source device fixture");
  }
  sourceDevice.status = "revoked";
  const afterCatalogSourceRevoked = buildFamilyConsole(snapshot, tasks, true);
  assert.equal(afterCatalogSourceRevoked.children[0]?.availability.screenTime.catalogApplicationCount, 0);
  assert.equal(afterCatalogSourceRevoked.children[0]?.availability.screenTime.catalogRevision, undefined);
  sourceDevice.status = "active";

  sourceDevice.requiresRebind = true;
  const whileCatalogSourceRequiresRebind = buildFamilyConsole(snapshot, tasks, true);
  assert.equal(whileCatalogSourceRequiresRebind.children[0]?.availability.screenTime.available, false);
  assert.equal(whileCatalogSourceRequiresRebind.children[0]?.availability.screenTime.catalogApplicationCount, 0);
  assert.equal(whileCatalogSourceRequiresRebind.children[0]?.availability.screenTime.catalogRevision, undefined);
  sourceDevice.requiresRebind = undefined;

  const child = snapshot.children[0];
  if (!child?.screenTimePolicy?.control || !child.screenTimeStatus) {
    assert.fail("expected screen time fixture");
  }
  child.screenTimePolicy.control = {
    ...child.screenTimePolicy.control,
    mode: "unlocked",
    unlockUntil: "2000-01-01T00:30:00.000Z",
  };
  child.screenTimeStatus.controlMode = "locked";
  const afterExpiredUnlock = buildFamilyConsole(snapshot, tasks, true);
  assert.equal(
    afterExpiredUnlock.children[0]?.availability.screenTime.available,
    true,
    "an expired guardian unlock must return to the locked, redeemable state",
  );
});

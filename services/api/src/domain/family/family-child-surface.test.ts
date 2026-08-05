import assert from "node:assert/strict";
import test from "node:test";
import type { FamilyTaskCloudRecord } from "./cloud-types.js";
import { buildFamilyChildSurfaces } from "./family-child-surface.js";

const commonTask: Omit<FamilyTaskCloudRecord, "id" | "clientRef" | "title" | "status" | "taskPayload"> = {
  childProfileId: "child-1",
  growthPoints: 10,
  requiresEvidence: false,
  deliveryStatus: "ready",
  version: 1,
  updatedAt: "2026-07-17T12:00:00.000Z",
};

test("child surface provides one stable module layout for every client", () => {
  const surfaces = buildFamilyChildSurfaces({
    generatedAt: "2026-07-17T12:00:00.000Z",
    children: [{
      id: "child-1",
      publicRef: "child_public",
      clientRef: "local-child",
      displayName: "Alex",
      birthYear: 2019,
      preReaderMode: true,
      interfaceLanguage: "english",
      contentLanguage: "english",
      version: 7,
    }],
    balances: [{ childProfileId: "child-1", balance: 125 }],
    taskCursors: [{ childProfileId: "child-1", cursor: "88" }],
    tasks: [{
      ...commonTask,
      id: "task-read",
      clientRef: "READ-ONE",
      title: "读一本书",
      titleEnglish: "Read a book",
      status: "assigned",
      taskPayload: { version: 2, task: { reading: { bookTitle: "A" } } },
    }, {
      ...commonTask,
      id: "task-done",
      clientRef: "DONE-ONE",
      title: "刷牙",
      status: "approved",
      taskPayload: { version: 2, task: { reading: null } },
    }],
    content: [{
      id: "book-1",
      publicRef: "book_public",
      clientRef: "BOOK-ONE",
      kind: "book",
      title: "A",
      sourceKind: "cloud_library",
      availability: "ready",
      metadata: {},
      version: 2,
      updatedAt: "2026-07-17T11:00:00.000Z",
      storageObjectKey: "must-not-leak.epub",
    }],
    assignments: [{
      contentItemId: "book-1",
      childProfileId: "child-1",
      status: "assigned",
      progressPercent: 20,
      durationSeconds: 180,
      version: 3,
      updatedAt: "2026-07-17T11:30:00.000Z",
    }],
  });

  assert.equal(surfaces.length, 1);
  const surface = surfaces[0]!;
  assert.deepEqual(surface.modules.map((entry) => entry.id), [
    "module:today", "module:reading", "module:video", "module:creation", "module:completed",
  ]);
  assert.equal(surface.child.growthPointBalance, 125);
  assert.equal(surface.sync.taskCursor, 88);
  assert.equal(surface.tasks[0]?.moduleId, "module:completed");
  assert.equal(surface.tasks[1]?.moduleId, "module:reading");
  assert.equal(surface.library.books[0]?.assignment.progressPercent, 20);
  assert.equal("storageObjectKey" in (surface.library.books[0] ?? {}), false);
  assert.match(surface.surfaceVersion, /^[a-f0-9]{24}$/);
});

test("quarantined tasks and removed content never reach a child surface", () => {
  const surfaces = buildFamilyChildSurfaces({
    children: [{
      id: "child-1", publicRef: "child_public", displayName: "Alex", preReaderMode: true,
      interfaceLanguage: "english", contentLanguage: "english",
    }],
    tasks: [{
      ...commonTask,
      id: "task-bad",
      clientRef: "bad",
      title: "Unavailable",
      status: "assigned",
      taskPayload: null,
      deliveryStatus: "quarantined",
    }],
    content: [{
      id: "video-1", publicRef: "video_public", clientRef: "video", kind: "video", title: "V",
      sourceKind: "cloud_library", availability: "ready", metadata: {}, version: 1,
      updatedAt: "2026-07-17T11:00:00.000Z",
    }],
    assignments: [{
      contentItemId: "video-1", childProfileId: "child-1", status: "removed", progressPercent: 0,
      durationSeconds: 0, version: 1, updatedAt: "2026-07-17T11:00:00.000Z",
    }],
  });
  assert.equal(surfaces[0]?.tasks.length, 0);
  assert.equal(surfaces[0]?.library.videos.length, 0);
});

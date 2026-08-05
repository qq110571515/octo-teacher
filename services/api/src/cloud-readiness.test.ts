import test from "node:test";
import assert from "node:assert/strict";
import { createOctoTeacherPlatform } from "./app/default-platform.js";
import { auditPlatformReadiness } from "./app/platform-readiness.js";
import { loadPlatformEnv } from "./config/env.js";
import { InMemoryBookCatalog } from "./domain/books/in-memory-book-catalog.js";
import { InMemoryFamilyStore } from "./domain/family/in-memory-family-store.js";
import { InMemoryUsageStore } from "./domain/usage/in-memory-usage-store.js";
import { defaultPlatformIntegrations, IntegrationRegistry } from "./integrations/integration-registry.js";

test("default platform registers cloud deployment modules and console routes", () => {
  const platform = createOctoTeacherPlatform();

  assert.ok(platform.modules.get("identity-family"));
  assert.ok(platform.modules.get("book-library"));
  assert.ok(platform.modules.get("usage-metering"));
  assert.ok(platform.modules.get("integration-registry"));
  assert.equal(platform.routes.get("control-books-list")?.plane, "control");
  assert.equal(platform.routes.get("runtime-books-list")?.readOnly, true);
  assert.equal(platform.routes.get("control-book-publish")?.state, "gated");
});

test("platform readiness audit catches no missing workflow hooks in the default scaffold", () => {
  const platform = createOctoTeacherPlatform();

  assert.deepEqual(auditPlatformReadiness(platform), []);
});

test("platform factory binds environment into integration readiness", () => {
  const platform = createOctoTeacherPlatform({
    environment: "staging",
    port: 8787,
    marketplaceOperationsEnabled: false,
    accountRegistrationEnabled: false,
    enableDangerousRoutes: false,
    enableRuntimeWrites: false,
  });

  assert.equal(platform.env.environment, "staging");
  assert.equal(platform.integrations.list().every((integration) => integration.environment === "staging"), true);
});

test("platform readiness blocks production dangerous flags", () => {
  const platform = createOctoTeacherPlatform({
    environment: "production",
    port: 8787,
    marketplaceOperationsEnabled: false,
    accountRegistrationEnabled: false,
    enableDangerousRoutes: true,
    enableRuntimeWrites: false,
  });

  assert.equal(auditPlatformReadiness(platform).some((finding) => finding.code === "production_dangerous_flag"), true);
});

test("family store requires an active guardian before creating child profiles and device links", () => {
  const store = new InMemoryFamilyStore();

  const guardian = store.createGuardian({
    id: "user_guardian_1",
    email: "guardian@example.com",
    displayName: "Guardian",
    createdAt: "2026-07-09T00:00:00.000Z",
  });
  const family = store.createFamily({
    id: "family_1",
    name: "Octo Teacher Test Family",
    guardianUserId: guardian.id,
    createdAt: "2026-07-09T00:01:00.000Z",
  });
  const child = store.createChildProfile({
    id: "child_1",
    familyId: family.id,
    displayName: "Child",
    guardianUserId: guardian.id,
    birthYear: 2018,
    createdAt: "2026-07-09T00:02:00.000Z",
  });
  const link = store.createDeviceLink({
    id: "device_link_1",
    familyId: family.id,
    childProfileId: child.id,
    devicePublicRef: "device:public-test",
    guardianUserId: guardian.id,
    createdAt: "2026-07-09T00:03:00.000Z",
  });

  assert.equal(store.listChildren(family.id).length, 1);
  assert.equal(link.status, "pending");
  assert.throws(
    () =>
      store.createChildProfile({
        id: "child_2",
        familyId: family.id,
        displayName: "No Guardian",
        guardianUserId: "user_not_guardian",
        createdAt: "2026-07-09T00:04:00.000Z",
      }),
    /not an active guardian/,
  );
});

test("book catalog gates publication on readable cloud assets and records download metrics", () => {
  const catalog = new InMemoryBookCatalog();

  catalog.upsertBook({
    id: "book_1",
    title: "A Public Domain Book",
    author: "Author",
    language: "en",
    ageBand: "6-8",
    categories: ["reading"],
    source: "public_domain",
    status: "review",
    createdAt: "2026-07-09T00:00:00.000Z",
  });

  assert.throws(() => catalog.publishBook("book_1"), /without an EPUB or PDF asset/);

  catalog.addAsset({
    id: "asset_1",
    bookId: "book_1",
    kind: "epub",
    storageKey: "books/book_1/v1/book.epub",
    contentType: "application/epub+zip",
    byteSize: 1024,
    checksum: "sha256:test",
    createdAt: "2026-07-09T00:01:00.000Z",
  });

  catalog.publishBook("book_1");
  catalog.recordDownload({
    id: "download_1",
    bookId: "book_1",
    familyId: "family_1",
    childProfileId: "child_1",
    platform: "ios",
    occurredAt: "2026-07-09T00:02:00.000Z",
  });

  assert.equal(catalog.listPublished().length, 1);
  assert.deepEqual(catalog.metrics(), [{ bookId: "book_1", downloadCount: 1 }]);
});

test("usage store rolls up AI token and app activation metrics without provider secrets", () => {
  const usage = new InMemoryUsageStore();

  usage.recordAiUsage({
    id: "ai_usage_1",
    familyId: "family_1",
    userId: "user_guardian_1",
    feature: "parent_coach",
    provider: "openai",
    model: "gpt-test",
    inputTokens: 100,
    outputTokens: 50,
    costUsd: 0.01,
    occurredAt: "2026-07-09T00:00:00.000Z",
  });
  usage.recordAppUsage({
    id: "app_event_1",
    kind: "family_created",
    platform: "ios",
    familyId: "family_1",
    userId: "user_guardian_1",
    occurredAt: "2026-07-09T00:01:00.000Z",
  });

  assert.deepEqual(usage.aiRollupByFamily(), [
    {
      familyId: "family_1",
      totalInputTokens: 100,
      totalOutputTokens: 50,
      totalCostUsd: 0.01,
      eventCount: 1,
    },
  ]);
  assert.equal(usage.appEventCount("family_created"), 1);
});

test("integration registry reports missing cloud secrets and blocks public secret exposure", () => {
  const registry = new IntegrationRegistry(defaultPlatformIntegrations("production"));
  const missingFindings = registry.audit({});

  assert.equal(missingFindings.some((finding) => finding.provider === "postgres" && finding.code === "missing_required_secret"), true);
  assert.equal(missingFindings.some((finding) => finding.code === "secret_in_public_config"), false);

  const openAi = registry.list().find((integration) => integration.provider === "openai");
  assert.ok(openAi);
  assert.equal(openAi.publicConfigKeys.includes("OPENAI_API_KEY"), false);
});

test("integration registry derives configured status from runtime env", () => {
  const platform = createOctoTeacherPlatform(
    loadPlatformEnv({
      OCTOTEACHER_ENV: "production",
      DATABASE_URL: "postgres://example",
      SENTRY_DSN: "https://public@example.ingest.sentry.io/1",
    }),
  );

  const postgres = platform.integrations.list().find((integration) => integration.provider === "postgres");
  const r2 = platform.integrations.list().find((integration) => integration.provider === "cloudflare_r2");
  const sentry = platform.integrations.list().find((integration) => integration.provider === "sentry");

  assert.ok(postgres);
  assert.ok(r2);
  assert.ok(sentry);
  assert.equal(postgres.status, "configured");
  assert.equal(r2.status, "missing_secret");
  assert.equal(sentry.status, "configured");
});

test("integration registry requires complete R2 credentials before marking storage configured", () => {
  const partial = createOctoTeacherPlatform(
    loadPlatformEnv({
      OCTOTEACHER_ENV: "production",
      R2_ACCOUNT_ID: "r2-account",
      R2_BOOKS_BUCKET: "books",
    }),
  );
  const complete = createOctoTeacherPlatform(
    loadPlatformEnv({
      OCTOTEACHER_ENV: "production",
      R2_ACCOUNT_ID: "r2-account",
      R2_ACCESS_KEY_ID: "r2-access-key",
      R2_SECRET_ACCESS_KEY: "r2-secret",
      R2_BOOKS_BUCKET: "books",
    }),
  );

  assert.equal(partial.integrations.list().find((integration) => integration.provider === "cloudflare_r2")?.status, "missing_secret");
  assert.equal(complete.integrations.list().find((integration) => integration.provider === "cloudflare_r2")?.status, "configured");
});

test("production integration registry requires complete APNs provider credentials", () => {
  const partial = createOctoTeacherPlatform(
    loadPlatformEnv({
      OCTOTEACHER_ENV: "production",
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
    }),
  );
  const complete = createOctoTeacherPlatform(
    loadPlatformEnv({
      OCTOTEACHER_ENV: "production",
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
      APNS_PRIVATE_KEY: "private-key",
      APNS_TOPIC: "com.octoteacher.app",
    }),
  );

  const partialAPNs = partial.integrations.list().find(
    (integration) => integration.provider === "apple_push_notifications",
  );
  const completeAPNs = complete.integrations.list().find(
    (integration) => integration.provider === "apple_push_notifications",
  );

  assert.equal(partialAPNs?.status, "missing_secret");
  assert.equal(completeAPNs?.status, "configured");
  assert.equal(
    partial.integrations.audit({
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
    }).some((finding) => finding.code === "missing_required_secret"),
    true,
  );
});

test("permission gate defaults to deny for writes and sensitive reads", () => {
  const platform = createOctoTeacherPlatform();

  const publicRead = platform.permissions.decide({
    actorId: "operator_1",
    role: "operator",
    action: "read",
    resource: "book-catalog",
    dataSensitivity: ["public", "operational"],
  });
  const write = platform.permissions.decide({
    actorId: "operator_1",
    role: "operator",
    action: "write",
    resource: "book-catalog",
    dataSensitivity: ["operational"],
  });
  const sensitiveRead = platform.permissions.decide({
    actorId: "operator_1",
    role: "operator",
    action: "read",
    resource: "child-profile",
    dataSensitivity: ["child_identity"],
  });

  assert.equal(publicRead.allowed, true);
  assert.equal(write.allowed, false);
  assert.equal(sensitiveRead.allowed, false);
});

test("environment schema captures deployment integration hints without enabling dangerous routes", () => {
  const env = loadPlatformEnv({
    OCTOTEACHER_ENV: "production",
    PORT: "3000",
    DATABASE_URL: "postgres://example",
    R2_ACCOUNT_ID: "r2-account",
    R2_ACCESS_KEY_ID: "r2-access-key",
    R2_SECRET_ACCESS_KEY: "r2-secret",
    R2_BOOKS_BUCKET: "books",
    OPENAI_API_KEY: "sk-test",
    OPENAI_PROJECT_ID: "proj_test",
    APP_STORE_CONNECT_KEY_ID: "key_test",
    APP_STORE_CONNECT_ISSUER_ID: "issuer_test",
    APP_STORE_CONNECT_PRIVATE_KEY: "private_key",
    MARKETPLACE_CREATOR_TOKEN: "creator-token",
    MARKETPLACE_OPERATOR_TOKEN: "operator-token",
    MARKETPLACE_OPERATIONS_ENABLED: "true",
  });

  assert.equal(env.environment, "production");
  assert.equal(env.port, 3000);
  assert.equal(env.enableDangerousRoutes, false);
  assert.equal(env.enableRuntimeWrites, false);
  assert.equal(env.marketplaceOperationsEnabled, true);
  assert.equal(env.r2AccessKeyId, "r2-access-key");
  assert.equal(env.r2BooksBucket, "books");
  assert.equal(env.appStoreConnectKeyId, "key_test");
});

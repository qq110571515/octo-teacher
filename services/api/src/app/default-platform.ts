import { InMemoryAuditLog } from "../audit/in-memory-audit-log.js";
import { InMemoryBookCatalog } from "../domain/books/in-memory-book-catalog.js";
import { InMemoryFamilyStore } from "../domain/family/in-memory-family-store.js";
import { InMemoryUsageStore } from "../domain/usage/in-memory-usage-store.js";
import { InMemoryEventStore } from "../events/in-memory-event-store.js";
import { defaultPlatformIntegrations, IntegrationRegistry } from "../integrations/integration-registry.js";
import { ModuleRegistry } from "../modules/module-registry.js";
import type { ModuleManifest } from "../modules/types.js";
import { DefaultPermissionGate } from "../permissions/default-permission-gate.js";
import { RouteRegistry } from "../routing/route-registry.js";
import type { RouteDefinition } from "../routing/types.js";
import { WorkflowRegistry } from "../workflows/workflow-registry.js";
import type { WorkflowDefinition } from "../workflows/types.js";
import { loadPlatformEnv, type PlatformEnv } from "../config/env.js";

export type OctoTeacherPlatform = {
  env: PlatformEnv;
  modules: ModuleRegistry;
  routes: RouteRegistry;
  events: InMemoryEventStore;
  workflows: WorkflowRegistry;
  permissions: DefaultPermissionGate;
  audit: InMemoryAuditLog;
  integrations: IntegrationRegistry;
  families: InMemoryFamilyStore;
  books: InMemoryBookCatalog;
  usage: InMemoryUsageStore;
};

export function createOctoTeacherPlatform(env: PlatformEnv = loadPlatformEnv()): OctoTeacherPlatform {
  const platform: OctoTeacherPlatform = {
    env,
    modules: new ModuleRegistry(),
    routes: new RouteRegistry(),
    events: new InMemoryEventStore(),
    workflows: new WorkflowRegistry(),
    permissions: new DefaultPermissionGate(),
    audit: new InMemoryAuditLog(),
    integrations: new IntegrationRegistry(
      defaultPlatformIntegrations(env.environment, {
        APP_STORE_CONNECT_ISSUER_ID: env.appStoreConnectIssuerId,
        APP_STORE_CONNECT_KEY_ID: env.appStoreConnectKeyId,
        APP_STORE_CONNECT_PRIVATE_KEY: env.appStoreConnectPrivateKey,
        APNS_KEY_ID: env.apnsKeyId,
        APNS_TEAM_ID: env.apnsTeamId,
        APNS_PRIVATE_KEY: env.apnsPrivateKey,
        APNS_TOPIC: env.apnsTopic,
        DATABASE_URL: env.databaseUrl,
        NEXT_PUBLIC_APP_ENV: env.publicAppEnv,
        OPENAI_API_KEY: env.openAiApiKey,
        OPENAI_PROJECT_ID: env.openAiProjectId,
        R2_ACCESS_KEY_ID: env.r2AccessKeyId,
        R2_ACCOUNT_ID: env.r2AccountId,
        R2_BOOKS_BUCKET: env.r2BooksBucket,
        R2_SECRET_ACCESS_KEY: env.r2SecretAccessKey,
        SENTRY_DSN: env.sentryDsn,
      }),
    ),
    families: new InMemoryFamilyStore(),
    books: new InMemoryBookCatalog(),
    usage: new InMemoryUsageStore(),
  };

  for (const manifest of defaultModuleManifests()) {
    platform.modules.register(manifest);
    for (const route of manifest.routes) {
      platform.routes.register(route);
    }
  }

  for (const workflow of defaultWorkflowDefinitions()) {
    platform.workflows.register(workflow);
  }

  return platform;
}

function route(input: RouteDefinition): RouteDefinition {
  return input;
}

export function defaultModuleManifests(): ModuleManifest[] {
  const releaseGates = [
    { id: "env-schema", title: "Environment schema", required: true, status: "passed" as const },
    { id: "audit-log", title: "Audit log attached", required: true, status: "passed" as const },
  ];

  return [
    {
      id: "module-registry",
      title: "Module Registry",
      owner: "platform",
      status: "scaffolded",
      priority: "P0",
      docs: ["docs/architecture/MODULE_SYSTEM.md"],
      capabilities: ["module:registry", "release-gate:read"],
      dependencies: [],
      dataSensitivity: ["operational"],
      routes: [
        route({
          id: "control-modules-list",
          plane: "control",
          method: "GET",
          path: "/console/v1/modules",
          moduleId: "module-registry",
          state: "enabled",
          readOnly: true,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Dashboard read model for registered modules.",
        }),
      ],
      eventsProduced: ["module.registered"],
      eventsConsumed: [],
      workflowHooks: ["module-release-gate-workflow"],
      releaseGates,
    },
    {
      id: "event-store",
      title: "Event Store",
      owner: "platform",
      status: "scaffolded",
      priority: "P0",
      docs: ["docs/architecture/EVENT_BUS.md", "docs/EVENT_CONTRACTS.md"],
      capabilities: ["event:append", "event:read", "event:replay-dry-run"],
      dependencies: [],
      dataSensitivity: ["operational", "child_identity"],
      routes: [
        route({
          id: "internal-events-append",
          plane: "internal",
          method: "POST",
          path: "/internal/v1/events",
          moduleId: "event-store",
          state: "gated",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational", "child_identity"],
          description: "Internal append-only event ingestion route.",
        }),
      ],
      eventsProduced: ["event.appended"],
      eventsConsumed: [],
      workflowHooks: ["offline-outbox-replay-workflow"],
      releaseGates,
    },
    {
      id: "workflow-engine",
      title: "Workflow Engine",
      owner: "platform",
      status: "scaffolded",
      priority: "P0",
      docs: ["docs/BACKEND_PLATFORM_BLUEPRINT.md"],
      capabilities: ["workflow:definition", "workflow:instance-dry-run"],
      dependencies: [{ moduleId: "event-store", reason: "Workflows are triggered by platform events." }],
      dataSensitivity: ["operational"],
      routes: [
        route({
          id: "control-workflows-list",
          plane: "control",
          method: "GET",
          path: "/console/v1/workflows",
          moduleId: "workflow-engine",
          state: "enabled",
          readOnly: true,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Dashboard read model for workflow definitions.",
        }),
      ],
      eventsProduced: ["workflow.definition_registered"],
      eventsConsumed: ["event.appended"],
      workflowHooks: ["module-release-gate-workflow"],
      releaseGates,
    },
    {
      id: "runtime-safety",
      title: "Runtime Safety Gates",
      owner: "family-safety",
      status: "scaffolded",
      priority: "P0",
      docs: ["docs/trust/PRIVACY_SAFETY.md", "docs/core/POLICY_ENGINE.md"],
      capabilities: ["permission:check", "consent:stub", "dangerous-route:disable"],
      dependencies: [
        { moduleId: "event-store", reason: "Safety decisions are audited through events." },
        { moduleId: "workflow-engine", reason: "High-risk actions require workflow gates." },
      ],
      dataSensitivity: ["operational", "child_privacy", "child_health", "ai_transcript", "payment", "credential"],
      routes: [
        route({
          id: "runtime-device-command",
          plane: "runtime",
          method: "POST",
          path: "/public/v1/device-commands",
          moduleId: "runtime-safety",
          state: "disabled",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational", "child_identity"],
          description: "Future device command endpoint; disabled until device-safety release gate passes.",
          releaseGateIds: ["dangerous-side-effect"],
        }),
        route({
          id: "runtime-credit-direct-adjust",
          plane: "runtime",
          method: "POST",
          path: "/public/v1/credit/direct-adjustments",
          moduleId: "runtime-safety",
          state: "disabled",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational", "child_identity"],
          description: "Forbidden direct credit adjustment route; credit changes must use workflow and ledger.",
          releaseGateIds: ["dangerous-side-effect"],
        }),
      ],
      eventsProduced: ["permission.decision_recorded"],
      eventsConsumed: ["workflow.side_effect_requested"],
      workflowHooks: ["task-completion-credit-workflow", "reward-redemption-device-workflow"],
      releaseGates: [
        ...releaseGates,
        { id: "privacy-safety", title: "Privacy safety gate", required: true, status: "watch" },
        { id: "device-safety", title: "Device safety gate", required: true, status: "watch" },
      ],
    },
    {
      id: "identity-family",
      title: "Identity and Family Runtime",
      owner: "family-safety",
      status: "enabled",
      priority: "P0",
      docs: ["docs/core/IDENTITY_ROLES.md", "docs/BACKEND_PLATFORM_BLUEPRINT.md"],
      capabilities: [
        "account:apple-guardian-session",
        "family:create",
        "family:guardian-join",
        "child-profile:create",
        "device-link:create",
        "device-link:revoke",
        "family-task:minimal-sync",
      ],
      dependencies: [
        { moduleId: "event-store", reason: "Family lifecycle changes emit durable events." },
        { moduleId: "runtime-safety", reason: "Family and child access requires guardian-scoped permission checks." },
      ],
      dataSensitivity: ["operational", "child_identity"],
      routes: [
        route({
          id: "runtime-email-device-start",
          plane: "runtime",
          method: "POST",
          path: "/api/v1/auth/email/device/start",
          moduleId: "identity-family",
          state: "enabled",
          readOnly: false,
          requiresAuth: false,
          dataSensitivity: ["public"],
          description: "Create a short-lived device approval code for the shared guardian email account.",
        }),
        route({
          id: "runtime-email-device-exchange",
          plane: "runtime",
          method: "POST",
          path: "/api/v1/auth/email/device/exchange",
          moduleId: "identity-family",
          state: "enabled",
          readOnly: false,
          requiresAuth: false,
          dataSensitivity: ["public"],
          description: "Exchange an approved one-time device request for an opaque guardian session.",
        }),
        route({
          id: "runtime-email-device-approve",
          plane: "runtime",
          method: "POST",
          path: "/api/v1/account/app-login/approve",
          moduleId: "identity-family",
          state: "enabled",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Approve a phone from the authenticated guardian email account on the portal.",
        }),
        route({
          id: "runtime-family-create",
          plane: "runtime",
          method: "POST",
          path: "/api/v1/families",
          moduleId: "identity-family",
          state: "enabled",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational", "child_identity"],
          description: "Create a family owned by an authenticated guardian.",
        }),
        route({
          id: "runtime-family-invite-claim",
          plane: "runtime",
          method: "POST",
          path: "/api/v1/family-invites/claim",
          moduleId: "identity-family",
          state: "enabled",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational", "child_identity"],
          description: "Consume a single-use hashed guardian or child-device invitation; guardian claims still require a session.",
        }),
        route({
          id: "runtime-family-task-sync",
          plane: "runtime",
          method: "POST",
          path: "/api/v1/families/:familyId/tasks",
          moduleId: "identity-family",
          state: "enabled",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational", "child_identity"],
          description: "Synchronize minimal task state only; excludes proof media, chat, memory, mail, and journal content.",
        }),
        route({
          id: "control-family-growth-summary",
          plane: "control",
          method: "GET",
          path: "/console/v1/families/summary",
          moduleId: "identity-family",
          state: "enabled",
          readOnly: true,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Aggregated family onboarding funnel for operators.",
        }),
      ],
      eventsProduced: ["guardian.created", "family.created", "child_profile.created", "device_link.created"],
      eventsConsumed: ["consent.revoked"],
      workflowHooks: ["consent-revocation-propagation-workflow"],
      releaseGates: [
        ...releaseGates,
        { id: "auth-provider", title: "Unified guardian email and device approval connected", required: true, status: "passed" },
        { id: "guardian-consent", title: "Versioned guardian family/task sync consent", required: true, status: "passed" },
      ],
    },
    {
      id: "book-library",
      title: "Cloud Book Library",
      owner: "content-platform",
      status: "scaffolded",
      priority: "P0",
      docs: ["docs/BACKEND_PLATFORM_BLUEPRINT.md"],
      capabilities: ["book:metadata", "book:asset-ref", "book:publish-gated", "book:download-metrics"],
      dependencies: [
        { moduleId: "event-store", reason: "Book publication and download actions emit events." },
        { moduleId: "workflow-engine", reason: "Book import and publication run through workflows." },
      ],
      dataSensitivity: ["public", "operational"],
      routes: [
        route({
          id: "control-books-list",
          plane: "control",
          method: "GET",
          path: "/console/v1/books",
          moduleId: "book-library",
          state: "enabled",
          readOnly: true,
          requiresAuth: true,
          dataSensitivity: ["public", "operational"],
          description: "Operator read model for cloud book catalog and publication state.",
        }),
        route({
          id: "runtime-books-list",
          plane: "runtime",
          method: "GET",
          path: "/public/v1/books",
          moduleId: "book-library",
          state: "enabled",
          readOnly: true,
          requiresAuth: true,
          dataSensitivity: ["public", "operational"],
          description: "Published book catalog for mobile clients.",
        }),
        route({
          id: "control-book-publish",
          plane: "control",
          method: "POST",
          path: "/console/v1/books/:bookId/publish",
          moduleId: "book-library",
          state: "gated",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["public", "operational"],
          description: "Publish a reviewed book version; requires content workflow approval.",
        }),
      ],
      eventsProduced: ["book.imported", "book.asset_attached", "book.published", "book.downloaded"],
      eventsConsumed: ["moderation.decision_made"],
      workflowHooks: ["book-import-publication-workflow", "growth-pack-publish-review-workflow"],
      releaseGates: [
        ...releaseGates,
        { id: "object-storage", title: "Object storage and signed URL policy connected", required: true, status: "missing" },
        { id: "content-review", title: "Book content review workflow connected", required: true, status: "watch" },
      ],
    },
    {
      id: "training-marketplace",
      title: "Training Marketplace",
      owner: "content-platform",
      status: "enabled",
      priority: "P0",
      docs: ["docs/ecosystem/TRAINING_MARKETPLACE_PRODUCT_MEMORY.md"],
      capabilities: [
        "marketplace:public-catalog",
        "marketplace:creator-submission",
        "marketplace:operator-review",
        "marketplace:versioned-listing",
        "marketplace:takedown",
      ],
      dependencies: [
        { moduleId: "runtime-safety", reason: "Public catalog output must remain redacted and side-effect free." },
      ],
      dataSensitivity: ["public", "operational"],
      routes: [
        route({
          id: "public-training-marketplace-list",
          plane: "runtime",
          method: "GET",
          path: "/api/v1/marketplace/listings",
          moduleId: "training-marketplace",
          state: "enabled",
          readOnly: true,
          requiresAuth: false,
          dataSensitivity: ["public"],
          description: "Redacted, reviewed, non-revoked training marketplace catalog for parent clients.",
        }),
        route({
          id: "creator-training-marketplace-submit",
          plane: "runtime",
          method: "POST",
          path: "/api/v1/marketplace/submissions",
          moduleId: "training-marketplace",
          state: "gated",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Token-gated creator submission; never publishes directly to the public catalog.",
          releaseGateIds: ["creator-service-token", "content-review", "copyright-review"],
        }),
        route({
          id: "operator-training-marketplace-review",
          plane: "control",
          method: "POST",
          path: "/api/v1/marketplace/submissions/:submissionId/review",
          moduleId: "training-marketplace",
          state: "gated",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Operator review gate for submitted marketplace versions.",
          releaseGateIds: ["operator-service-token", "content-review", "copyright-review"],
        }),
        route({
          id: "operator-training-marketplace-publish",
          plane: "control",
          method: "POST",
          path: "/api/v1/marketplace/submissions/:submissionId/publish",
          moduleId: "training-marketplace",
          state: "gated",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Explicit operator publication after approved review and integrity revalidation.",
          releaseGateIds: ["operator-service-token", "content-review", "copyright-review"],
        }),
      ],
      eventsProduced: [],
      eventsConsumed: [],
      workflowHooks: [],
      releaseGates: [
        ...releaseGates,
        { id: "database-schema", title: "Marketplace database schema and RLS", required: true, status: "passed" },
        { id: "content-review", title: "Content review and takedown policy", required: true, status: "watch" },
        { id: "creator-service-token", title: "Creator service token configured", required: true, status: "watch" },
        { id: "operator-service-token", title: "Operator service token configured", required: true, status: "watch" },
        { id: "copyright-review", title: "Copyright review workflow", required: true, status: "watch" },
      ],
    },
    {
      id: "usage-metering",
      title: "Usage and Cost Metering",
      owner: "platform",
      status: "scaffolded",
      priority: "P0",
      docs: ["docs/BACKEND_PLATFORM_BLUEPRINT.md", "docs/cloud/ANALYTICS.md"],
      capabilities: ["ai:token-metering", "app:event-metering", "operator:rollup"],
      dependencies: [
        { moduleId: "event-store", reason: "Usage rollups are linked to platform events." },
        { moduleId: "identity-family", reason: "Usage can be attributed to family and user scopes." },
      ],
      dataSensitivity: ["operational"],
      routes: [
        route({
          id: "internal-ai-usage-record",
          plane: "internal",
          method: "POST",
          path: "/internal/v1/usage/ai",
          moduleId: "usage-metering",
          state: "gated",
          readOnly: false,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Record server-side AI token and cost usage after provider calls.",
        }),
        route({
          id: "control-ai-usage-rollup",
          plane: "control",
          method: "GET",
          path: "/console/v1/usage/ai-rollup",
          moduleId: "usage-metering",
          state: "enabled",
          readOnly: true,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Operator AI token and cost rollup by family, feature, and provider.",
        }),
      ],
      eventsProduced: ["ai.usage_recorded", "app.usage_recorded"],
      eventsConsumed: ["ai.provider_response_received", "book.downloaded", "family.created"],
      workflowHooks: ["ai-cost-reconciliation-workflow"],
      releaseGates: [
        ...releaseGates,
        { id: "usage-retention", title: "Usage retention and redaction policy connected", required: true, status: "missing" },
      ],
    },
    {
      id: "integration-registry",
      title: "Cloud Integration Registry",
      owner: "platform",
      status: "scaffolded",
      priority: "P0",
      docs: ["docs/BACKEND_PLATFORM_BLUEPRINT.md"],
      capabilities: ["integration:readiness", "secret-ref:audit", "provider:inventory"],
      dependencies: [{ moduleId: "module-registry", reason: "Integrations are surfaced through module readiness." }],
      dataSensitivity: ["operational", "credential"],
      routes: [
        route({
          id: "control-integrations-list",
          plane: "control",
          method: "GET",
          path: "/console/v1/integrations",
          moduleId: "integration-registry",
          state: "enabled",
          readOnly: true,
          requiresAuth: true,
          dataSensitivity: ["operational"],
          description: "Redacted integration readiness inventory for the dashboard.",
        }),
      ],
      eventsProduced: ["integration.readiness_checked"],
      eventsConsumed: [],
      workflowHooks: ["deployment-readiness-workflow"],
      releaseGates: [
        ...releaseGates,
        { id: "secret-manager", title: "Production secret manager policy connected", required: true, status: "missing" },
      ],
    },
  ];
}

export function defaultWorkflowDefinitions(): WorkflowDefinition[] {
  return [
    {
      id: "module-release-gate-workflow",
      title: "Module Release Gate Workflow",
      triggerEventTypes: ["module.release_requested"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "collect-evidence", title: "Collect module evidence", kind: "decision", moduleId: "module-registry" },
        { id: "human-approval", title: "Owner approval", kind: "human_gate", moduleId: "workflow-engine", requiresHumanApproval: true },
      ],
    },
    {
      id: "task-completion-credit-workflow",
      title: "Task Completion to Credit Workflow",
      triggerEventTypes: ["task.submitted", "verification.decided"],
      risk: "high",
      enabled: false,
      steps: [
        { id: "verify-proof", title: "Verify proof", kind: "decision", moduleId: "runtime-safety" },
        { id: "request-credit", title: "Request credit grant", kind: "side_effect_request", moduleId: "runtime-safety", requiresHumanApproval: true },
      ],
    },
    {
      id: "reward-redemption-device-workflow",
      title: "Reward Redemption to Device Command Workflow",
      triggerEventTypes: ["reward.redemption_requested"],
      risk: "high",
      enabled: false,
      steps: [
        { id: "hold-credit", title: "Hold credit", kind: "side_effect_request", moduleId: "runtime-safety", requiresHumanApproval: true },
        { id: "queue-device-command", title: "Queue device command", kind: "side_effect_request", moduleId: "runtime-safety", requiresHumanApproval: true },
        { id: "compensate-failure", title: "Release hold on failure", kind: "compensation", moduleId: "runtime-safety" },
      ],
    },
    {
      id: "book-import-publication-workflow",
      title: "Book Import and Publication Workflow",
      triggerEventTypes: ["book.import_requested", "book.review_approved"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "store-asset-ref", title: "Store object storage reference", kind: "decision", moduleId: "book-library" },
        { id: "content-review", title: "Review copyright and age suitability", kind: "human_gate", moduleId: "book-library", requiresHumanApproval: true },
        { id: "publish-version", title: "Publish reviewed version", kind: "side_effect_request", moduleId: "book-library", requiresHumanApproval: true },
      ],
    },
    {
      id: "offline-outbox-replay-workflow",
      title: "Offline Outbox Replay Workflow",
      triggerEventTypes: ["mobile.outbox_replay_requested"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "dedupe-replay", title: "Dedupe replay by idempotency key", kind: "decision", moduleId: "event-store" },
        { id: "append-events", title: "Append accepted replay events", kind: "event", moduleId: "event-store" },
      ],
    },
    {
      id: "ai-companion-safety-escalation-workflow",
      title: "AI Companion Safety Escalation Workflow",
      triggerEventTypes: ["ai.safety_risk_detected"],
      risk: "high",
      enabled: false,
      steps: [
        { id: "classify-risk", title: "Classify safety risk", kind: "decision", moduleId: "runtime-safety" },
        { id: "guardian-review", title: "Guardian or safety review", kind: "human_gate", moduleId: "runtime-safety", requiresHumanApproval: true },
      ],
    },
    {
      id: "growth-pack-publish-review-workflow",
      title: "Growth Pack Publish Review Workflow",
      triggerEventTypes: ["growth_pack.publish_requested"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "content-review", title: "Review growth pack content", kind: "human_gate", moduleId: "book-library", requiresHumanApproval: true },
        { id: "publish-approved", title: "Publish approved package", kind: "side_effect_request", moduleId: "book-library", requiresHumanApproval: true },
      ],
    },
    {
      id: "school-homework-credit-handoff-workflow",
      title: "School Homework Credit Handoff Workflow",
      triggerEventTypes: ["school.homework_verified"],
      risk: "high",
      enabled: false,
      steps: [
        { id: "verify-school-scope", title: "Verify school and family scope", kind: "decision", moduleId: "runtime-safety" },
        { id: "guardian-credit-review", title: "Guardian credit review", kind: "human_gate", moduleId: "runtime-safety", requiresHumanApproval: true },
      ],
    },
    {
      id: "consent-revocation-propagation-workflow",
      title: "Consent Revocation Propagation Workflow",
      triggerEventTypes: ["consent.revoked"],
      risk: "high",
      enabled: false,
      steps: [
        { id: "identify-affected-resources", title: "Identify affected child resources", kind: "decision", moduleId: "identity-family" },
        { id: "queue-redaction", title: "Queue redaction and cache invalidation", kind: "side_effect_request", moduleId: "runtime-safety", requiresHumanApproval: true },
      ],
    },
    {
      id: "billing-entitlement-reconciliation-workflow",
      title: "Billing Entitlement Reconciliation Workflow",
      triggerEventTypes: ["billing.webhook_received", "entitlement.reconcile_requested"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "validate-provider-event", title: "Validate provider event", kind: "decision", moduleId: "integration-registry" },
        { id: "reconcile-entitlement", title: "Reconcile entitlement projection", kind: "decision", moduleId: "usage-metering" },
      ],
    },
    {
      id: "moderation-visibility-sync-workflow",
      title: "Moderation Visibility Sync Workflow",
      triggerEventTypes: ["moderation.decision_made"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "apply-visibility", title: "Apply approved visibility projection", kind: "decision", moduleId: "book-library" },
        { id: "invalidate-cache", title: "Invalidate public cache", kind: "side_effect_request", moduleId: "book-library", requiresHumanApproval: true },
      ],
    },
    {
      id: "deployment-readiness-workflow",
      title: "Deployment Readiness Workflow",
      triggerEventTypes: ["deployment.readiness_requested"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "check-integrations", title: "Check integration readiness", kind: "decision", moduleId: "integration-registry" },
        { id: "operator-approval", title: "Operator deployment approval", kind: "human_gate", moduleId: "integration-registry", requiresHumanApproval: true },
      ],
    },
    {
      id: "ai-cost-reconciliation-workflow",
      title: "AI Usage Cost Reconciliation Workflow",
      triggerEventTypes: ["ai.usage_recorded"],
      risk: "sensitive",
      enabled: true,
      steps: [
        { id: "rollup-usage", title: "Roll up usage by family and feature", kind: "decision", moduleId: "usage-metering" },
        { id: "flag-budget-risk", title: "Flag budget anomalies", kind: "decision", moduleId: "usage-metering" },
      ],
    },
  ];
}

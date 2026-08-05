import test from "node:test";
import assert from "node:assert/strict";
import { createOctoTeacherPlatform } from "./app/default-platform.js";

test("registers modules, routes, and workflow definitions", () => {
  const platform = createOctoTeacherPlatform();

  assert.ok(platform.modules.get("module-registry"));
  assert.ok(platform.modules.get("event-store"));
  assert.ok(platform.modules.get("workflow-engine"));
  assert.ok(platform.workflows.get("module-release-gate-workflow"));
  assert.ok(platform.workflows.get("task-completion-credit-workflow"));
  assert.equal(platform.routes.get("control-modules-list")?.plane, "control");
});

test("stores events append-only and rejects duplicate event ids", () => {
  const platform = createOctoTeacherPlatform();

  const event = {
    id: "event_1",
    type: "module.release_requested",
    schemaVersion: 1,
    source: "test",
    familyId: "family:test",
    aggregate: { type: "module", id: "module-registry", version: 1 },
    occurredAt: "2026-07-09T00:00:00.000Z",
    correlationId: "corr_1",
    payload: { moduleId: "module-registry" },
  };

  platform.events.append(event);
  assert.equal(platform.events.list({ type: "module.release_requested" }).length, 1);
  assert.throws(() => platform.events.append(event), /Duplicate event id/);
});

test("keeps high-risk workflows and dangerous routes disabled by default", () => {
  const platform = createOctoTeacherPlatform();

  assert.equal(platform.workflows.get("task-completion-credit-workflow")?.enabled, false);
  assert.equal(platform.workflows.get("reward-redemption-device-workflow")?.enabled, false);
  assert.equal(platform.routes.get("runtime-device-command")?.state, "disabled");
  assert.equal(platform.routes.get("runtime-credit-direct-adjust")?.state, "disabled");
});

test("route audit allows disabled dangerous routes and blocks accidental enablement", () => {
  const platform = createOctoTeacherPlatform();

  assert.deepEqual(platform.routes.audit(), []);

  platform.routes.register({
    id: "bad-device-command",
    plane: "runtime",
    method: "POST",
    path: "/public/v1/bad-device-command",
    moduleId: "runtime-safety",
    state: "enabled",
    readOnly: false,
    requiresAuth: true,
    dataSensitivity: ["operational"],
    description: "Test-only unsafe route.",
    releaseGateIds: ["dangerous-side-effect"],
  });

  assert.equal(platform.routes.audit().some((finding) => finding.code === "dangerous_enabled"), true);
});

test("permission gate denies sensitive or side-effecting requests by default", () => {
  const platform = createOctoTeacherPlatform();

  const sideEffect = platform.permissions.decide({
    actorId: "actor:test",
    role: "guardian",
    familyId: "family:test",
    action: "execute_side_effect",
    resource: "device-command",
    dataSensitivity: ["operational"],
  });

  const teacherTranscript = platform.permissions.decide({
    actorId: "actor:teacher",
    role: "teacher",
    familyId: "family:test",
    childId: "child:test",
    action: "read",
    resource: "ai-session",
    dataSensitivity: ["ai_transcript"],
  });

  assert.equal(sideEffect.allowed, false);
  assert.equal(teacherTranscript.allowed, false);
});

test("audit log is append-only and duplicate-safe", () => {
  const platform = createOctoTeacherPlatform();

  const record = {
    id: "audit_1",
    occurredAt: "2026-07-09T00:00:00.000Z",
    actorId: "actor:test",
    actorRole: "worker",
    action: "module.audit",
    resource: "module-registry",
    decision: "recorded" as const,
    reasonCode: "test",
    correlationId: "corr_1",
  };

  platform.audit.append(record);
  assert.equal(platform.audit.list().length, 1);
  assert.throws(() => platform.audit.append(record), /Duplicate audit record id/);
});

import type { OctoTeacherPlatform } from "./default-platform.js";

export type PlatformReadinessFinding = {
  severity: "block" | "warn";
  code:
    | "missing_workflow_definition"
    | "high_risk_workflow_enabled"
    | "dangerous_route_not_disabled"
    | "credential_route_not_internal"
    | "production_dangerous_flag";
  ref: string;
  message: string;
};

export function auditPlatformReadiness(platform: OctoTeacherPlatform): PlatformReadinessFinding[] {
  const findings: PlatformReadinessFinding[] = [];
  const workflowIds = new Set(platform.workflows.list().map((workflow) => workflow.id));

  for (const manifest of platform.modules.list()) {
    for (const hook of manifest.workflowHooks) {
      if (!workflowIds.has(hook)) {
        findings.push({
          severity: "block",
          code: "missing_workflow_definition",
          ref: `${manifest.id}:${hook}`,
          message: `Module ${manifest.id} references missing workflow ${hook}.`,
        });
      }
    }
  }

  for (const workflow of platform.workflows.list()) {
    if (workflow.risk === "high" && workflow.enabled) {
      findings.push({
        severity: "block",
        code: "high_risk_workflow_enabled",
        ref: workflow.id,
        message: `High-risk workflow ${workflow.id} must be disabled until release evidence passes.`,
      });
    }
  }

  for (const route of platform.routes.list()) {
    if (route.releaseGateIds?.includes("dangerous-side-effect") && route.state !== "disabled") {
      findings.push({
        severity: "block",
        code: "dangerous_route_not_disabled",
        ref: route.id,
        message: `Dangerous route ${route.id} must stay disabled by default.`,
      });
    }
    if (route.dataSensitivity.includes("credential") && route.plane !== "internal") {
      findings.push({
        severity: "block",
        code: "credential_route_not_internal",
        ref: route.id,
        message: `Credential-sensitive route ${route.id} must stay internal.`,
      });
    }
  }

  if (platform.env.environment === "production" && (platform.env.enableDangerousRoutes || platform.env.enableRuntimeWrites)) {
    findings.push({
      severity: "block",
      code: "production_dangerous_flag",
      ref: "env",
      message: "Production cannot boot with dangerous routes or runtime writes enabled by environment flag.",
    });
  }

  return findings;
}

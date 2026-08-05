import type { PermissionDecision, PermissionGate, PermissionRequest } from "./types.js";

const sensitive = new Set(["child_privacy", "child_health", "ai_transcript", "payment", "credential"]);

export class DefaultPermissionGate implements PermissionGate {
  decide(request: PermissionRequest): PermissionDecision {
    if (request.action === "execute_side_effect") {
      return deny("side_effect_disabled", "Side effects require an explicit workflow gate.");
    }

    if (request.dataSensitivity.some((item) => sensitive.has(item)) && request.role !== "guardian" && request.role !== "worker") {
      return deny("sensitive_data_denied", "Sensitive data requires guardian or trusted worker scope.");
    }

    if (request.role === "child" && (request.action === "approve" || request.action === "publish")) {
      return deny("child_role_limited", "Child role cannot approve or publish.");
    }

    if (request.action !== "read") {
      return deny("default_write_denied", "Writes require an explicit route, workflow, and consent-aware policy.");
    }

    if (request.dataSensitivity.some((item) => item !== "public" && item !== "operational")) {
      return deny("default_sensitive_read_denied", "Sensitive reads require explicit production policy.");
    }

    return {
      allowed: true,
      reasonCode: "allowed_readonly_stub_policy",
      explanation: "Allowed only for non-sensitive read in scaffold policy; production must replace this with consent-aware RBAC/ABAC.",
    };
  }
}

function deny(reasonCode: string, explanation: string): PermissionDecision {
  return { allowed: false, reasonCode, explanation };
}

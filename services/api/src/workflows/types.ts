export type WorkflowRisk = "low" | "sensitive" | "high";
export type WorkflowStepKind = "event" | "decision" | "human_gate" | "side_effect_request" | "compensation";

export type WorkflowStepDefinition = {
  id: string;
  title: string;
  kind: WorkflowStepKind;
  moduleId: string;
  timeoutSeconds?: number;
  retryLimit?: number;
  requiresHumanApproval?: boolean;
};

export type WorkflowDefinition = {
  id: string;
  title: string;
  triggerEventTypes: string[];
  risk: WorkflowRisk;
  enabled: boolean;
  steps: WorkflowStepDefinition[];
};

export type WorkflowInstanceStatus = "pending" | "running" | "waiting_for_human" | "completed" | "failed" | "rolled_back";

export type WorkflowInstance = {
  id: string;
  definitionId: string;
  status: WorkflowInstanceStatus;
  correlationId: string;
  startedAt: string;
  completedAt?: string;
  currentStepId?: string;
};

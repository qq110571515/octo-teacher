export type AiUsageEvent = {
  id: string;
  familyId?: string;
  userId?: string;
  feature: "child_companion" | "parent_coach" | "book_import" | "proof_review" | "operator_tool";
  provider: "openai" | "local_qwen" | "mock";
  model: string;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  occurredAt: string;
};

export type AppUsageEvent = {
  id: string;
  kind: "app_install" | "app_open" | "family_created" | "child_profile_created" | "book_downloaded";
  platform: "ios" | "web" | "unknown";
  familyId?: string;
  userId?: string;
  occurredAt: string;
};

export type UsageRollup = {
  familyId?: string;
  feature?: string;
  totalInputTokens: number;
  totalOutputTokens: number;
  totalCostUsd: number;
  eventCount: number;
};

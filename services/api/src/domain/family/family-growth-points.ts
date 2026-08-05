import {
  FamilyCloudError,
  type FamilyGrowthPointMutationKind,
  type FamilyTaskCloudRecord,
} from "./cloud-types.js";

export type FamilyGrowthPointMutation = {
  mutationRef: string;
  kind: FamilyGrowthPointMutationKind;
  delta: number;
  sourceRef: string;
};

export function shouldAwardTaskGrowthPoints(
  previous: FamilyTaskCloudRecord["status"] | undefined,
  next: FamilyTaskCloudRecord["status"],
): boolean {
  return next === "approved" && previous !== "approved";
}

function ledgerRef(value: unknown, code: string): string {
  if (typeof value !== "string") throw new FamilyCloudError(code);
  const normalized = value.trim();
  if (normalized.length < 8 || normalized.length > 160 || !/^[A-Za-z0-9:._-]+$/.test(normalized)) {
    throw new FamilyCloudError(code);
  }
  return normalized;
}

export function normalizeGrowthPointMutation(value: unknown): FamilyGrowthPointMutation {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_points_mutation");
  }
  const raw = value as Record<string, unknown>;
  if (raw.kind !== "screen_time_spend" && raw.kind !== "screen_time_refund") {
    throw new FamilyCloudError("invalid_points_mutation_kind");
  }
  if (!Number.isSafeInteger(raw.delta) || Number(raw.delta) === 0 || Math.abs(Number(raw.delta)) > 1_000_000) {
    throw new FamilyCloudError("invalid_points_delta");
  }
  const delta = Number(raw.delta);
  if ((raw.kind === "screen_time_spend" && delta >= 0) ||
      (raw.kind === "screen_time_refund" && delta <= 0)) {
    throw new FamilyCloudError("invalid_points_delta");
  }
  return {
    mutationRef: ledgerRef(raw.mutationRef, "invalid_mutation_ref"),
    kind: raw.kind,
    delta,
    sourceRef: ledgerRef(raw.sourceRef, "invalid_source_ref"),
  };
}

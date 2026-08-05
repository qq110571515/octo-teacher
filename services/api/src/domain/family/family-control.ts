import { sha256 } from "../../auth/apple-identity.js";
import { FamilyCloudError } from "./cloud-types.js";

export const FAMILY_SYNC_PAGE_LIMIT = 200;
export const FAMILY_ACTIVITY_SUMMARY_DAYS = 90;

export const FAMILY_CONTENT_KINDS = ["book", "video", "creation"] as const;
export type FamilyContentKind = typeof FAMILY_CONTENT_KINDS[number];
export const FAMILY_CONTENT_SOURCES = [
  "marketplace", "cloud_library", "guardian_upload", "external", "generated",
] as const;
export type FamilyContentSource = typeof FAMILY_CONTENT_SOURCES[number];
export type FamilySyncEntityKind =
  | "family" | "guardian" | "child" | "device" | "task" | "points"
  | "content" | "content_assignment" | "activity";

export type FamilySyncChange = {
  cursor: string;
  childProfileId?: string;
  entityKind: FamilySyncEntityKind;
  entityRef: string;
  operation: "upsert" | "remove";
  entityVersion: number;
  changedAt: string;
};

export function resolveUniqueActiveGuardianFamily<T extends { familyId: string }>(
  memberships: T[],
  requestedFamilyId?: string,
): T {
  const unique = [...new Map(memberships.map((entry) => [entry.familyId, entry])).values()];
  if (unique.length === 0) throw new FamilyCloudError("family_access_denied");
  if (unique.length > 1) throw new FamilyCloudError("guardian_multiple_active_families");
  if (requestedFamilyId && unique[0]!.familyId !== requestedFamilyId) {
    throw new FamilyCloudError("family_access_denied");
  }
  return unique[0]!;
}

export type NormalizedFamilyContent = {
  mutationRef: string;
  clientRef: string;
  kind: FamilyContentKind;
  title: string;
  titleEnglish?: string;
  sourceKind: FamilyContentSource;
  sourceRef?: string;
  storageObjectKey?: string;
  availability: "processing" | "ready" | "unavailable";
  metadata: Record<string, string | number | boolean | null>;
  payloadHash: string;
};

const CONTENT_KEYS = new Set([
  "mutationRef", "clientRef", "kind", "title", "titleEnglish", "sourceKind",
  "sourceRef", "storageObjectKey", "availability", "metadata", "baseVersion",
]);
const FORBIDDEN_METADATA_KEY = /(?:api.?key|secret|token|authorization|chat|message|evidence|raw.?text|email.?body|family.?controls|managed.?settings)/i;
const FORBIDDEN_VALUE = /(?:\bsk-[A-Za-z0-9_-]{12,}\b|bearer\s+[A-Za-z0-9._-]{12,}|data:|file:\/\/)/i;

function object(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new FamilyCloudError(code);
  return value as Record<string, unknown>;
}

function text(value: unknown, code: string, maximum: number): string {
  if (typeof value !== "string") throw new FamilyCloudError(code);
  const normalized = value.trim();
  if (!normalized || normalized.length > maximum || /[\u0000-\u001f\u007f]/.test(normalized)) {
    throw new FamilyCloudError(code);
  }
  return normalized;
}

export function normalizeFamilySyncCursor(value: unknown): string {
  if (value === undefined || value === null || value === "") return "0";
  if (typeof value !== "string" || !/^\d{1,19}$/.test(value)) {
    throw new FamilyCloudError("invalid_family_sync_cursor");
  }
  const cursor = BigInt(value);
  if (cursor > 9_223_372_036_854_775_807n) throw new FamilyCloudError("invalid_family_sync_cursor");
  return cursor.toString();
}

export function normalizeMutationReference(value: unknown): string {
  const normalized = text(value, "invalid_mutation_ref", 160);
  if (!/^[A-Za-z0-9][A-Za-z0-9:_-]{7,159}$/.test(normalized)) {
    throw new FamilyCloudError("invalid_mutation_ref");
  }
  return normalized;
}

function normalizeMetadata(value: unknown): Record<string, string | number | boolean | null> {
  if (value === undefined || value === null) return {};
  const raw = object(value, "invalid_content_metadata");
  const normalized: Record<string, string | number | boolean | null> = {};
  for (const [key, entry] of Object.entries(raw)) {
    if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(key) || FORBIDDEN_METADATA_KEY.test(key)) {
      throw new FamilyCloudError("forbidden_content_metadata");
    }
    if (entry !== null && typeof entry !== "string" && typeof entry !== "number" && typeof entry !== "boolean") {
      throw new FamilyCloudError("invalid_content_metadata");
    }
    if (typeof entry === "string" && (entry.length > 500 || FORBIDDEN_VALUE.test(entry))) {
      throw new FamilyCloudError("forbidden_content_metadata");
    }
    normalized[key] = entry;
  }
  if (JSON.stringify(normalized).length > 16_384) throw new FamilyCloudError("content_metadata_too_large");
  return normalized;
}

function stableObject(value: Record<string, string | number | boolean | null>): Record<string, string | number | boolean | null> {
  return Object.fromEntries(Object.entries(value).sort(([left], [right]) => left.localeCompare(right)));
}

export function normalizeFamilyContent(value: unknown): NormalizedFamilyContent {
  const raw = object(value, "invalid_family_content");
  if (Object.keys(raw).some((key) => !CONTENT_KEYS.has(key))) {
    throw new FamilyCloudError("forbidden_family_content_field");
  }
  const mutationRef = normalizeMutationReference(raw.mutationRef);
  const clientRef = normalizeMutationReference(raw.clientRef);
  if (!FAMILY_CONTENT_KINDS.includes(raw.kind as FamilyContentKind)) {
    throw new FamilyCloudError("invalid_content_kind");
  }
  if (!FAMILY_CONTENT_SOURCES.includes(raw.sourceKind as FamilyContentSource)) {
    throw new FamilyCloudError("invalid_content_source");
  }
  const title = text(raw.title, "invalid_content_title", 240);
  const titleEnglish = raw.titleEnglish === undefined || raw.titleEnglish === null
    ? undefined : text(raw.titleEnglish, "invalid_content_title", 240);
  const sourceRef = raw.sourceRef === undefined || raw.sourceRef === null
    ? undefined : text(raw.sourceRef, "invalid_content_source_ref", 240);
  const storageObjectKey = raw.storageObjectKey === undefined || raw.storageObjectKey === null
    ? undefined : text(raw.storageObjectKey, "invalid_content_storage_key", 500);
  const availability = raw.availability === undefined ? "processing" : raw.availability;
  if (!["processing", "ready", "unavailable"].includes(String(availability))) {
    throw new FamilyCloudError("invalid_content_availability");
  }
  if (FORBIDDEN_VALUE.test(sourceRef ?? "") || FORBIDDEN_VALUE.test(storageObjectKey ?? "")) {
    throw new FamilyCloudError("forbidden_content_reference");
  }
  const metadata = normalizeMetadata(raw.metadata);
  const stable = JSON.stringify({
    clientRef, kind: raw.kind, title, titleEnglish: titleEnglish ?? null,
    sourceKind: raw.sourceKind, sourceRef: sourceRef ?? null,
    storageObjectKey: storageObjectKey ?? null, availability, metadata: stableObject(metadata),
  });
  return {
    mutationRef, clientRef, kind: raw.kind as FamilyContentKind, title,
    ...(titleEnglish ? { titleEnglish } : {}), sourceKind: raw.sourceKind as FamilyContentSource,
    ...(sourceRef ? { sourceRef } : {}), ...(storageObjectKey ? { storageObjectKey } : {}),
    availability: availability as NormalizedFamilyContent["availability"], metadata,
    payloadHash: sha256(stable),
  };
}

export function childCanSeeFamilyChange(change: FamilySyncChange, childProfileId: string): boolean {
  if (change.entityKind === "family") return true;
  if (change.entityKind === "guardian" || change.entityKind === "content") return false;
  return change.childProfileId === childProfileId;
}

export function requireSafeGuardianRevocation(input: {
  actorGuardianId: string;
  targetGuardianId: string;
  targetIsCreator: boolean;
}): void {
  if (input.actorGuardianId === input.targetGuardianId) throw new FamilyCloudError("guardian_self_revoke_forbidden");
  if (input.targetIsCreator) throw new FamilyCloudError("family_creator_revoke_forbidden");
}

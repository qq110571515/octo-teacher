import { FamilyCloudError } from "./cloud-types.js";

export const FAMILY_EXPORT_VERSION = "2026-07-family-export-v1";

export function familyDeletionConfirmation(publicRef: string): string {
  return `DELETE ${publicRef}`;
}

export function requireFamilyDeletionConfirmation(publicRef: string, confirmation: unknown): void {
  if (confirmation !== familyDeletionConfirmation(publicRef)) {
    throw new FamilyCloudError("family_deletion_confirmation_invalid");
  }
}

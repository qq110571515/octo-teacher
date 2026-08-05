import { randomBytes } from "node:crypto";
import { sha256 } from "../../auth/apple-identity.js";
import { FamilyCloudError } from "./cloud-types.js";

const PORTAL_LINK_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const PORTAL_LINK_CODE_LENGTH = 12;

export type PortalLinkClaimState = {
  status: "issued" | "consumed" | "revoked" | "expired";
  expiresAt: string;
  consumedByAccountId?: string;
};

export function resolveAccountIdentityLink(
  linkedAccountId: string | undefined,
  requestedAccountId: string,
): "insert" | "refresh" {
  if (!linkedAccountId) return "insert";
  if (linkedAccountId === requestedAccountId) return "refresh";
  throw new FamilyCloudError("portal_apple_identity_already_linked");
}

export function generatePortalLinkCode(): string {
  const bytes = randomBytes(PORTAL_LINK_CODE_LENGTH);
  const raw = Array.from(bytes, (byte) => PORTAL_LINK_CODE_ALPHABET[byte % PORTAL_LINK_CODE_ALPHABET.length]).join("");
  return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`;
}

export function normalizePortalLinkCode(value: unknown): string {
  if (typeof value !== "string") throw new FamilyCloudError("invalid_portal_link_code");
  const normalized = value.toUpperCase().replace(/[\s-]/g, "");
  const pattern = new RegExp(`^[${PORTAL_LINK_CODE_ALPHABET}]{${PORTAL_LINK_CODE_LENGTH}}$`);
  if (!pattern.test(normalized)) throw new FamilyCloudError("invalid_portal_link_code");
  return normalized;
}

export function portalLinkCodeHash(value: unknown): string {
  return sha256(normalizePortalLinkCode(value));
}

export function resolvePortalLinkClaim(
  state: PortalLinkClaimState | undefined,
  accountId: string,
  now = new Date(),
): "consume" | "idempotent" {
  if (!state) throw new FamilyCloudError("portal_link_not_found");
  if (state.status === "consumed") {
    if (state.consumedByAccountId === accountId) return "idempotent";
    throw new FamilyCloudError("portal_link_consumed");
  }
  if (state.status !== "issued") throw new FamilyCloudError("portal_link_unavailable");
  if (Date.parse(state.expiresAt) <= now.getTime()) throw new FamilyCloudError("portal_link_expired");
  return "consume";
}

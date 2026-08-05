import { timingSafeEqual } from "node:crypto";

export type ServiceTokenResult = "authorized" | "not_configured" | "unauthorized";

function equalSecret(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}

export function authorizeBearerToken(authorization: string | undefined, expectedToken: string | undefined): ServiceTokenResult {
  if (!expectedToken) return "not_configured";
  if (!authorization?.startsWith("Bearer ")) return "unauthorized";
  const supplied = authorization.slice("Bearer ".length).trim();
  if (!supplied || !equalSecret(supplied, expectedToken)) return "unauthorized";
  return "authorized";
}

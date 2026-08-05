import { loadPlatformEnv } from "../../../src/config/env.js";
import { bootstrapPendingAccount, loadAccountForIdentity } from "../../../src/domain/accounts/postgres-platform-accounts.js";
import { applyPortalCors, readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";
import { requirePlatformIdentity } from "../../_account-auth.js";

type RegistrationInput = { handle?: string; displayName?: string };

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  const identity = await requirePlatformIdentity(req, res);
  if (!identity) return;
  try {
    if ((req.method ?? "GET") === "GET") {
      const account = await loadAccountForIdentity(identity);
      writeJson(res, 200, { account: account ?? null, isOwnerApprover: identity.isOwnerApprover });
      return;
    }
    if (req.method === "POST") {
      if (!loadPlatformEnv().accountRegistrationEnabled) {
        writeJson(res, 403, { error: "closed_beta_registration_disabled" });
        return;
      }
      const body = (readJsonBody(req) ?? {}) as RegistrationInput;
      const account = await bootstrapPendingAccount(identity, body);
      writeJson(res, account.status === "pending" ? 202 : 200, { account, isOwnerApprover: identity.isOwnerApprover });
      return;
    }
    writeJson(res, 405, { error: "method_not_allowed" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "account_unavailable";
    writeJson(res, message.includes("unique") ? 409 : 503, { error: "account_unavailable" });
  }
}

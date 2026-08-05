import { authorizeBearerToken } from "../src/auth/service-token.js";
import { requestHeader, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";

export type MarketplaceOperationRole = "creator" | "operator";

export function requireMarketplaceOperation(
  req: ApiRequest,
  res: ApiResponse,
  role: MarketplaceOperationRole,
): boolean {
  if (process.env.MARKETPLACE_OPERATIONS_ENABLED !== "true") {
    writeJson(res, 503, { error: "marketplace_operations_disabled" });
    return false;
  }
  const expected = role === "creator" ? process.env.MARKETPLACE_CREATOR_TOKEN : process.env.MARKETPLACE_OPERATOR_TOKEN;
  const result = authorizeBearerToken(requestHeader(req, "authorization"), expected);
  if (result === "not_configured") {
    writeJson(res, 503, { error: "marketplace_operations_not_configured" });
    return false;
  }
  if (result === "unauthorized") {
    res.setHeader("www-authenticate", "Bearer");
    writeJson(res, 401, { error: "unauthorized" });
    return false;
  }
  return true;
}

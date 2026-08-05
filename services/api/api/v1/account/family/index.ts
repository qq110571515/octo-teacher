import {
  deleteLinkedFamily,
  loadLinkedFamilyConsole,
  renameLinkedFamily,
} from "../../../../src/domain/family/postgres-family-portal.js";
import { requirePlatformIdentity } from "../../../_account-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { applyPortalCors, readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

function requestedTimeZone(req: ApiRequest): string {
  const raw = req.query?.timeZone;
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (!value || value.length > 100) return "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return value;
  } catch {
    return "UTC";
  }
}

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  if (!["GET", "PATCH", "DELETE"].includes(req.method ?? "GET")) {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const identity = await requirePlatformIdentity(req, res);
    if (!identity) return;
    if ((req.method ?? "GET") === "GET") {
      writeJson(res, 200, {
        family: await loadLinkedFamilyConsole(identity, requestedTimeZone(req)),
      });
      return;
    }
    const body = readJsonBody(req);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new Error("invalid_json");
    }
    if (req.method === "PATCH") {
      writeJson(res, 200, await renameLinkedFamily(
        identity,
        (body as Record<string, unknown>).displayName,
      ));
      return;
    }
    const result = await deleteLinkedFamily(
      identity,
      (body as Record<string, unknown>).confirmation,
    );
    writeJson(res, 200, { deleted: true, ...result });
  } catch (error) {
    writeFamilyError(res, error, "linked_family_console_unavailable");
  }
}

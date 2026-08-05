import { createFamily, loadCurrentFamily } from "../../../src/domain/family/postgres-family-cloud.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";
import { requireGuardianSession } from "../../_family-auth.js";
import { writeFamilyError } from "../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    if ((req.method ?? "GET") === "GET") {
      writeJson(res, 200, { family: await loadCurrentFamily(context) });
      return;
    }
    if (req.method === "POST") {
      const raw = readJsonBody(req);
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
      const body = raw as Record<string, unknown>;
      if (typeof body.displayName !== "string" || typeof body.deviceName !== "string" || !Array.isArray(body.children) ||
          typeof body.consentVersion !== "string") {
        writeJson(res, 400, { error: "family_fields_required" });
        return;
      }
      const children = body.children.map((child) => child as {
        clientRef: string;
        displayName: string;
        birthYear?: number;
        preReaderMode?: boolean;
        interfaceLanguage?: "chinese" | "english";
        contentLanguage?: "chinese" | "english" | "bilingual";
        dailyLimitMinutes?: number;
        exchangePolicy?: unknown;
      });
      writeJson(res, 201, { family: await createFamily({
        context, displayName: body.displayName, deviceName: body.deviceName, children,
        consentVersion: body.consentVersion,
        familySyncAccepted: body.familySyncAccepted === true,
        childTaskSyncAccepted: body.childTaskSyncAccepted === true,
      }) });
      return;
    }
    writeJson(res, 405, { error: "method_not_allowed" });
  } catch (error) {
    writeFamilyError(res, error, "family_endpoint_unavailable");
  }
}

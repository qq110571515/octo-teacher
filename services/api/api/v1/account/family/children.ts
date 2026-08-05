import { randomUUID } from "node:crypto";
import { requirePlatformIdentity } from "../../../_account-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { applyPortalCors, readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { FamilyCloudError } from "../../../../src/domain/family/cloud-types.js";
import { createChildProfile } from "../../../../src/domain/family/postgres-family-cloud.js";
import { archiveFamilyChild } from "../../../../src/domain/family/postgres-family-control.js";
import { loadLinkedGuardian } from "../../../../src/domain/family/postgres-family-portal.js";

type CreateChildBody = {
  displayName?: unknown;
  age?: unknown;
};

type ArchiveChildBody = {
  childId?: unknown;
};

function childName(value: unknown): string {
  if (typeof value !== "string") throw new FamilyCloudError("invalid_child_name");
  const name = value.trim();
  if (!name || name.length > 80) throw new FamilyCloudError("invalid_child_name");
  return name;
}

function childAge(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 3 || value > 18) {
    throw new FamilyCloudError("invalid_child_age");
  }
  return value;
}

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  const method = req.method ?? "GET";
  if (method !== "POST" && method !== "DELETE") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }

  try {
    const identity = await requirePlatformIdentity(req, res);
    if (!identity) return;
    const linked = await loadLinkedGuardian(identity);
    const context = {
      sessionId: "portal-account",
      guardianId: linked.guardianId,
      devicePublicRef: "portal-account",
    };

    if (method === "POST") {
      const body = (readJsonBody(req) ?? {}) as CreateChildBody;
      const displayName = childName(body.displayName);
      const age = childAge(body.age);
      const currentYear = new Date().getUTCFullYear();
      await createChildProfile({
        context,
        familyId: linked.familyId,
        clientRef: randomUUID(),
        displayName,
        birthYear: currentYear - age,
        preReaderMode: age <= 7,
        interfaceLanguage: "chinese",
        contentLanguage: "chinese",
        dailyLimitMinutes: 60,
      });
      writeJson(res, 201, { created: true });
      return;
    }

    const body = (readJsonBody(req) ?? {}) as ArchiveChildBody;
    if (typeof body.childId !== "string" || !body.childId) {
      throw new FamilyCloudError("child_profile_not_found");
    }
    const result = await archiveFamilyChild({
      context,
      familyId: linked.familyId,
      childProfileId: body.childId,
    });
    writeJson(res, 200, result);
  } catch (error) {
    writeFamilyError(res, error, "account_family_child_change_failed");
  }
}

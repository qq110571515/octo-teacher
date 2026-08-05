import { loadGuardianLearningActivitySummary } from "../../../../../../src/domain/family/postgres-family-control.js";
import {
  normalizeActivitySummaryDate,
  normalizeActivitySummaryTimeZone,
  normalizeActivitySummaryWindowDays,
} from "../../../../../../src/domain/family/family-activity.js";
import { requireGuardianSession } from "../../../../../_family-auth.js";
import { writeFamilyError } from "../../../../../_family-errors.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res); if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const childProfileId = Array.isArray(req.query?.childId) ? req.query?.childId[0] : req.query?.childId;
    const days = Array.isArray(req.query?.days) ? req.query?.days[0] : req.query?.days;
    const date = Array.isArray(req.query?.date) ? req.query?.date[0] : req.query?.date;
    const timeZone = Array.isArray(req.query?.timeZone) ? req.query?.timeZone[0] : req.query?.timeZone;
    if (!familyId || !childProfileId) throw new Error("invalid_json");
    writeJson(res, 200, await loadGuardianLearningActivitySummary({
      context,
      familyId,
      childProfileId,
      windowDays: normalizeActivitySummaryWindowDays(days),
      localDate: normalizeActivitySummaryDate(date),
      timeZone: normalizeActivitySummaryTimeZone(timeZone),
    }));
  } catch (error) { writeFamilyError(res, error, "activity_summary_unavailable"); }
}

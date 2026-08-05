import { createOctoTeacherPlatform } from "../src/app/default-platform.js";
import { auditPlatformReadiness } from "../src/app/platform-readiness.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";

export default function handler(req: ApiRequest, res: ApiResponse): void {
  if (!requireGet(req, res)) return;

  const platform = createOctoTeacherPlatform();
  const findings = auditPlatformReadiness(platform);
  writeJson(res, findings.some((finding) => finding.severity === "block") ? 503 : 200, {
    ok: findings.length === 0,
    findings,
  });
}

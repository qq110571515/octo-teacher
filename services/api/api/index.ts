import { createOctoTeacherPlatform } from "../src/app/default-platform.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";

export default function handler(req: ApiRequest, res: ApiResponse): void {
  if (!requireGet(req, res)) return;

  const platform = createOctoTeacherPlatform();
  writeJson(res, 200, {
    ok: true,
    service: "Octo Teacher Platform API",
    environment: platform.env.environment,
    message: "Octo Teacher cloud services are online.",
    endpoints: {
      health: "/api/health",
      readiness: "/api/readiness",
      modules: "/api/modules",
      integrations: "/api/integrations",
    },
  });
}

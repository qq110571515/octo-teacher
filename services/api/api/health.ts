import { createOctoTeacherPlatform } from "../src/app/default-platform.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";

export default function handler(req: ApiRequest, res: ApiResponse): void {
  if (!requireGet(req, res)) return;

  const platform = createOctoTeacherPlatform();
  writeJson(res, 200, {
    ok: true,
    service: "octoteacher-platform-api",
    environment: platform.env.environment,
    modules: platform.modules.list().length,
    workflows: platform.workflows.list().length,
    dangerousRoutesEnabled: platform.env.enableDangerousRoutes,
    runtimeWritesEnabled: platform.env.enableRuntimeWrites,
  });
}

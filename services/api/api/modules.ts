import { createOctoTeacherPlatform } from "../src/app/default-platform.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";

export default function handler(req: ApiRequest, res: ApiResponse): void {
  if (!requireGet(req, res)) return;

  const platform = createOctoTeacherPlatform();
  writeJson(res, 200, {
    modules: platform.modules.list().map((manifest) => ({
      id: manifest.id,
      title: manifest.title,
      owner: manifest.owner,
      status: manifest.status,
      priority: manifest.priority,
      capabilities: manifest.capabilities,
      workflowHooks: manifest.workflowHooks,
      routes: manifest.routes.map((route) => ({
        id: route.id,
        plane: route.plane,
        method: route.method,
        path: route.path,
        state: route.state,
        readOnly: route.readOnly,
      })),
    })),
  });
}

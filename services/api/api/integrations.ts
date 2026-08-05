import { createOctoTeacherPlatform } from "../src/app/default-platform.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";

export default function handler(req: ApiRequest, res: ApiResponse): void {
  if (!requireGet(req, res)) return;

  const platform = createOctoTeacherPlatform();
  writeJson(res, 200, {
    integrations: platform.integrations.list().map((integration) => ({
      provider: integration.provider,
      environment: integration.environment,
      status: integration.status,
      purpose: integration.purpose,
      requiredSecrets: integration.secretRefs
        .filter((secret) => secret.required)
        .map((secret) => ({ id: secret.id, envName: secret.envName, holder: secret.holder })),
      dangerousCapabilities: integration.dangerousCapabilities,
    })),
  });
}

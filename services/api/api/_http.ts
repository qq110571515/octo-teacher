export type ApiRequest = {
  method?: string;
  headers?: Record<string, string | string[] | undefined>;
  body?: unknown;
  query?: Record<string, string | string[] | undefined>;
};

export type ApiResponse = {
  status(code: number): ApiResponse;
  json(body: unknown): void;
  setHeader(name: string, value: string): void;
  end?(): void;
};

export function writeJson(res: ApiResponse, status: number, body: unknown): void {
  res.setHeader("cache-control", "no-store");
  res.status(status).json(body);
}

export function requireGet(req: ApiRequest, res: ApiResponse): boolean {
  if ((req.method ?? "GET") !== "GET") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return false;
  }
  return true;
}

export function requirePost(req: ApiRequest, res: ApiResponse): boolean {
  if ((req.method ?? "GET") !== "POST") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return false;
  }
  return true;
}

export function requestHeader(req: ApiRequest, name: string): string | undefined {
  const target = name.toLowerCase();
  const entry = Object.entries(req.headers ?? {}).find(([key]) => key.toLowerCase() === target)?.[1];
  return Array.isArray(entry) ? entry[0] : entry;
}

export function applyPortalCors(req: ApiRequest, res: ApiResponse): boolean {
  const policy = portalCorsPolicy(req.method, requestHeader(req, "origin"));
  for (const [name, value] of Object.entries(policy.headers)) res.setHeader(name, value);

  if (policy.preflight) {
    res.status(204);
    res.end?.();
    return true;
  }
  return false;
}

export function bearerToken(req: ApiRequest): string | undefined {
  const authorization = requestHeader(req, "authorization");
  if (!authorization?.startsWith("Bearer ")) return undefined;
  const token = authorization.slice("Bearer ".length).trim();
  return token || undefined;
}

export function readJsonBody(req: ApiRequest): unknown {
  if (typeof req.body !== "string") return req.body;
  try {
    return JSON.parse(req.body) as unknown;
  } catch {
    throw new Error("invalid_json");
  }
}
import { portalCorsPolicy } from "../src/security/portal-cors.js";

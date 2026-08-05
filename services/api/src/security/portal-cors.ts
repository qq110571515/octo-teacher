const portalOrigins = new Set([
  "https://octoteacher.com",
  "https://www.octoteacher.com",
  "https://octoteacher-portal.vercel.app",
]);

export type PortalCorsPolicy = {
  headers: Record<string, string>;
  preflight: boolean;
};

export function portalCorsPolicy(method: string | undefined, origin: string | undefined): PortalCorsPolicy {
  const headers: Record<string, string> = {};
  if (origin && portalOrigins.has(origin)) {
    headers["access-control-allow-origin"] = origin;
    headers["access-control-allow-headers"] = "authorization, content-type";
    headers["access-control-allow-methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS";
    headers["access-control-max-age"] = "600";
    headers.vary = "Origin";
  }
  return { headers, preflight: method === "OPTIONS" };
}

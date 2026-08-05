import { createHash } from "node:crypto";
import { buildPublicMarketplaceCatalog } from "../../../src/domain/marketplace/public-catalog.js";
import { loadPublishedMarketplaceListings } from "../../../src/domain/marketplace/postgres-marketplace-catalog.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;

  try {
    const catalog = buildPublicMarketplaceCatalog(await loadPublishedMarketplaceListings());
    const payload = JSON.stringify(catalog);
    const etag = `"${createHash("sha256").update(payload).digest("hex")}"`;
    res.setHeader("cache-control", "public, max-age=60, s-maxage=300, stale-while-revalidate=900");
    res.setHeader("content-type", "application/json; charset=utf-8");
    res.setHeader("etag", etag);
    if (req.headers?.["if-none-match"] === etag) {
      res.status(304).end?.();
      return;
    }
    res.status(200).json(catalog);
  } catch {
    writeJson(res, 503, { error: "marketplace_catalog_unavailable" });
  }
}

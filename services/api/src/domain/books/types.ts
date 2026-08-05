export type BookAssetKind = "epub" | "pdf" | "cover" | "audio" | "parsed_text";
export type BookPublicationStatus = "draft" | "processing" | "review" | "published" | "retired";

export type Book = {
  id: string;
  title: string;
  author: string;
  language: string;
  ageBand: string;
  categories: string[];
  source: "public_domain" | "licensed" | "creator" | "manual_upload";
  status: BookPublicationStatus;
  createdAt: string;
};

export type BookAsset = {
  id: string;
  bookId: string;
  kind: BookAssetKind;
  storageKey: string;
  contentType: string;
  byteSize: number;
  checksum: string;
  createdAt: string;
};

export type BookDownloadEvent = {
  id: string;
  bookId: string;
  familyId?: string;
  childProfileId?: string;
  platform: "ios" | "web" | "unknown";
  occurredAt: string;
};

export type BookMetrics = {
  bookId: string;
  downloadCount: number;
};

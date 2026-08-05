import type { Book, BookAsset, BookDownloadEvent, BookMetrics } from "./types.js";

export class InMemoryBookCatalog {
  private readonly books = new Map<string, Book>();
  private readonly assets = new Map<string, BookAsset>();
  private readonly downloads: BookDownloadEvent[] = [];

  upsertBook(book: Book): void {
    this.books.set(book.id, book);
  }

  addAsset(asset: BookAsset): void {
    if (!this.books.has(asset.bookId)) {
      throw new Error(`Cannot attach asset to missing book: ${asset.bookId}`);
    }
    this.assets.set(asset.id, asset);
  }

  publishBook(bookId: string): Book {
    const book = this.books.get(bookId);
    if (!book) throw new Error(`Missing book: ${bookId}`);
    const hasReadableAsset = [...this.assets.values()].some((asset) => asset.bookId === bookId && (asset.kind === "epub" || asset.kind === "pdf"));
    if (!hasReadableAsset) {
      throw new Error(`Book cannot be published without an EPUB or PDF asset: ${bookId}`);
    }
    const published: Book = { ...book, status: "published" };
    this.books.set(bookId, published);
    return published;
  }

  recordDownload(event: BookDownloadEvent): void {
    const book = this.books.get(event.bookId);
    if (!book || book.status !== "published") {
      throw new Error(`Cannot download unpublished book: ${event.bookId}`);
    }
    this.downloads.push(event);
  }

  metrics(): BookMetrics[] {
    const counts = new Map<string, number>();
    for (const event of this.downloads) {
      counts.set(event.bookId, (counts.get(event.bookId) ?? 0) + 1);
    }
    return [...counts.entries()].map(([bookId, downloadCount]) => ({ bookId, downloadCount }));
  }

  listPublished(): Book[] {
    return [...this.books.values()].filter((book) => book.status === "published");
  }
}

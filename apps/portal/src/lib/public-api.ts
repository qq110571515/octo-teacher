const apiBase = process.env.NEXT_PUBLIC_PLATFORM_API_URL?.replace(/\/$/, "") ?? "";

export type GuestbookMessage = {
  id: string;
  displayName: string;
  message: string;
  createdAt: string;
};

export type GuestbookChallenge = {
  token: string;
  salt: string;
  difficulty: number;
  notBeforeAt: string;
  expiresAt: string;
};

export class PublicApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
    this.name = "PublicApiError";
  }
}

async function publicRequest<T>(path: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers);
  headers.set("accept", "application/json");
  if (init?.body !== undefined) headers.set("content-type", "application/json");

  const response = await fetch(`${apiBase}${path}`, {
    ...init,
    cache: "no-store",
    headers,
  });
  const payload = (await response.json().catch(() => undefined)) as
    | (T & { error?: string })
    | undefined;

  if (!response.ok) {
    throw new PublicApiError(response.status, payload?.error ?? "request_failed");
  }
  if (payload === undefined) throw new PublicApiError(response.status, "invalid_response");
  return payload;
}

export async function loadGuestbookMessages(): Promise<GuestbookMessage[]> {
  const payload = await publicRequest<{ messages: GuestbookMessage[] }>("/api/v1/guestbook");
  return payload.messages;
}

export async function loadGuestbookChallenge(): Promise<GuestbookChallenge> {
  const payload = await publicRequest<{ challenge: GuestbookChallenge }>("/api/v1/guestbook/challenge");
  return payload.challenge;
}

export async function submitGuestbookMessage(input: {
  displayName: string;
  message: string;
  website: string;
  challengeToken: string;
  proof: number;
}): Promise<GuestbookMessage> {
  const payload = await publicRequest<{ message: GuestbookMessage }>("/api/v1/guestbook", {
    method: "POST",
    body: JSON.stringify(input),
  });
  return payload.message;
}

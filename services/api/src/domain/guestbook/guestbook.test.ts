import assert from "node:assert/strict";
import test from "node:test";
import {
  createGuestbookChallenge,
  fnv1a32,
  GuestbookError,
  parseGuestbookSubmission,
  verifyGuestbookChallenge,
} from "./guestbook.js";

const secret = "test-guestbook-secret-with-at-least-thirty-two-characters";

function solveProof(salt: string, difficulty: number, displayName: string, message: string): number {
  const divisor = 2 ** (32 - difficulty);
  for (let proof = 0; proof <= 2_000_000; proof += 1) {
    if (Math.floor(fnv1a32(`${salt}:${displayName}:${message}:${proof}`) / divisor) === 0) return proof;
  }
  throw new Error("proof_not_found");
}

test("normalizes and validates a public guestbook submission", () => {
  const submission = parseGuestbookSubmission({
    displayName: "  Leo   Ma ",
    message: "  A thoughtful public message.  ",
    website: "",
    challengeToken: "signed-token",
    proof: 42,
  });
  assert.deepEqual(submission, {
    displayName: "Leo Ma",
    message: "A thoughtful public message.",
    challengeToken: "signed-token",
    proof: 42,
  });
});

test("rejects honeypot input and link-heavy spam", () => {
  assert.throws(
    () => parseGuestbookSubmission({ displayName: "Bot", message: "A long enough message", website: "spam.example", challengeToken: "x", proof: 1 }),
    (error: unknown) => error instanceof GuestbookError && error.code === "challenge_invalid",
  );
  assert.throws(
    () => parseGuestbookSubmission({ displayName: "Bot", message: "https://a.test https://b.test https://c.test", website: "", challengeToken: "x", proof: 1 }),
    (error: unknown) => error instanceof GuestbookError && error.code === "message_too_many_links",
  );
});

test("accepts a signed, IP-bound proof only after the minimum delay", () => {
  const issuedAt = Date.parse("2026-08-04T20:00:00.000Z");
  const challenge = createGuestbookChallenge(secret, "203.0.113.8", issuedAt, 8);
  const submission = {
    displayName: "Anonymous",
    message: "This project should help many families.",
    challengeToken: challenge.token,
    proof: solveProof(challenge.salt, challenge.difficulty, "Anonymous", "This project should help many families."),
  };

  assert.throws(
    () => verifyGuestbookChallenge({ secret, ipAddress: "203.0.113.8", submission, now: issuedAt + 1_000 }),
    (error: unknown) => error instanceof GuestbookError && error.code === "challenge_too_fast",
  );
  assert.doesNotThrow(() => verifyGuestbookChallenge({ secret, ipAddress: "203.0.113.8", submission, now: issuedAt + 3_000 }));
  assert.throws(
    () => verifyGuestbookChallenge({ secret, ipAddress: "203.0.113.9", submission, now: issuedAt + 3_000 }),
    (error: unknown) => error instanceof GuestbookError && error.code === "challenge_invalid",
  );
});

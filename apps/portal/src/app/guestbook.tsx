"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { ArrowRight, LoaderCircle, ShieldCheck } from "lucide-react";
import {
  loadGuestbookChallenge,
  loadGuestbookMessages,
  PublicApiError,
  submitGuestbookMessage,
  type GuestbookChallenge,
  type GuestbookMessage,
} from "@/lib/public-api";
import styles from "./open-source.module.css";

const proofBatchSize = 100_000;
const maximumProof = 50_000_000;

function normalizeName(value: string): string {
  return value.trim().replace(/\s+/g, " ") || "Anonymous";
}

function normalizeMessage(value: string): string {
  return value.replace(/\r\n?/g, "\n").trim();
}

function fnv1a32(value: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash;
}

function nextFrame(): Promise<void> {
  return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}

async function solveChallenge(
  challenge: GuestbookChallenge,
  displayName: string,
  message: string,
): Promise<number> {
  const prefix = `${challenge.salt}:${normalizeName(displayName)}:${normalizeMessage(message)}:`;
  const divisor = 2 ** (32 - challenge.difficulty);

  for (let start = 0; start < maximumProof; start += proofBatchSize) {
    const end = Math.min(start + proofBatchSize, maximumProof);
    for (let proof = start; proof < end; proof += 1) {
      if (Math.floor(fnv1a32(`${prefix}${proof}`) / divisor) === 0) return proof;
    }
    await nextFrame();
  }
  throw new Error("human_check_failed");
}

function friendlyError(error: unknown): string {
  if (!(error instanceof PublicApiError)) return "The message could not be sent. Please try again.";
  switch (error.code) {
    case "guestbook_rate_limited":
      return "A few messages have already been sent from this network. Please try again later.";
    case "guestbook_duplicate":
      return "That note was already received. Thank you.";
    case "challenge_expired":
    case "challenge_invalid":
    case "challenge_too_fast":
      return "The human check expired. Please press send once more.";
    case "message_too_short":
      return "Please write at least 10 characters.";
    case "message_too_long":
      return "Please keep the note under 600 characters.";
    case "message_too_many_links":
      return "Please include no more than two links.";
    default:
      return "The message could not be sent. Please try again.";
  }
}

function formattedDate(value: string): string {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(new Date(value));
}

export default function Guestbook() {
  const [messages, setMessages] = useState<GuestbookMessage[]>([]);
  const [challenge, setChallenge] = useState<GuestbookChallenge | null>(null);
  const [loadingMessages, setLoadingMessages] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [messageLength, setMessageLength] = useState(0);

  const refreshChallenge = useCallback(async () => {
    const nextChallenge = await loadGuestbookChallenge();
    setChallenge(nextChallenge);
    return nextChallenge;
  }, []);

  useEffect(() => {
    let active = true;
    Promise.all([loadGuestbookMessages(), loadGuestbookChallenge()])
      .then(([nextMessages, nextChallenge]) => {
        if (!active) return;
        setMessages(nextMessages);
        setChallenge(nextChallenge);
      })
      .catch(() => {
        if (active) setError("The guestbook is temporarily unavailable.");
      })
      .finally(() => {
        if (active) setLoadingMessages(false);
      });
    return () => {
      active = false;
    };
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formElement = event.currentTarget;
    setSubmitting(true);
    setError("");
    setStatus("Preparing the privacy-respecting human check...");

    const form = new FormData(formElement);
    const displayName = String(form.get("displayName") ?? "");
    const message = String(form.get("message") ?? "");
    const website = String(form.get("website") ?? "");

    try {
      let activeChallenge = challenge;
      if (!activeChallenge || Date.parse(activeChallenge.expiresAt) < Date.now() + 5_000) {
        activeChallenge = await refreshChallenge();
      }

      setStatus("Verifying this browser. This usually takes a moment...");
      const proof = await solveChallenge(activeChallenge, displayName, message);
      const waitMs = Date.parse(activeChallenge.notBeforeAt) - Date.now();
      if (waitMs > 0) await new Promise((resolve) => setTimeout(resolve, waitMs));

      const created = await submitGuestbookMessage({
        displayName,
        message,
        website,
        challengeToken: activeChallenge.token,
        proof,
      });
      setMessages((current) => [created, ...current].slice(0, 24));
      formElement.reset();
      setMessageLength(0);
      setStatus("Your note is now on the guestbook. Thank you.");
      await refreshChallenge();
    } catch (submissionError) {
      setError(friendlyError(submissionError));
      setStatus("");
      await refreshChallenge().catch(() => setChallenge(null));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className={styles.guestbookLayout}>
      <form className={styles.guestbookForm} onSubmit={handleSubmit}>
        <h3>Write a public note</h3>
        <p>Your name is optional. Messages appear publicly after the automated checks pass.</p>

        <div className={styles.fieldGroup}>
          <label htmlFor="guestbook-name">Name</label>
          <input id="guestbook-name" name="displayName" maxLength={40} placeholder="Anonymous" autoComplete="name" />
        </div>

        <div className={styles.honeypot} aria-hidden="true">
          <label htmlFor="guestbook-website">Website</label>
          <input id="guestbook-website" name="website" tabIndex={-1} autoComplete="off" />
        </div>

        <div className={styles.fieldGroup}>
          <label htmlFor="guestbook-message">Message</label>
          <textarea
            id="guestbook-message"
            name="message"
            minLength={10}
            maxLength={600}
            required
            placeholder="What should this project become?"
            onChange={(event) => setMessageLength(event.target.value.length)}
          />
          <div className={styles.fieldMeta}><span>10 character minimum</span><span>{messageLength}/600</span></div>
        </div>

        <div className={styles.humanCheck}>
          <ShieldCheck size={20} aria-hidden="true" />
          <span>No account or tracking cookie. A short-lived browser challenge and rate limits discourage automated spam.</span>
        </div>

        <button className={styles.submitButton} type="submit" disabled={submitting || !challenge}>
          {submitting ? <LoaderCircle size={18} className={styles.spinner} /> : <ArrowRight size={18} />}
          {submitting ? "Checking and sending" : "Publish note"}
        </button>
        <p className={`${styles.formStatus} ${error ? styles.formError : ""}`} aria-live="polite">
          {error || status}
        </p>
      </form>

      <div className={styles.messageColumn}>
        <h3>Recent notes</h3>
        <p>Public messages from families, educators, builders, and curious visitors.</p>
        <div className={styles.messageList} aria-live="polite">
          {loadingMessages ? (
            <p className={styles.emptyMessages}>Loading the conversation...</p>
          ) : messages.length === 0 ? (
            <p className={styles.emptyMessages}>The guestbook is open. Be the first to leave a thoughtful note.</p>
          ) : (
            messages.map((entry) => (
              <article className={styles.messageItem} key={entry.id}>
                <div className={styles.messageMeta}>
                  <strong>{entry.displayName}</strong>
                  <time dateTime={entry.createdAt}>{formattedDate(entry.createdAt)}</time>
                </div>
                <p>{entry.message}</p>
              </article>
            ))
          )}
        </div>
      </div>
    </div>
  );
}

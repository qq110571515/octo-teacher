"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import Image from "next/image";
import {
  BookOpen,
  Check,
  ChevronRight,
  CircleUserRound,
  Clock3,
  GraduationCap,
  LogOut,
  Mail,
  RefreshCw,
  ShieldCheck,
  Smartphone,
  Sparkles,
  UsersRound,
} from "lucide-react";
import type { Session } from "@supabase/supabase-js";
import { createPortalSupabaseClient } from "@/lib/supabase";
import { platformApiPaths, platformRequest } from "@/lib/platform-api";
import { FamilyConsolePanel } from "./family-console";
import styles from "./page.module.css";

type AccountStatus = "pending" | "active" | "suspended" | "deleted";
type Account = {
  publicRef: string;
  handle: string;
  displayName: string;
  maskedEmail?: string;
  status: AccountStatus;
  createdAt: string;
};

type AccountResponse = {
  account: Account | null;
  isOwnerApprover: boolean;
};

async function accountRequest<T>(session: Session, path: string, init?: RequestInit): Promise<T> {
  return platformRequest<T>(session, path, init);
}

export default function Home() {
  const supabase = useMemo(() => createPortalSupabaseClient(), []);
  const [session, setSession] = useState<Session | null>(null);
  const [accountState, setAccountState] = useState<AccountResponse | null>(null);
  const [pending, setPending] = useState<Account[]>([]);
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [handle, setHandle] = useState("");
  const [appCode, setAppCode] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  const loadAccount = useCallback(async (current: Session) => {
    const state = await accountRequest<AccountResponse>(current, platformApiPaths.account);
    setAccountState(state);
    if (state.isOwnerApprover && state.account?.status === "active") {
      const approvals = await accountRequest<{ pending: Account[] }>(current, platformApiPaths.accountApprovals);
      setPending(approvals.pending);
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setAppCode(new URLSearchParams(window.location.search).get("app_code")?.trim() ?? "");
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      if (data.session) void loadAccount(data.session).catch(() => setMessage("We could not load your account. Please try again shortly."));
    });
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setAccountState(null);
      if (nextSession) void loadAccount(nextSession).catch(() => setMessage("We could not load your account. Please try again shortly."));
    });
    return () => data.subscription.unsubscribe();
  }, [loadAccount, supabase]);

  async function requestMagicLink(event: FormEvent) {
    event.preventDefault();
    if (!supabase) return;
    setBusy(true);
    setMessage("");
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: `${window.location.origin}/family${window.location.search}` },
    });
    setMessage(error ? "The sign-in email could not be sent. Check the address and try again." : "Your sign-in link is on its way. Open it from your email within ten minutes.");
    setBusy(false);
  }

  async function createAccount(event: FormEvent) {
    event.preventDefault();
    if (!session) return;
    setBusy(true);
    setMessage("");
    try {
      const state = await accountRequest<AccountResponse>(session, platformApiPaths.account, {
        method: "POST",
        body: JSON.stringify({ displayName, handle }),
      });
      setAccountState(state);
    } catch {
      setMessage("That ID may already be in use. Choose another one and try again.");
    } finally {
      setBusy(false);
    }
  }

  async function approve(publicRef: string) {
    if (!session) return;
    setBusy(true);
    try {
      await accountRequest(session, platformApiPaths.accountApprovals, {
        method: "POST",
        body: JSON.stringify({ publicRef, action: "approve" }),
      });
      await loadAccount(session);
    } finally {
      setBusy(false);
    }
  }

  async function signOut() {
    if (!supabase) return;
    await supabase.auth.signOut();
    setAccountState(null);
    setPending([]);
  }

  async function approveAppLogin() {
    if (!session || !appCode) return;
    setBusy(true);
    setMessage("");
    try {
      await accountRequest(session, platformApiPaths.appLoginApprove, {
        method: "POST",
        body: JSON.stringify({ code: appCode }),
      });
      setMessage("This phone is approved. Return to the Octo Teacher app and tap Complete Connection.");
    } catch {
      setMessage("That device code is invalid or expired. Generate a new code in the app and try again.");
    } finally {
      setBusy(false);
    }
  }

  const account = accountState?.account;

  return (
    <main className={styles.shell}>
      <header className={styles.header}>
        <div className={styles.brand}>
          <Image className={styles.mark} src="/brand/octo-teacher-logo.png" alt="" aria-hidden="true" width={44} height={44} priority />
          <div>
            <strong>Octo Teacher</strong>
            <span>Family Console</span>
          </div>
        </div>
        {session ? (
          <button className={styles.iconButton} onClick={signOut} title="Sign out" aria-label="Sign out">
            <LogOut size={19} />
          </button>
        ) : null}
      </header>

      {!supabase ? (
        <section className={styles.centerState}><ShieldCheck size={34} /><h1>Portal authentication is not configured</h1><p>Set the Supabase project URL and publishable key, then deploy again.</p></section>
      ) : !session ? (
        <section className={styles.authLayout}>
          <div className={styles.authIntro}>
            <p className={styles.eyebrow}>FAMILY CONSOLE</p>
            <h1>One place for your family&apos;s shared growth plan.</h1>
            <p className={styles.tagline}>Healthy structure for learning, responsibility, and digital access.</p>
            <p>The console is currently available to approved families. Children do not need accounts. Guardians can create a family, invite another guardian, and review synced activity.</p>
            <div className={styles.trustLine}>
              <ShieldCheck size={20} />
              <span>Children&apos;s chats, photos, recordings, and private memories are not shown here.</span>
            </div>
          </div>
          <form className={styles.authPanel} onSubmit={requestMagicLink}>
            <div className={styles.panelHeading}>
              <Mail size={22} />
              <div><h2>Sign in with email</h2><p>The website and Octo Teacher app share one guardian account</p></div>
            </div>
            <label htmlFor="email">Email</label>
            <input id="email" type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} placeholder="parent@example.com" />
            <button className={styles.primaryButton} disabled={busy}>{busy ? "Sending..." : "Send sign-in link"}<ChevronRight size={18} /></button>
            <p className={styles.finePrint}>New accounts choose a unique ID and wait for approval before family data becomes available.</p>
            {message ? <p className={styles.message}>{message}</p> : null}
          </form>
        </section>
      ) : !accountState ? (
        <section className={styles.centerState}><RefreshCw className={styles.spin} /><h1>Checking your account</h1></section>
      ) : !account ? (
        <section className={styles.narrow}>
          <form className={styles.authPanel} onSubmit={createAccount}>
            <div className={styles.panelHeading}><CircleUserRound size={22} /><div><h2>Request family access</h2><p>Your approved ID will be used for web and app sign-in</p></div></div>
            <label htmlFor="displayName">Display name</label>
            <input id="displayName" required maxLength={60} value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="For example: The Rivera Family" />
            <label htmlFor="handle">Unique ID</label>
            <input id="handle" required minLength={3} maxLength={28} pattern="[a-z0-9_]+" value={handle} onChange={(event) => setHandle(event.target.value.toLowerCase())} placeholder="For example: rivera_family" />
            <button className={styles.primaryButton} disabled={busy}>{busy ? "Submitting..." : "Submit for review"}<ChevronRight size={18} /></button>
            {message ? <p className={styles.message}>{message}</p> : null}
          </form>
        </section>
      ) : account.status === "pending" ? (
        <section className={styles.centerState}>
          <Clock3 size={34} />
          <p className={styles.eyebrow}>ACCOUNT PENDING</p>
          <h1>Your account is awaiting review</h1>
          <p><strong>{account.handle}</strong> was submitted. Family data and app access stay unavailable until an administrator approves it.</p>
          <button className={styles.secondaryButton} onClick={() => session && loadAccount(session)}><RefreshCw size={17} />Refresh status</button>
        </section>
      ) : account.status !== "active" ? (
        <section className={styles.centerState}><ShieldCheck size={34} /><h1>This account is unavailable</h1><p>Contact the project administrator to review your access.</p></section>
      ) : (
        <section className={styles.dashboard}>
          <div className={styles.dashboardTitle}>
            <div><p className={styles.eyebrow}>APPROVED FAMILY</p><h1>Hello, {account.displayName}</h1><p>Account {account.handle} is approved. Family cloud features are being released in stages.</p></div>
            <span className={styles.approved}><Check size={16} />Approved</span>
          </div>

          <section className={styles.identityPanel}>
            <div>
              <p className={styles.eyebrow}>ACCOUNT & SIGN-IN</p>
              <h2>Account and sign-in</h2>
              <p>The website and Octo Teacher app use this approved email account. Child devices join the family without an email address or password.</p>
            </div>
            <div className={styles.identityActions}>
              <span className={styles.identityStatus}><Mail size={16} />Email verified</span>
            </div>
          </section>
          {appCode ? (
            <section className={styles.identityPanel}>
              <div>
                <p className={styles.eyebrow}>CONNECT IPHONE</p>
                <h2>Approve this guardian phone</h2>
                <p>Device code <strong>{appCode}</strong> securely connects the signed-in account to this phone and expires after ten minutes.</p>
              </div>
              <div className={styles.identityActions}>
                <button className={styles.primaryButton} disabled={busy} onClick={approveAppLogin}>
                  <Smartphone size={17} />{busy ? "Approving..." : "Approve this phone"}
                </button>
              </div>
            </section>
          ) : null}
          {message ? <p className={styles.message}>{message}</p> : null}

          <div className={styles.actionGrid}>
            <article><UsersRound /><h2>My family</h2><p>Review children, points, tasks, content, and device status in the family cloud.</p><button onClick={() => document.getElementById("family-console")?.scrollIntoView({ behavior: "smooth" })}>Open Family Console</button></article>
            <article><Smartphone /><h2>iPhone beta</h2><p>Approved accounts may receive a private TestFlight invitation at the same email address.</p><button disabled>Awaiting TestFlight</button></article>
            <article><GraduationCap /><h2>Growth packs</h2><p>Browse reviewed packs for reading, learning, daily life, and creative work.</p><button>View beta catalog</button></article>
            <article><Sparkles /><h2>Creator Studio</h2><p>Build bilingual task packs, configure rewards, and submit them for review.</p><button>Open studio</button></article>
            <article><BookOpen /><h2>Cloud library</h2><p>Manage lawfully sourced books and family-selected resources without uploading children&apos;s reading text.</p><button disabled>Integration in progress</button></article>
          </div>

          <FamilyConsolePanel session={session} />

          {accountState.isOwnerApprover ? (
            <section className={styles.approvalDesk}>
              <div className={styles.sectionHeading}><div><p className={styles.eyebrow}>OWNER ONLY</p><h2>Account approvals</h2></div><span>{pending.length} pending</span></div>
              {pending.length === 0 ? <p className={styles.empty}>No accounts are waiting for approval.</p> : pending.map((item) => (
                <div className={styles.approvalRow} key={item.publicRef}>
                  <div><strong>{item.displayName}</strong><span>{item.handle} · {item.maskedEmail}</span></div>
                  <button className={styles.approveButton} disabled={busy} onClick={() => approve(item.publicRef)}><Check size={16} />Approve</button>
                </div>
              ))}
            </section>
          ) : null}
        </section>
      )}

      <footer>Octo Teacher · Family Console · Open-source family technology.</footer>
    </main>
  );
}

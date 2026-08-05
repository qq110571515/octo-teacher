# Octo Teacher Platform API

This package is the first deployable scaffold for the Octo Teacher backend platform.
It is intentionally broad in shape and conservative at runtime:

- The **control plane** manages module registration, workflow definitions, release gates, audit evidence, and dashboard-facing read models.
- The **runtime plane** owns product actions such as family sync, task submission, verification, credit ledger, reward redemption, AI proxy, growth packs, school, creator, expert, moderation, billing, and analytics.
- High-risk capabilities start as `disabled` or `gated`; the scaffold provides in-memory implementations for tests and dry-run development only.

The first production-safe vertical slices are the parent-facing training marketplace catalog and its gated creator workflow:

- Postgres-backed, versioned creators, listings, plan items, and public reviews.
- Moderated book, video, and creation-template resources linked to listings by stable IDs.
- RLS enabled on all marketplace tables; mobile clients never connect to Postgres directly.
- `GET /api/v1/marketplace/listings` returns only reviewed, published, non-revoked, redacted fields.
- Creator submissions require a server-held creator token, current terms acceptance, bilingual metadata, strict field validation, and a content hash.
- Creator listings may reference only already-published resources; arbitrary external URLs cannot bypass resource review.
- Operator review and publication use a separate server-held token. Submission never publishes directly; approved payloads are integrity-checked again at publication.
- Ratings writes, payments, child receipts, and family behavior uploads remain disabled.
- The iOS app installs selected plans into its existing local atomic task workflow and uploads no child or device identifiers.
- Resource-only packs install references into Library, Educational Videos, or Creation Plaza without silently downloading or assigning content.
- Guardian, family, child profile, and hashed QR-invite tables are protected by RLS and connect through the family's approved guardian email account.

The family identity phase opens a deliberately narrow API:

- The website signs a guardian in with an approved email magic link. The App displays a short-lived code that the signed-in guardian approves on the website, then exchanges a one-time polling token for an opaque guardian session.
- Plaintext device codes and polling tokens are returned once and stored by the server only as SHA-256 hashes. Children still join by QR code and do not need an email account.
- Guardian and child-device session tokens are returned once and persisted by the server only as SHA-256 hashes.
- A family creator can issue ten-minute, single-use guardian or child-device QR invitations and revoke bound devices.
- Child profiles require no email or independent login. A child device is scoped to exactly one child profile.
- Minimal task sync includes title, schedule, points, status, and a short evidence summary only. It excludes photos, recordings, chat, AI memory, journals, mail bodies, and school documents.
- A family creator can export exactly that cloud scope as JSON, revoke the current guardian session, or permanently delete the cloud family after an exact public-reference confirmation. Deletion revokes all family guardian sessions and child device tokens in the same transaction.
- Family creation requires explicit versioned consent for family metadata and minimal child-task synchronization.
- Family task sync uses monotonic cursors, server-controlled versions, and idempotent mutation references so multiple guardians and child devices can retry safely without reopening completed work.
- Child task submissions are designed for a protected device outbox. A repeated mutation returns the already-applied task state, while stale versions return an explicit conflict for refresh and replay.
- Unknown family API failures are reported to Sentry using sanitized error codes only. Request bodies, authorization headers, child content, user objects, and traces are excluded.

## Current Scope

Implemented in this scaffold:

- Environment schema parsing with safe defaults.
- Route registry with control-plane/runtime/internal route layers.
- Module registry with dependency and release-gate metadata.
- Event envelope and in-memory event store.
- Workflow definition and in-memory workflow registry.
- Permission/consent gate stub that defaults to deny for sensitive actions.
- Append-only audit log types and in-memory implementation.
- Integration readiness registry for Vercel, Postgres, R2, OpenAI, Apple, Resend, Stripe, and Sentry.
- Durable marketplace catalog, moderated content resources, creator submission, review, publication, and append-only submission audit records.
- Family identity schema foundation for guardian accounts, equal-capability guardian membership, child profiles without email, and hashed QR invites.
- In-memory account/family, cloud book library, and AI/app usage metering stores for modules that are not yet cloud-enabled.
- Platform factory that wires the registries together.
- Platform readiness audit for workflow hook consistency, dangerous route defaults, credential route isolation, and production dangerous flags.
- Tests proving the dry-run safety rules.

Not implemented yet:

- Push notification queue, object storage adapter, payment provider, broad device control, school API, server AI provider, or broad iOS data sync beyond minimal family tasks.
- Uploading real child data.
- Creator self-service identity; the current operational tokens are an interim closed-beta service boundary, not end-user login.
- Unified Web/iOS guardian email accounts are active. Existing pre-email families retain a one-time migration code only so their historical family data can be attached without replacement.

## Commands

```sh
npm install --prefix services/api
npm run typecheck --prefix services/api
npm test --prefix services/api
npm run build --prefix services/api
npm run db:migrate --prefix services/api
npm run db:seed:marketplace --prefix services/api
```

Run migrations and seeds only with a server-side `DATABASE_URL`. Never put that URL in the iOS app or source control.
They are explicit one-time release operations and are intentionally not part of `vercel-build`, because Vercel may invoke the build command once per function.

Marketplace write endpoints additionally require all of these server-only variables:

```text
MARKETPLACE_OPERATIONS_ENABLED=true
MARKETPLACE_CREATOR_TOKEN=<random secret>
MARKETPLACE_OPERATOR_TOKEN=<different random secret>
```

`POST /api/v1/marketplace/submissions` accepts a creator draft. `GET /api/v1/marketplace/submissions`,
`POST /api/v1/marketplace/submissions/:id/review`, and `POST /api/v1/marketplace/submissions/:id/publish`
are operator-only. Keep the feature switch off whenever the review desk is unattended.

The normal guardian sign-in path uses the verified email provider configured for the portal. Legacy Apple endpoints remain compatibility-only and are not advertised by the App or website.

## Safety Defaults

- Dashboard/control-plane routes are read-only unless explicitly marked `gated`.
- Dangerous runtime routes, such as device commands, payment capture, and direct credit mutation, are registered as `disabled`.
- Events and audit records are append-only in the in-memory scaffold.
- Permission checks return `deny` for sensitive data or side-effecting actions until a real policy engine is connected.
- Writes are denied by default in the scaffold permission gate; only non-sensitive reads are allowed as a dry-run convenience.
- The platform can register large-module metadata now, but runtime behavior should be enabled module by module through release gates.
- Book publishing is gated on cloud asset references and content review.
- AI usage is recorded as product telemetry; provider keys never appear in public config.
- Family identity tables have RLS enabled and are reachable only through guardian or child-device scoped API sessions.
- QR invite, guardian-session, and child-device token plaintext is never stored; only SHA-256 hashes are persisted.
- Creator and operator credentials are separate, constant-time compared, and never returned by readiness endpoints.

## Cloud Account Inventory

The integration registry models the accounts and secrets needed for deployment without connecting to them yet:

| Provider | Purpose | Required first |
| --- | --- | --- |
| Vercel | Deploy API/console and manage env vars | project/team, domain plan |
| Postgres | Durable users, families, events, books, usage, audit | `DATABASE_URL` |
| Cloudflare R2 | Cloud book repository and signed downloads | account id, access key id, secret, bucket |
| OpenAI | Server AI proxy and token metering | server API key; optional admin key for cost sync |
| App Store Connect | Downloads, sales, and subscription report sync | key id, issuer id, private key |
| APNs | Guardian notifications and safety escalation | key id, team id, private key |
| Resend | Email invites and login codes | API key and verified domain |
| Stripe | Future web/school/creator billing | secret key and webhook secret |
| Sentry | Error monitoring | DSN with privacy scrubbing |

The registry reports missing required secrets and blocks any secret env from being exposed as public config.

## Production Prerequisites

Before this package can serve production traffic, add:

- Postgres migrations and durable event store.
- Real authentication and session binding.
- RBAC/ABAC plus guardian consent policy integration.
- Queue/outbox workers and dead-letter handling.
- Secrets management and provider adapters.
- R2 signed upload/download workflow for books and proof assets.
- App Store Connect report sync jobs.
- OpenAI proxy handlers that persist token/cost usage per family and feature.
- Observability, backups, retention jobs, and deletion propagation.
- Release-gate evidence wired into the Octo Teacher dashboard.

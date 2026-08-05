# Device Activity Monitor Extension

This directory is reserved for the future iOS `DeviceActivityMonitor` extension.
It is intentionally not wired into the current app target.

The current OctoTeacher iOS build uses `MockScreenTimeController` as the only
screen-time execution surface. Do not add `DeviceActivity` code here until the
mock reward session loop, App Group contract, Apple Family Controls entitlement,
and real-device parent authorization flow are all ready.

## Future Responsibility

When enabled, this extension should only do three things:

- Observe an approved reward session schedule.
- Emit an expiry receipt when the session window ends.
- Request a re-shield through the app/extension shared command channel.

It must not decide credits, approve tasks, select apps, read child content, call
cloud APIs, or store raw device/app identifiers.

## Shared Data Contract

Allowed App Group data:

- Redacted reward session id.
- Start and expiry timestamps.
- Granted minutes.
- Minimal shield policy revision.

Forbidden App Group data:

- Child name, school, family id, task text, homework text, diary content, media
  paths, real bundle identifiers, device identifiers, local network addresses,
  API keys, model names, tokens, or raw event payloads.

## Safety Gate

Before adding implementation code:

1. Keep `make ios-test` green with the mock controller.
2. Add extension-specific tests for expiry, duplicate callbacks, stale schedules,
   clock drift, and missing App Group payloads.
3. Verify that expiry always re-locks; an expired session must never remain
   unlocked.
4. Confirm the app still displays the product name `OctoTeacher`.

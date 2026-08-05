# Shield Action Extension

This directory is reserved for the future iOS `ShieldAction` extension. It is
not part of the current mock-only screen-time loop.

The extension may only be implemented after Apple Family Controls entitlement,
parent authorization, App Group storage, and `MockScreenTimeController` parity
tests are complete.

## Future Responsibility

When enabled, this extension handles button taps from the system shield UI.
Allowed actions are deliberately narrow:

- Close the shield UI.
- Create a redacted "request more time" intent for the parent inbox.
- Record a minimal local receipt that the child tapped a shield action.

It must not grant credit, spend credit, approve a reward, unlock a device,
modify task state, bypass parent approval, call AI, call cloud APIs, or expose
real bundle identifiers in user-visible copy.

## Parent Approval Boundary

"Request more time" is only a request. The parent app flow must still decide:

- Whether the child has enough available credit.
- Whether the family rule allows the request at that time.
- Whether the request conflicts with sleep, school, or quiet windows.
- Whether a guardian must explicitly approve it.

## Safety Gate

Before adding implementation code:

1. Add tests for close, request-more-time, duplicate taps, stale sessions, and
   missing shared payloads.
2. Prove the action extension cannot directly call reward settlement or device
   unlock use cases.
3. Keep all shared payloads redacted and minimal.
4. Keep the visible product name `OctoTeacher`; the octopus asset is only a logo.

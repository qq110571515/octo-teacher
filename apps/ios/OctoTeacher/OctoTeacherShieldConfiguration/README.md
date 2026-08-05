# Shield Configuration Extension

This directory is reserved for the future iOS `ShieldConfiguration` extension.
It is intentionally not implemented in the current mock-only iOS app.

The extension may only be wired after Apple Family Controls entitlement, parent
authorization, real device smoke testing, and the mock screen-time loop are all
stable.

## Future Responsibility

When enabled, this extension customizes the system shield screen with safe,
age-appropriate, non-sensitive copy. It may show:

- Product name: `OctoTeacher`.
- A generic encouragement message.
- Remaining approved session context, if it is already redacted.
- A parent-approved action label such as "Ask for more time".

It must not show:

- Child name, school, grade, task title, homework text, diary content, VLOG text,
  badge rationale, family member names, credit balance details, real app bundle
  identifiers, device identifiers, or local/network/debug information.

## Copy Rules

- Do not shame, compare, or pressure the child.
- Do not reveal why a parent rejected a request.
- Do not claim an unlock is available unless the parent flow has approved it.
- Do not mention internal models, QWEN/Claude/Codex, tokens, local paths, or
  backend status.

## Safety Gate

Before adding implementation code:

1. Add snapshot-style tests for child-safe copy.
2. Add redaction tests that reject names, ids, local paths, bundle ids, school
   names, task bodies, model names, and tokens.
3. Verify the shield screen remains useful when shared payloads are missing.
4. Keep the app display name and primary brand copy as `OctoTeacher`.

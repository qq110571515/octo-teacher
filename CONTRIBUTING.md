# Contributing to Octo Teacher

Thank you for helping build family technology that can withstand careful review.

## Before You Start

1. Read the README, especially the Apple Screen Time constraints.
2. Search existing issues before opening a new one.
3. Keep proposals focused. Large architecture changes should begin with a discussion issue.
4. Never include real child data, family exports, credentials, signing assets, or production logs.

## Development Workflow

Create a branch from `main`, make the smallest coherent change, and add tests that match the risk of the behavior being changed.

Useful checks:

```sh
# iOS
make ios-parse
make ios-lint
make ios-test

# Portal
npm run lint --prefix apps/portal
npm run build --prefix apps/portal

# API
npm run typecheck --prefix services/api
npm test --prefix services/api
npm run build --prefix services/api
```

Real Screen Time behavior must be described with the device model, iOS version, authorization state, and exact sequence tested. Redact family names, Apple IDs, device identifiers, notification tokens, and screenshots before attaching evidence.

## Pull Requests

A useful pull request includes:

- A short explanation of the user-visible behavior.
- The reason for the approach.
- Tests or verification performed.
- Any Apple capability, migration, deployment, or privacy impact.
- Screenshots for UI work using synthetic data only.

By contributing, you agree that your contribution is licensed under the MIT License.

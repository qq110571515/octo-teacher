# Octo Teacher

[![CI](https://github.com/qq110571515/octo-teacher/actions/workflows/ci.yml/badge.svg)](https://github.com/qq110571515/octo-teacher/actions/workflows/ci.yml)

Octo Teacher is an open-source family growth system that connects meaningful offline activity with healthier digital access. Children complete learning, creative, physical, and household tasks, earn growth points, and can exchange those points for bounded app-access windows.

The project is early-stage software under active development. It is not a finished parental-control product and should not be treated as a substitute for attentive family decision-making.

## Why This Project Is Open

Family technology influences children, household rules, and sensitive device behavior. Its implementation should be inspectable. Opening Octo Teacher makes it possible for families, engineers, privacy reviewers, educators, and accessibility contributors to question the model and improve it together.

## What Is Included

| Area | Location | Purpose |
| --- | --- | --- |
| iOS app | `apps/ios/OctoTeacher` | SwiftUI child and guardian experiences, Screen Time integration, and extensions |
| Website | `apps/portal` | English project site and separate guardian Family Console |
| Platform API | `services/api` | Family identity, device binding, task sync, Screen Time commands, and audit-safe APIs |
| Task packs | `packages/task-packs` | Schemas and seed content for family growth activities |

## Apple Screen Time Reality

Octo Teacher uses Apple FamilyControls, ManagedSettings, and DeviceActivity as its enforcement foundation. There are important platform constraints:

- Screen Time authorization and app selection must be completed on a supported Apple device.
- Apple exposes privacy-preserving opaque tokens, not a remotely enumerable list of every app installed on a child's phone.
- Screen Time extensions and entitlement behavior require real-device testing. Simulator-only results are insufficient.
- A guardian web console can coordinate policies and show synchronized summaries, but it cannot bypass Apple's authorization model.

These constraints are part of the architecture, not hidden implementation details.

## Local Development

### iOS

Requirements: macOS, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make doctor
make ios-generate
make ios-build
make ios-test
make ios-open
```

The production Screen Time path requires the appropriate Apple capability and a physical device.

### Website

```sh
cd apps/portal
cp .env.example .env.local
npm install
npm run dev
```

Open `http://localhost:3000` for the public project site and `http://localhost:3000/family` for the Family Console.

### Platform API

```sh
npm install --prefix services/api
npm run typecheck --prefix services/api
npm test --prefix services/api
npm run build --prefix services/api
```

See `services/api/README.md` for environment variables, database migrations, and production safety gates.

## Privacy and Security

- Never commit `.env` files, signing assets, database URLs, provider keys, guardian session tokens, child-device tokens, or real family exports.
- Use synthetic names and identifiers in tests, screenshots, fixtures, and bug reports.
- Keep child chats, photos, recordings, journals, and private memories outside public issues.
- Report vulnerabilities through GitHub private vulnerability reporting as described in `SECURITY.md`.

## Contributing

Start with `CONTRIBUTING.md`, then open a focused issue or pull request. Useful contributions include iOS reliability, Screen Time lifecycle testing, accessibility, privacy review, documentation, and narrowly scoped bug fixes.

By participating, you agree to follow `CODE_OF_CONDUCT.md`.

## License

Octo Teacher is available under the [MIT License](LICENSE).

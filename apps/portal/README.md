# Octo Teacher Website and Family Console

The Next.js website deployed at `octoteacher.com`.

## Routes

- `/` is the English open-source project site.
- `/family` is the separate guardian Family Console.
- Guardians sign in with an email magic link and new accounts require approval.
- Children do not register on the website.
- The console does not receive complete child chats, photos, recordings, or private memories.

## Local Development

Copy `.env.example` to `.env.local` and set the public configuration:

```bash
npm install
npm run dev
```

Required:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_PLATFORM_API_URL`

Production environment variables are managed by Vercel and are never committed.

## Verification

```bash
npm run lint
npm run build
```

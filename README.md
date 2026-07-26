# YAJIB Nexus University Platform

YAJIB Nexus is a production-oriented university examination, academic records, research governance and learning management platform built with HTML5, CSS3, vanilla JavaScript ES modules, PostgreSQL and Supabase.

The landing page is deliberately self-contained in `index.html`: its layout, responsive styling, English/Arabic/French translations, RTL behavior, login, role selection and password-recovery logic are all in that one file. Authenticated role dashboards use shared modules to avoid duplicating security-critical logic.

## Delivered capabilities

- Secure Supabase email/password login with loading and validation states.
- English, Arabic and French landing content; Arabic switches the document to RTL immediately.
- Database-derived role routing with a multiple-role chooser and fixed route allowlist.
- Password reset request and verified password update flow.
- Seventeen role-specific dashboard entry pages.
- Live, RLS-filtered examinations, results, learning, assignments, records, transcripts, research, approvals, users, courses and audit modules.
- Secure RPCs for exam start/save/submit, result approval, research submission, transcript request and transcript verification.
- Strict Row-Level Security, immutable approved results, audit events, constraints, indexes and transactional workflows.
- Protected server-side demo seeding and privileged role-management Edge Functions.
- Light/dark themes, mobile navigation, semantic controls, keyboard focus, reduced-motion support, empty/error/loading/offline states and CSP headers.
- A local 1280×720 H.264 platform tutorial video, avoiding an unavailable third-party media dependency.

## Project structure

```text
university-platform/
├── index.html                    # Self-contained multilingual landing and authentication
├── reset-password.html           # Verified password update page
├── runtime-config.js             # Public browser configuration (URL + anon key only)
├── assets/
│   ├── css/app.css               # Shared authenticated-workspace design system
│   ├── js/                       # Auth guard, Supabase client, service and dashboard modules
│   └── media/                    # Tutorial video, poster and source SVG frames
├── pages/                        # One responsive HTML entry page per role
├── supabase/
│   ├── migrations/               # Schema, RLS, workflows and RPCs
│   ├── functions/                # Server-only privileged functions
│   ├── seed/reference-data.sql   # Non-secret university reference data
│   └── config.toml
├── tests/                        # Node test suite
├── scripts/validate-project.js
├── docs/                         # Architecture, security, testing and operations
└── deploy/nginx.conf             # Production static-host configuration
```

## Prerequisites

- Node.js 20 or later (tests only)
- Supabase CLI 2.x
- Docker Desktop for local Supabase, or a hosted Supabase project
- A static HTTPS host such as Nginx, Cloudflare Pages, Netlify or Vercel static hosting

## Local setup

1. Open a terminal in this directory.
2. Start local Supabase:

   ```bash
   supabase start
   supabase db reset
   supabase db execute --file supabase/seed/reference-data.sql
   ```

3. Copy the values printed by `supabase status` into `runtime-config.js`. Only use the public API URL and public anon key. Never put the service-role key in this file.
4. Start the web app:

   ```bash
   npm run dev
   ```

5. Open `http://127.0.0.1:4173`.

The page intentionally disables sign-in when public Supabase configuration is absent or malformed. It never falls back to fabricated data.

## Hosted Supabase deployment

1. Create a Supabase project and record its project reference.
2. Authenticate and link the CLI:

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

3. Run `supabase/seed/reference-data.sql` in the SQL editor or with the CLI.
4. Set server-only function secrets:

   ```bash
   supabase secrets set APP_ORIGIN=https://university.example.edu
   supabase secrets set DEMO_SEED_SECRET=YOUR_RANDOM_32_PLUS_CHARACTER_SECRET
   supabase secrets set ALLOW_DEMO_SEED=true
   ```

5. Deploy functions:

   ```bash
   supabase functions deploy seed-demo-users --no-verify-jwt
   supabase functions deploy admin-role-management
   ```

6. Invoke the seed function once from a trusted administrator terminal using the `x-seed-secret` header. The response returns counts only and never returns a password.
7. Immediately disable future seeding:

   ```bash
   supabase secrets set ALLOW_DEMO_SEED=false
   ```

8. Add the production site URL and `https://university.example.edu/reset-password.html` to **Authentication → URL Configuration** in Supabase.
9. Put the production project URL and anon key in `runtime-config.js`, then deploy the static files over HTTPS.

## Demo account security

The required demo identities are defined only inside the server-side seed function. Password values are absent from `index.html`, every dashboard, shared browser JavaScript and public runtime configuration. For a real deployment:

- seed only in a non-production or controlled acceptance environment;
- disable the seeder immediately;
- require password change at first login and enable MFA for privileged users;
- replace shared demo identities with named institutional accounts before launch.

## Verification

```bash
npm run verify
```

See `docs/TESTING.md` for database, browser, accessibility and security test procedures.

## Important production boundary

The implementation is complete, but it cannot contact a Supabase project until the project owner supplies the public URL and anon key and applies the migrations. SMTP delivery, custom domains, institutional SSO, SMS, payment gateways, proctoring vendors and object-storage antivirus scanning are external services; none is falsely simulated. Integration points and safe fallbacks are documented in `docs/OPERATIONS.md`.

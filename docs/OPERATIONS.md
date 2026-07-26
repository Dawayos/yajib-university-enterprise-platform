# Operations and deployment

## Environments

Maintain isolated Supabase projects for development, staging and production. Apply migrations through CI using a protected deployment identity. Never reuse production data in development.

## External service adapters

| Service | Adapter boundary | Required configuration | Fallback |
|---|---|---|---|
| Transactional email | Supabase Auth SMTP | SMTP host, credentials, sender domain | Display a neutral delivery message; support can resend after service recovery |
| Institutional SSO | Supabase Auth identity provider | SAML/OIDC tenant metadata | Email/password remains available only if institutional policy permits |
| File storage | Supabase Storage signed URLs | Private buckets, MIME/size policies | Text submission remains available; uploads are disabled with an actionable notice |
| Malware scanning | Storage webhook/Edge Function | Scanner endpoint and secret | Quarantine uploads; never release unscanned material |
| Proctoring | Server-side provider adapter | Provider URL, secret and consent policy | Standard invigilation workflow; no fake AI decision |
| SMS | Server-side messaging adapter | Provider endpoint and secret | In-app/email notification and retry queue |

No adapter secret belongs in `runtime-config.js`.

## Static deployment headers

Use `deploy/nginx.conf` as a baseline. In production, tune `connect-src` to the exact Supabase project host, enable HSTS only after HTTPS is confirmed and add a nonce/hash CSP if the single-file landing constraint changes.

## Backups and recovery

- Enable Point-in-Time Recovery for the production database.
- Export encrypted logical backups daily to a separate account.
- Retain quarterly immutable archives according to institutional policy.
- Perform and document a restore test at least quarterly.
- Recovery objectives should be formally approved; a suggested starting point is RPO 15 minutes and RTO 4 hours during examination periods.

## Monitoring

Alert on repeated failed login/reset requests, role changes, result publication, unusual bulk reads, Edge Function failures, database saturation, realtime disconnects and backup failures. Treat audit data as sensitive and restrict it to authorized operational staff.

## Incident response

1. Contain affected accounts or environment.
2. Preserve logs and database evidence.
3. Rotate relevant secrets and revoke sessions.
4. Determine scope, including affected students and records.
5. Restore or correct through approved, auditable procedures.
6. Notify institutional leadership, data-protection personnel and regulators where required.
7. Record corrective actions and test them before closure.

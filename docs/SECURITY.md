# Security model

## Controls implemented

- Supabase Auth handles password hashing, tokens, reset links and session refresh.
- Authentication fails closed when public configuration is absent.
- User roles are normalized in `user_roles`; client metadata is never trusted for authorization.
- Every business table has RLS enabled and forced.
- Course staff, enrolment, ownership and role helper functions centralize authorization.
- Critical exam and approval operations run transactionally in PostgreSQL RPCs.
- Approved/published results are immutable through a database trigger.
- The service-role key appears only in Edge Function environment access.
- Browser routing uses a fixed role-to-path allowlist.
- DOM values are written with `textContent`; user HTML is not injected.
- CSP blocks third-party frames, objects, unknown connections and navigation base changes.
- Security-definer functions use an empty `search_path` and fully qualified objects.
- Audit records are append-only to browser users.
- Demo seeding requires a long secret plus an explicit enable flag and can be disabled without redeployment.
- Password recovery gives the same success response whether or not an account exists, reducing account enumeration.

## Threat controls

| Threat | Primary mitigation |
|---|---|
| SQL injection | Supabase query APIs, typed RPC arguments and no string-built SQL in application requests |
| XSS | `textContent`, plain-text content fields, CSP and control-character stripping |
| IDOR | RLS ownership, enrolment and responsibility checks on each table |
| Privilege escalation | Database role checks, server-side admin function and no service key in browser |
| Result tampering | RLS, staged approvals, row locking, immutable-state trigger, versioning and audit |
| Exam answer disclosure | Students retrieve questions through an RPC that excludes `correct_answer` |
| Open redirect | Fixed role route allowlist |
| Account enumeration | Uniform password-reset message |
| Session theft impact | Short JWT lifetime, refresh rotation, HTTPS requirement and no local password storage |
| Brute force | Supabase Auth rate limiting; deploy WAF/rate limits at the edge |

## Production hardening checklist

- Enforce MFA for developer, admin, registrar, senate and VC roles.
- Configure custom SMTP with SPF, DKIM and DMARC.
- Add bot protection and institution-appropriate rate limits.
- Set production CSP as HTTP headers; remove `'unsafe-inline'` by moving the landing script/style to hashed or nonce-controlled assets if the single-file constraint is relaxed.
- Enable Supabase Point-in-Time Recovery and daily off-platform encrypted backups.
- Send database and Edge Function logs to a protected SIEM.
- Use separate development, staging and production Supabase projects.
- Rotate the demo seed secret and service-role key after acceptance testing.
- Add malware scanning before accepting research or assignment file uploads.
- Complete a DPIA and align retention rules with the institution’s policies and applicable Nigerian data-protection requirements.
- Run independent penetration testing before handling live examinations or official records.

## Known, intentional limitation

The one-file landing requirement needs inline CSS and JavaScript, so its CSP permits inline execution. Other pages keep their scripts and styles external. If policy allows a modular landing later, use nonce-based CSP or external assets and remove `'unsafe-inline'`.

# Test and quality plan

## Automated checks

Run:

```bash
npm run verify
```

The suite checks required artifacts, role pages, public-secret leakage, CSP presence, multilingual/auth flow markers, email/UUID validation, control-character handling and CSS-status sanitization.

## Database tests

With local Supabase running, execute these acceptance cases with separate JWTs:

1. A student can read only their published results, enrolments, submissions, projects and transcript requests.
2. A student cannot select `questions.correct_answer`; `get_exam_questions` omits it.
3. A student cannot start an exam outside its time window or without candidate eligibility.
4. Concurrent attempt-start calls cannot exceed `max_attempts`.
5. An answer cannot be saved after submission or expiry.
6. A lecturer can manage only assigned courses.
7. Each approval stage can decide only its own pending row.
8. Scores cannot change after a result becomes approved or published.
9. Only senate, registrar or developer authority can publish a result.
10. An anonymous user cannot enumerate transcripts; verification needs both reference and secret code.
11. A non-admin cannot grant or revoke a role through the Edge Function.
12. Audit rows cannot be updated or deleted by browser users.

Use Supabase’s `db test`/pgTAP facility in CI for these RLS cases with seeded disposable users.

## Browser acceptance matrix

Test current Chrome, Edge, Firefox and Safari plus Android Chrome and iOS Safari at 320, 375, 768, 1024 and 1440 CSS pixels.

- Login validation, loading, error and disabled states.
- English → Arabic applies RTL without reload; French restores LTR.
- Keyboard-only modal open, close, tab order and submission.
- Screen-reader names for controls, status messages and tables.
- Reduced-motion preference disables automatic movement.
- Light/dark theme persistence.
- Multiple-role selection and unauthorized deep-link redirection.
- Reset link success, expiry and already-used behavior.
- Offline notification and recovery.
- Realtime record update on a second browser session.

## Performance targets

- Lighthouse performance ≥ 90 on a representative 4G profile.
- Accessibility ≥ 95 with no critical axe violations.
- Largest Contentful Paint ≤ 2.5 s and Cumulative Layout Shift ≤ 0.1.
- Authenticated list queries use bounded limits and indexed filters.

## Release gates

A release is blocked by a failed RLS test, secret-scanning alert, critical/high dependency issue, WCAG A failure, broken password recovery, cross-role data exposure or unverified backup restoration.

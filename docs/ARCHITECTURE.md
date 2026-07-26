# Architecture

## System context

```mermaid
flowchart TB
  U["Students and staff"] --> W["Static vanilla-JS web app"]
  W --> A["Supabase Auth"]
  W --> P["PostgREST and secure RPCs"]
  W --> R["Realtime channels"]
  P --> D["PostgreSQL with RLS"]
  R --> D
  E["Privileged Edge Functions"] --> D
  E --> A
```

The browser possesses only the public anon key and the signed-in user JWT. PostgreSQL Row-Level Security authorizes every data request. The browser cannot choose a role it has not been assigned because `set_active_role` checks `user_roles` inside a security-definer function.

## Authentication and routing sequence

```mermaid
sequenceDiagram
  actor User
  participant Web
  participant Auth
  participant DB
  User->>Web: Submit email and password
  Web->>Auth: signInWithPassword
  Auth-->>Web: User session JWT
  Web->>DB: get_my_bootstrap()
  DB-->>Web: Active profile and assigned roles
  alt One role
    Web->>DB: set_active_role(role)
    Web-->>User: Open authorized dashboard
  else Multiple roles
    Web-->>User: Show role chooser
    User->>Web: Select role
    Web->>DB: set_active_role(role)
    Web-->>User: Open authorized dashboard
  end
```

## Academic result workflow

```mermaid
stateDiagram-v2
  [*] --> Draft
  Draft --> Pending: Lecturer submits
  Pending --> Approved: Required stages approve
  Pending --> Rejected: A stage rejects
  Rejected --> Draft: Returned for correction
  Approved --> Published: Senate or Registrar publishes
  Published --> Archived
```

Database triggers reject score changes after approval or publication. Decisions are transactional RPC calls that lock the approval row, authorize the current stage and create an audit record.

## Key design decisions

| Decision | Reason |
|---|---|
| Self-contained public `index.html` | Meets the single-page landing requirement and simplifies reliable public deployment. |
| Shared authenticated modules | Prevents seventeen copies of auth and data-access code from diverging. |
| Separate role HTML entry points | Provides explicit URLs, CSP boundaries and predictable routing. |
| Database-first authorization | UI visibility is convenience; RLS and RPC checks remain authoritative. |
| Plain text/structured JSON content | Avoids storing executable HTML and reduces stored-XSS exposure. |
| Server-only user/role administration | Keeps the service-role key and Auth Admin API out of the browser. |
| Local tutorial media | Removes availability, tracking and licensing dependencies on a video host. |

## Role surfaces

| Role | Primary modules |
|---|---|
| Developer / Administrator | Users, courses, examinations, audit |
| Lecturer | Examinations, learning, assignments, results, research |
| Student | Learning, assignments, results, records, research, transcripts |
| Coordinator / DEO / HOD / Faculty / Senate | Results and staged approvals at the assigned scope |
| Registrar | Records, transcripts, published results |
| Vice-Chancellor | Institutional results, research and audit indicators |
| External Examiner | Examinations, results and external review |
| Supervisor / PG Coordinator | Research projects and milestones |
| Invigilator | Live examination operations |
| Help Desk | User support and permitted audit evidence |
| Transcript Verification | Verification request records only |

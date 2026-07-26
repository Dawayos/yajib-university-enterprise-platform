begin;

create extension if not exists pgcrypto;
create extension if not exists citext;

create type public.app_role as enum (
  'developer','admin','lecturer','student','coordinator','deo','hod','faculty','senate',
  'registrar','vc','external','supervisor','pgcoordinator','invigilator','helpdesk','transcript_verification'
);
create type public.record_status as enum ('draft','pending','approved','rejected','published','archived');
create type public.exam_status as enum ('draft','scheduled','open','closed','marking','approved','published','archived');
create type public.research_status as enum ('draft','submitted','under_review','revision_required','approved','active','completed','archived');
create type public.approval_decision as enum ('pending','approved','rejected','returned');

create table public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 3 and 180),
  code text not null unique check (code ~ '^[A-Z0-9_-]{2,20}$'),
  domain citext,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  institution_id uuid references public.institutions(id) on delete restrict,
  email citext not null,
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  student_number text,
  staff_number text,
  phone text check (phone is null or phone ~ '^\+?[0-9 ()-]{7,24}$'),
  locale text not null default 'en' check (locale in ('en','ar','fr')),
  avatar_path text,
  is_active boolean not null default true,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, student_number),
  unique (institution_id, staff_number)
);

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  is_active boolean not null default true,
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  primary key (user_id, role),
  check (expires_at is null or expires_at > granted_at)
);

create table public.user_active_roles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  role public.app_role not null,
  selected_at timestamptz not null default now()
);

create table public.faculties (
  id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete restrict,
  code text not null, name text not null check (char_length(trim(name)) between 2 and 160), dean_id uuid references public.profiles(id) on delete set null,
  is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(institution_id,code)
);
create table public.departments (
  id uuid primary key default gen_random_uuid(), faculty_id uuid not null references public.faculties(id) on delete restrict,
  code text not null, name text not null check (char_length(trim(name)) between 2 and 160), hod_id uuid references public.profiles(id) on delete set null,
  is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(faculty_id,code)
);
create table public.programmes (
  id uuid primary key default gen_random_uuid(), department_id uuid not null references public.departments(id) on delete restrict,
  code text not null, name text not null, award text not null, duration_years smallint not null check(duration_years between 1 and 8),
  is_active boolean not null default true, created_at timestamptz not null default now(), unique(department_id,code)
);
create table public.academic_sessions (
  id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete restrict,
  name text not null check(name ~ '^[0-9]{4}/[0-9]{4}$'), starts_on date not null, ends_on date not null, is_current boolean not null default false,
  created_at timestamptz not null default now(), unique(institution_id,name), check(ends_on>starts_on)
);
create unique index one_current_session_per_institution on public.academic_sessions(institution_id) where is_current;
create table public.semesters (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references public.academic_sessions(id) on delete cascade,
  name text not null check(name in ('First Semester','Second Semester','Summer Semester')), starts_on date not null, ends_on date not null,
  is_current boolean not null default false, unique(session_id,name), check(ends_on>starts_on)
);
create table public.courses (
  id uuid primary key default gen_random_uuid(), department_id uuid not null references public.departments(id) on delete restrict,
  code text not null check(code ~ '^[A-Z]{2,8}[0-9]{3,4}$'), title text not null check(char_length(trim(title)) between 3 and 180),
  credit_units numeric(3,1) not null check(credit_units between 0.5 and 12), level smallint not null check(level between 100 and 900),
  description text not null default '', is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(department_id,code)
);
create table public.course_staff (
  course_id uuid not null references public.courses(id) on delete cascade, staff_id uuid not null references public.profiles(id) on delete cascade,
  responsibility text not null default 'lecturer' check(responsibility in ('lecturer','coordinator','assistant','examiner')), assigned_at timestamptz not null default now(), primary key(course_id,staff_id,responsibility)
);
create table public.enrollments (
  id uuid primary key default gen_random_uuid(), student_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete restrict, session_id uuid not null references public.academic_sessions(id) on delete restrict,
  semester_id uuid not null references public.semesters(id) on delete restrict, status public.record_status not null default 'approved', enrolled_at timestamptz not null default now(),
  created_at timestamptz not null default now(), unique(student_id,course_id,session_id,semester_id)
);

create table public.exams (
  id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete restrict,
  title text not null check(char_length(trim(title)) between 5 and 160), instructions text not null default '' check(char_length(instructions)<=4000),
  starts_at timestamptz not null, ends_at timestamptz not null, duration_minutes smallint not null check(duration_minutes between 5 and 600),
  max_attempts smallint not null default 1 check(max_attempts between 1 and 5), randomize_questions boolean not null default true,
  status public.exam_status not null default 'draft', created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check(ends_at>starts_at)
);
create table public.questions (
  id uuid primary key default gen_random_uuid(), exam_id uuid not null references public.exams(id) on delete cascade,
  question_type text not null check(question_type in ('mcq','true_false','fill_blank','short_answer','essay')),
  prompt text not null check(char_length(trim(prompt)) between 3 and 10000), options jsonb not null default '[]'::jsonb,
  correct_answer jsonb, marks numeric(7,2) not null check(marks>0 and marks<=1000), position integer not null check(position>0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(exam_id,position), check(jsonb_typeof(options)='array')
);
create table public.exam_candidates (
  exam_id uuid not null references public.exams(id) on delete cascade, student_id uuid not null references public.profiles(id) on delete cascade,
  eligibility text not null default 'eligible' check(eligibility in ('eligible','ineligible','suspended','completed')), access_code_hash text,
  added_at timestamptz not null default now(), primary key(exam_id,student_id)
);
create table public.exam_attempts (
  id uuid primary key default gen_random_uuid(), exam_id uuid not null references public.exams(id) on delete restrict,
  student_id uuid not null default auth.uid() references public.profiles(id) on delete restrict, attempt_number smallint not null check(attempt_number between 1 and 5),
  started_at timestamptz not null default now(), submitted_at timestamptz, status text not null default 'in_progress' check(status in ('in_progress','submitted','auto_submitted','invalidated')),
  client_fingerprint_hash text, ip_address inet, created_at timestamptz not null default now(), unique(exam_id,student_id,attempt_number), check(submitted_at is null or submitted_at>=started_at)
);
create table public.exam_answers (
  id uuid primary key default gen_random_uuid(), attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete restrict, answer jsonb not null default '{}'::jsonb,
  awarded_marks numeric(7,2) check(awarded_marks>=0), marker_feedback text check(char_length(marker_feedback)<=4000), marked_by uuid references public.profiles(id) on delete restrict,
  saved_at timestamptz not null default now(), marked_at timestamptz, unique(attempt_id,question_id)
);
create table public.results (
  id uuid primary key default gen_random_uuid(), student_id uuid not null constraint results_student_id_fkey references public.profiles(id) on delete restrict,
  course_id uuid not null references public.courses(id) on delete restrict, session_id uuid not null references public.academic_sessions(id) on delete restrict,
  semester_id uuid not null references public.semesters(id) on delete restrict, attempt_id uuid references public.exam_attempts(id) on delete set null,
  ca_score numeric(7,2) not null default 0 check(ca_score>=0), exam_score numeric(7,2) not null default 0 check(exam_score>=0),
  total_score numeric(7,2) generated always as (ca_score+exam_score) stored, letter_grade text,
  status public.record_status not null default 'draft', published_at timestamptz, version integer not null default 1,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(student_id,course_id,session_id,semester_id), check((status='published' and published_at is not null) or status<>'published')
);
create table public.result_approvals (
  id uuid primary key default gen_random_uuid(), result_id uuid not null references public.results(id) on delete cascade,
  stage public.app_role not null check(stage in ('lecturer','coordinator','deo','hod','faculty','senate')),
  decision public.approval_decision not null default 'pending', comment text check(char_length(comment)<=2000), decided_by uuid references public.profiles(id) on delete restrict,
  decided_at timestamptz, created_at timestamptz not null default now(), unique(result_id,stage), check((decision='pending' and decided_at is null) or (decision<>'pending' and decided_at is not null))
);

create table public.learning_modules (
  id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade,
  title text not null check(char_length(trim(title)) between 3 and 160), content text not null check(char_length(content) between 10 and 10000),
  module_order integer not null check(module_order between 1 and 200), is_published boolean not null default false,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(course_id,module_order)
);
create table public.assignments (
  id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade,
  title text not null check(char_length(trim(title)) between 3 and 180), instructions text not null check(char_length(instructions)<=10000),
  due_at timestamptz not null, max_score numeric(7,2) not null check(max_score>0), status public.record_status not null default 'draft',
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.assignment_submissions (
  id uuid primary key default gen_random_uuid(), assignment_id uuid not null references public.assignments(id) on delete cascade,
  student_id uuid not null default auth.uid() references public.profiles(id) on delete cascade, content text not null default '' check(char_length(content)<=20000),
  storage_path text, submitted_at timestamptz, score numeric(7,2) check(score>=0), feedback text check(char_length(feedback)<=5000),
  graded_by uuid references public.profiles(id) on delete restrict, graded_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(assignment_id,student_id)
);

create table public.research_projects (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  title text not null check(char_length(trim(title)) between 10 and 220), abstract text not null check(char_length(abstract) between 50 and 5000),
  research_type text not null check(research_type in ('undergraduate','masters','doctoral','staff')), status public.research_status not null default 'draft',
  ethics_reference text, submitted_at timestamptz, approved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.research_supervisions (
  project_id uuid not null references public.research_projects(id) on delete cascade, supervisor_id uuid not null references public.profiles(id) on delete restrict,
  is_primary boolean not null default false, assigned_at timestamptz not null default now(), primary key(project_id,supervisor_id)
);
create table public.research_milestones (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.research_projects(id) on delete cascade,
  title text not null, due_on date, status public.record_status not null default 'draft', notes text check(char_length(notes)<=5000),
  completed_at timestamptz, created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict, created_at timestamptz not null default now()
);

create sequence public.transcript_reference_seq start 100001;
create table public.transcript_requests (
  id uuid primary key default gen_random_uuid(), student_id uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  reference_number text not null unique default ('TR-'||to_char(current_date,'YYYY')||'-'||nextval('public.transcript_reference_seq')),
  purpose text not null check(char_length(trim(purpose)) between 3 and 300), recipient_name text, recipient_email citext,
  status public.record_status not null default 'pending', verification_hash text unique, processed_by uuid references public.profiles(id) on delete restrict,
  processed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check(char_length(title)<=160), body text not null check(char_length(body)<=1000), link_path text,
  read_at timestamptz, created_at timestamptz not null default now()
);
create table public.audit_logs (
  id bigint generated always as identity primary key, actor_id uuid references public.profiles(id) on delete set null,
  action text not null, entity_type text not null, entity_id uuid, old_data jsonb, new_data jsonb,
  ip_address inet, user_agent text, request_id uuid default gen_random_uuid(), created_at timestamptz not null default now()
);

create index profiles_institution_idx on public.profiles(institution_id);
create index user_roles_active_idx on public.user_roles(user_id,role) where is_active;
create index courses_department_idx on public.courses(department_id);
create index enrollments_student_idx on public.enrollments(student_id,session_id);
create index enrollments_course_idx on public.enrollments(course_id,session_id);
create index exams_course_status_idx on public.exams(course_id,status,starts_at);
create index candidates_student_idx on public.exam_candidates(student_id,exam_id);
create index attempts_student_idx on public.exam_attempts(student_id,exam_id);
create index results_student_idx on public.results(student_id,session_id,status);
create index results_course_idx on public.results(course_id,session_id,status);
create index approvals_pending_idx on public.result_approvals(stage,decision) where decision='pending';
create index learning_course_idx on public.learning_modules(course_id,module_order);
create index assignments_course_idx on public.assignments(course_id,due_at);
create index research_owner_idx on public.research_projects(owner_id,status);
create index audit_actor_time_idx on public.audit_logs(actor_id,created_at desc);
create index audit_entity_idx on public.audit_logs(entity_type,entity_id,created_at desc);
create index notifications_unread_idx on public.notifications(user_id,created_at desc) where read_at is null;

commit;

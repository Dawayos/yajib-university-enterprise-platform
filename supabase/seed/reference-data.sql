-- Reference data only. Auth users and passwords are created by the protected
-- seed-demo-users Edge Function, never by browser code or migration files.
begin;
insert into public.institutions(name,code,domain)
values('YAJIB Demonstration University','YDU','yajib-demo.edu.ng')
on conflict(code) do update set name=excluded.name,domain=excluded.domain;

with inst as (select id from public.institutions where code='YDU'),
faculty as (
  insert into public.faculties(institution_id,code,name) select id,'SCI','Faculty of Computing and Applied Sciences' from inst
  on conflict(institution_id,code) do update set name=excluded.name returning id
), dept as (
  insert into public.departments(faculty_id,code,name) select id,'CSC','Department of Computer Science' from faculty
  on conflict(faculty_id,code) do update set name=excluded.name returning id
)
insert into public.courses(department_id,code,title,credit_units,level,description)
select id,'CSC401','Database Management Systems',3,400,'Advanced database design, integrity, security and distributed data systems.' from dept
on conflict(department_id,code) do update set title=excluded.title,credit_units=excluded.credit_units,level=excluded.level;

insert into public.academic_sessions(institution_id,name,starts_on,ends_on,is_current)
select id,'2026/2027','2026-09-01','2027-07-31',true from public.institutions where code='YDU'
on conflict(institution_id,name) do update set starts_on=excluded.starts_on,ends_on=excluded.ends_on,is_current=excluded.is_current;
insert into public.semesters(session_id,name,starts_on,ends_on,is_current)
select id,'First Semester','2026-09-01','2027-01-31',true from public.academic_sessions where name='2026/2027'
on conflict(session_id,name) do update set starts_on=excluded.starts_on,ends_on=excluded.ends_on,is_current=excluded.is_current;
commit;

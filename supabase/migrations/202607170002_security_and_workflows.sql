begin;

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now(); return new; end $$;
do $$ declare t text; begin foreach t in array array['institutions','profiles','faculties','departments','courses','exams','questions','results','learning_modules','assignments','assignment_submissions','research_projects','transcript_requests'] loop execute format('create trigger touch_%I before update on public.%I for each row execute function public.touch_updated_at()',t,t); end loop; end $$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.profiles(id,email,full_name,locale,is_active)
  values(new.id,new.email,coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1)),coalesce(new.raw_user_meta_data->>'locale','en'),true);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.has_role(required_role public.app_role) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role=required_role and ur.is_active and (ur.expires_at is null or ur.expires_at>now()))
$$;
create or replace function public.has_any_role(required_roles public.app_role[]) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role=any(required_roles) and ur.is_active and (ur.expires_at is null or ur.expires_at>now()))
$$;
create or replace function public.is_course_staff(target_course uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.course_staff cs where cs.course_id=target_course and cs.staff_id=auth.uid())
$$;
create or replace function public.is_enrolled(target_course uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.enrollments e where e.course_id=target_course and e.student_id=auth.uid() and e.status in ('approved','published'))
$$;

create or replace function public.set_active_role(requested_role public.app_role) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not public.has_role(requested_role) then raise exception 'ROLE_NOT_ASSIGNED' using errcode='42501'; end if;
  insert into public.user_active_roles(user_id,role,selected_at) values(auth.uid(),requested_role,now())
  on conflict(user_id) do update set role=excluded.role,selected_at=excluded.selected_at;
end $$;

create or replace function public.get_my_bootstrap() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'profile',to_jsonb(p),
    'roles',coalesce((select jsonb_agg(jsonb_build_object('role',ur.role,'expires_at',ur.expires_at) order by ur.role::text) from public.user_roles ur where ur.user_id=p.id and ur.is_active and (ur.expires_at is null or ur.expires_at>now())),'[]'::jsonb),
    'active_role',(select uar.role from public.user_active_roles uar where uar.user_id=p.id),
    'permissions','[]'::jsonb
  ) from public.profiles p where p.id=auth.uid()
$$;

create or replace function public.get_dashboard_summary() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'active_courses',(select count(*) from public.courses c where c.is_active and (public.has_any_role(array['developer','admin','registrar','vc']::public.app_role[]) or public.is_course_staff(c.id) or public.is_enrolled(c.id))),
    'pending_actions',(select count(*) from public.result_approvals ra where ra.decision='pending' and public.has_role(ra.stage)),
    'published_results',(select count(*) from public.results r where r.status='published' and (r.student_id=auth.uid() or public.is_course_staff(r.course_id) or public.has_any_role(array['developer','admin','coordinator','deo','hod','faculty','senate','registrar','vc']::public.app_role[]))),
    'research_projects',(select count(*) from public.research_projects rp where rp.owner_id=auth.uid() or exists(select 1 from public.research_supervisions rs where rs.project_id=rp.id and rs.supervisor_id=auth.uid()) or public.has_any_role(array['developer','admin','pgcoordinator','faculty','vc']::public.app_role[]))
  )
$$;

create or replace function public.guard_result_changes() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status in ('approved','published','archived') and (new.ca_score,new.exam_score,new.student_id,new.course_id,new.session_id,new.semester_id) is distinct from (old.ca_score,old.exam_score,old.student_id,old.course_id,old.session_id,old.semester_id) then
    raise exception 'APPROVED_RESULT_IMMUTABLE' using errcode='42501';
  end if;
  if new.status='published' and not public.has_any_role(array['senate','registrar','developer']::public.app_role[]) then raise exception 'PUBLISH_NOT_AUTHORIZED' using errcode='42501'; end if;
  new.version=old.version+1;
  if new.status='published' and old.status<>'published' then new.published_at=now(); end if;
  return new;
end $$;
create trigger protect_results before update on public.results for each row execute function public.guard_result_changes();

create or replace function public.decide_result_approval(target_approval uuid, requested_decision public.approval_decision, decision_comment text default null) returns public.result_approvals
language plpgsql security definer set search_path='' as $$
declare approval public.result_approvals;
begin
  if requested_decision='pending' then raise exception 'INVALID_DECISION'; end if;
  select * into approval from public.result_approvals where id=target_approval for update;
  if not found or not public.has_role(approval.stage) then raise exception 'NOT_AUTHORIZED' using errcode='42501'; end if;
  if approval.decision<>'pending' then raise exception 'ALREADY_DECIDED'; end if;
  update public.result_approvals set decision=requested_decision,comment=left(trim(decision_comment),2000),decided_by=auth.uid(),decided_at=now() where id=target_approval returning * into approval;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data) values(auth.uid(),'approval_decided','result_approval',approval.id,to_jsonb(approval));
  return approval;
end $$;

create or replace function public.verify_transcript(public_reference text, verification_code text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rec record;
begin
  select tr.reference_number,tr.status,tr.processed_at,p.full_name,p.student_number into rec
  from public.transcript_requests tr join public.profiles p on p.id=tr.student_id
  where tr.reference_number=upper(trim(public_reference)) and tr.verification_hash=encode(digest(trim(verification_code),'sha256'),'hex') and tr.status in ('approved','published');
  if not found then return jsonb_build_object('valid',false); end if;
  return jsonb_build_object('valid',true,'reference_number',rec.reference_number,'status',rec.status,'processed_at',rec.processed_at,'student_name',rec.full_name,'student_number',rec.student_number);
end $$;

revoke all on function public.has_role(public.app_role) from public;
revoke all on function public.has_any_role(public.app_role[]) from public;
revoke all on function public.is_course_staff(uuid) from public;
revoke all on function public.is_enrolled(uuid) from public;
grant execute on function public.set_active_role(public.app_role),public.get_my_bootstrap(),public.get_dashboard_summary(),public.decide_result_approval(uuid,public.approval_decision,text) to authenticated;
grant execute on function public.verify_transcript(text,text) to anon,authenticated;

do $$ declare t text; begin foreach t in array array['institutions','profiles','user_roles','user_active_roles','faculties','departments','programmes','academic_sessions','semesters','courses','course_staff','enrollments','exams','questions','exam_candidates','exam_attempts','exam_answers','results','result_approvals','learning_modules','assignments','assignment_submissions','research_projects','research_supervisions','research_milestones','transcript_requests','notifications','audit_logs'] loop execute format('alter table public.%I enable row level security',t); execute format('alter table public.%I force row level security',t); end loop; end $$;

create policy institutions_read on public.institutions for select to authenticated using(is_active or public.has_any_role(array['developer','admin']::public.app_role[]));
create policy institutions_admin on public.institutions for all to authenticated using(public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.has_any_role(array['developer','admin','lecturer','coordinator','deo','hod','faculty','senate','registrar','vc','external','supervisor','pgcoordinator','helpdesk']::public.app_role[]));
create policy profiles_self_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy profiles_admin_update on public.profiles for update to authenticated using(public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy roles_self_read on public.user_roles for select to authenticated using(user_id=auth.uid() or public.has_any_role(array['developer','admin']::public.app_role[]));
create policy roles_admin_write on public.user_roles for all to authenticated using(public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy active_roles_self on public.user_active_roles for select to authenticated using(user_id=auth.uid());

create policy faculties_read on public.faculties for select to authenticated using(true);
create policy departments_read on public.departments for select to authenticated using(true);
create policy programmes_read on public.programmes for select to authenticated using(true);
create policy sessions_read on public.academic_sessions for select to authenticated using(true);
create policy semesters_read on public.semesters for select to authenticated using(true);
create policy courses_read on public.courses for select to authenticated using(is_active or public.has_any_role(array['developer','admin','registrar']::public.app_role[]));
create policy structure_admin_faculty on public.faculties for all to authenticated using(public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy structure_admin_department on public.departments for all to authenticated using(public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy structure_admin_programme on public.programmes for all to authenticated using(public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy structure_admin_courses on public.courses for all to authenticated using(public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy course_staff_read on public.course_staff for select to authenticated using(staff_id=auth.uid() or public.has_any_role(array['developer','admin','coordinator','deo','hod','faculty']::public.app_role[]));
create policy course_staff_admin on public.course_staff for all to authenticated using(public.has_any_role(array['developer','admin','hod']::public.app_role[])) with check(public.has_any_role(array['developer','admin','hod']::public.app_role[]));
create policy enrollment_read on public.enrollments for select to authenticated using(student_id=auth.uid() or public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','coordinator','deo','hod','faculty','registrar','pgcoordinator']::public.app_role[]));
create policy enrollment_manage on public.enrollments for all to authenticated using(public.has_any_role(array['developer','admin','registrar']::public.app_role[])) with check(public.has_any_role(array['developer','admin','registrar']::public.app_role[]));

create policy exams_read on public.exams for select to authenticated using(public.is_course_staff(course_id) or exists(select 1 from public.exam_candidates ec where ec.exam_id=id and ec.student_id=auth.uid()) or public.has_any_role(array['developer','admin','coordinator','deo','hod','faculty','external','invigilator']::public.app_role[]));
create policy exams_create on public.exams for insert to authenticated with check(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[]));
create policy exams_update on public.exams for update to authenticated using(created_by=auth.uid() or public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[])) with check(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[]));
create policy questions_staff on public.questions for all to authenticated using(exists(select 1 from public.exams e where e.id=exam_id and (public.is_course_staff(e.course_id) or public.has_any_role(array['developer','admin','deo','external']::public.app_role[])))) with check(exists(select 1 from public.exams e where e.id=exam_id and (public.is_course_staff(e.course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[]))));
create policy candidates_self_read on public.exam_candidates for select to authenticated using(student_id=auth.uid() or exists(select 1 from public.exams e where e.id=exam_id and public.is_course_staff(e.course_id)) or public.has_any_role(array['developer','admin','deo','invigilator']::public.app_role[]));
create policy candidates_staff_manage on public.exam_candidates for all to authenticated using(exists(select 1 from public.exams e where e.id=exam_id and (public.is_course_staff(e.course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[])))) with check(exists(select 1 from public.exams e where e.id=exam_id and (public.is_course_staff(e.course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[]))));
create policy attempts_read on public.exam_attempts for select to authenticated using(student_id=auth.uid() or exists(select 1 from public.exams e where e.id=exam_id and public.is_course_staff(e.course_id)) or public.has_any_role(array['developer','admin','deo','invigilator']::public.app_role[]));
create policy attempts_student_insert on public.exam_attempts for insert to authenticated with check(student_id=auth.uid() and exists(select 1 from public.exam_candidates ec join public.exams e on e.id=ec.exam_id where ec.exam_id=exam_id and ec.student_id=auth.uid() and ec.eligibility='eligible' and e.status='open' and now() between e.starts_at and e.ends_at));
create policy attempts_student_update on public.exam_attempts for update to authenticated using(student_id=auth.uid() and status='in_progress') with check(student_id=auth.uid());
create policy answers_read on public.exam_answers for select to authenticated using(exists(select 1 from public.exam_attempts a join public.exams e on e.id=a.exam_id where a.id=attempt_id and (a.student_id=auth.uid() or public.is_course_staff(e.course_id) or public.has_any_role(array['developer','admin','deo','external']::public.app_role[]))));
create policy answers_student_write on public.exam_answers for insert to authenticated with check(exists(select 1 from public.exam_attempts a where a.id=attempt_id and a.student_id=auth.uid() and a.status='in_progress'));
create policy answers_student_update on public.exam_answers for update to authenticated using(exists(select 1 from public.exam_attempts a where a.id=attempt_id and a.student_id=auth.uid() and a.status='in_progress')) with check(exists(select 1 from public.exam_attempts a where a.id=attempt_id and a.student_id=auth.uid() and a.status='in_progress'));

create policy results_read on public.results for select to authenticated using((student_id=auth.uid() and status='published') or public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','coordinator','deo','hod','faculty','senate','registrar','vc','external']::public.app_role[]));
create policy results_create on public.results for insert to authenticated with check(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[]));
create policy results_update on public.results for update to authenticated using(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','coordinator','deo','hod','faculty','senate','registrar']::public.app_role[])) with check(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','coordinator','deo','hod','faculty','senate','registrar']::public.app_role[]));
create policy approvals_read on public.result_approvals for select to authenticated using(public.has_role(stage) or exists(select 1 from public.results r where r.id=result_id and (r.student_id=auth.uid() or public.is_course_staff(r.course_id))) or public.has_any_role(array['developer','admin','registrar','vc']::public.app_role[]));
create policy approvals_create on public.result_approvals for insert to authenticated with check(exists(select 1 from public.results r where r.id=result_id and (public.is_course_staff(r.course_id) or public.has_any_role(array['developer','admin','deo']::public.app_role[]))));

create policy learning_read on public.learning_modules for select to authenticated using((is_published and public.is_enrolled(course_id)) or public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','coordinator','hod']::public.app_role[]));
create policy learning_manage on public.learning_modules for all to authenticated using(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin']::public.app_role[]));
create policy assignments_read on public.assignments for select to authenticated using((status in ('approved','published') and public.is_enrolled(course_id)) or public.is_course_staff(course_id) or public.has_any_role(array['developer','admin','coordinator','hod']::public.app_role[]));
create policy assignments_manage on public.assignments for all to authenticated using(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin']::public.app_role[])) with check(public.is_course_staff(course_id) or public.has_any_role(array['developer','admin']::public.app_role[]));
create policy submissions_read on public.assignment_submissions for select to authenticated using(student_id=auth.uid() or exists(select 1 from public.assignments a where a.id=assignment_id and public.is_course_staff(a.course_id)) or public.has_any_role(array['developer','admin']::public.app_role[]));
create policy submissions_student_manage on public.assignment_submissions for all to authenticated using(student_id=auth.uid() and score is null) with check(student_id=auth.uid());
create policy submissions_staff_update on public.assignment_submissions for update to authenticated using(exists(select 1 from public.assignments a where a.id=assignment_id and public.is_course_staff(a.course_id))) with check(exists(select 1 from public.assignments a where a.id=assignment_id and public.is_course_staff(a.course_id)));

create policy research_read on public.research_projects for select to authenticated using(owner_id=auth.uid() or exists(select 1 from public.research_supervisions rs where rs.project_id=id and rs.supervisor_id=auth.uid()) or public.has_any_role(array['developer','admin','pgcoordinator','faculty','vc']::public.app_role[]));
create policy research_owner_create on public.research_projects for insert to authenticated with check(owner_id=auth.uid());
create policy research_owner_update on public.research_projects for update to authenticated using(owner_id=auth.uid() and status in ('draft','revision_required')) with check(owner_id=auth.uid());
create policy research_review_update on public.research_projects for update to authenticated using(exists(select 1 from public.research_supervisions rs where rs.project_id=id and rs.supervisor_id=auth.uid()) or public.has_any_role(array['developer','admin','pgcoordinator']::public.app_role[])) with check(true);
create policy supervision_read on public.research_supervisions for select to authenticated using(supervisor_id=auth.uid() or exists(select 1 from public.research_projects rp where rp.id=project_id and rp.owner_id=auth.uid()) or public.has_any_role(array['developer','admin','pgcoordinator']::public.app_role[]));
create policy supervision_manage on public.research_supervisions for all to authenticated using(public.has_any_role(array['developer','admin','pgcoordinator']::public.app_role[])) with check(public.has_any_role(array['developer','admin','pgcoordinator']::public.app_role[]));
create policy milestones_read on public.research_milestones for select to authenticated using(exists(select 1 from public.research_projects rp where rp.id=project_id and (rp.owner_id=auth.uid() or exists(select 1 from public.research_supervisions rs where rs.project_id=rp.id and rs.supervisor_id=auth.uid()))) or public.has_any_role(array['developer','admin','pgcoordinator']::public.app_role[]));
create policy milestones_manage on public.research_milestones for all to authenticated using(created_by=auth.uid() or public.has_any_role(array['developer','admin','pgcoordinator']::public.app_role[])) with check(created_by=auth.uid() or public.has_any_role(array['developer','admin','pgcoordinator']::public.app_role[]));

create policy transcripts_read on public.transcript_requests for select to authenticated using(student_id=auth.uid() or public.has_any_role(array['developer','admin','registrar','transcript_verification']::public.app_role[]));
create policy transcripts_student_create on public.transcript_requests for insert to authenticated with check(student_id=auth.uid());
create policy transcripts_staff_update on public.transcript_requests for update to authenticated using(public.has_any_role(array['developer','admin','registrar']::public.app_role[])) with check(public.has_any_role(array['developer','admin','registrar']::public.app_role[]));
create policy notifications_self_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy notifications_self_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy notifications_service_insert on public.notifications for insert to authenticated with check(public.has_any_role(array['developer','admin']::public.app_role[]));
create policy audit_read on public.audit_logs for select to authenticated using(actor_id=auth.uid() or public.has_any_role(array['developer','admin','vc','helpdesk']::public.app_role[]));

alter publication supabase_realtime add table public.notifications,public.exams,public.results,public.result_approvals,public.learning_modules,public.assignments,public.research_projects,public.transcript_requests;

commit;

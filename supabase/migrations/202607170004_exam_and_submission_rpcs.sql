begin;

create or replace function public.start_exam_attempt(target_exam uuid, fingerprint_hash text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare exam_row public.exams; candidate_row public.exam_candidates; attempt_count integer; new_id uuid;
begin
  select * into exam_row from public.exams where id=target_exam for share;
  if not found or exam_row.status<>'open' or now() not between exam_row.starts_at and exam_row.ends_at then raise exception 'EXAM_NOT_OPEN'; end if;
  select * into candidate_row from public.exam_candidates where exam_id=target_exam and student_id=auth.uid() for update;
  if not found or candidate_row.eligibility<>'eligible' then raise exception 'NOT_ELIGIBLE' using errcode='42501'; end if;
  select count(*) into attempt_count from public.exam_attempts where exam_id=target_exam and student_id=auth.uid();
  if attempt_count>=exam_row.max_attempts then raise exception 'ATTEMPT_LIMIT_REACHED'; end if;
  insert into public.exam_attempts(exam_id,student_id,attempt_number,client_fingerprint_hash)
  values(target_exam,auth.uid(),attempt_count+1,left(fingerprint_hash,128)) returning id into new_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data) values(auth.uid(),'exam_started','exam_attempt',new_id,jsonb_build_object('exam_id',target_exam));
  return new_id;
end $$;

create or replace function public.get_exam_questions(target_attempt uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare attempt_row public.exam_attempts; exam_row public.exams;
begin
  select * into attempt_row from public.exam_attempts where id=target_attempt and student_id=auth.uid();
  if not found or attempt_row.status<>'in_progress' then raise exception 'INVALID_ATTEMPT' using errcode='42501'; end if;
  select * into exam_row from public.exams where id=attempt_row.exam_id;
  if now()>least(exam_row.ends_at,attempt_row.started_at+make_interval(mins=>exam_row.duration_minutes)) then raise exception 'ATTEMPT_EXPIRED'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'question_type',q.question_type,'prompt',q.prompt,'options',q.options,'marks',q.marks,'position',q.position) order by case when exam_row.randomize_questions then md5(q.id::text||target_attempt::text) else lpad(q.position::text,10,'0') end),'[]'::jsonb) from public.questions q where q.exam_id=exam_row.id);
end $$;

create or replace function public.save_exam_answer(target_attempt uuid, target_question uuid, submitted_answer jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare attempt_row public.exam_attempts; exam_row public.exams;
begin
  if pg_column_size(submitted_answer)>32768 then raise exception 'ANSWER_TOO_LARGE'; end if;
  select * into attempt_row from public.exam_attempts where id=target_attempt and student_id=auth.uid() for update;
  if not found or attempt_row.status<>'in_progress' then raise exception 'INVALID_ATTEMPT' using errcode='42501'; end if;
  select * into exam_row from public.exams where id=attempt_row.exam_id;
  if now()>least(exam_row.ends_at,attempt_row.started_at+make_interval(mins=>exam_row.duration_minutes)) then
    update public.exam_attempts set status='auto_submitted',submitted_at=now() where id=target_attempt;
    raise exception 'ATTEMPT_EXPIRED';
  end if;
  if not exists(select 1 from public.questions q where q.id=target_question and q.exam_id=attempt_row.exam_id) then raise exception 'QUESTION_NOT_IN_EXAM'; end if;
  insert into public.exam_answers(attempt_id,question_id,answer,saved_at) values(target_attempt,target_question,submitted_answer,now())
  on conflict(attempt_id,question_id) do update set answer=excluded.answer,saved_at=excluded.saved_at where public.exam_answers.marked_at is null;
end $$;

create or replace function public.submit_exam_attempt(target_attempt uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  update public.exam_attempts set status='submitted',submitted_at=now() where id=target_attempt and student_id=auth.uid() and status='in_progress';
  if not found then raise exception 'INVALID_ATTEMPT' using errcode='42501'; end if;
  update public.exam_candidates ec set eligibility='completed' where ec.exam_id=(select exam_id from public.exam_attempts where id=target_attempt) and ec.student_id=auth.uid();
  insert into public.audit_logs(actor_id,action,entity_type,entity_id) values(auth.uid(),'exam_submitted','exam_attempt',target_attempt);
end $$;

create or replace function public.submit_research_project(target_project uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  update public.research_projects set status='submitted',submitted_at=now() where id=target_project and owner_id=auth.uid() and status in ('draft','revision_required');
  if not found then raise exception 'PROJECT_NOT_SUBMITTABLE' using errcode='42501'; end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id) values(auth.uid(),'research_submitted','research_project',target_project);
end $$;

create or replace function public.request_transcript(request_purpose text, target_name text default null, target_email citext default null) returns text
language plpgsql security definer set search_path='' as $$
declare ref text;
begin
  if char_length(trim(request_purpose)) not between 3 and 300 then raise exception 'INVALID_PURPOSE'; end if;
  if target_email is not null and target_email::text !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'INVALID_EMAIL'; end if;
  insert into public.transcript_requests(student_id,purpose,recipient_name,recipient_email)
  values(auth.uid(),trim(request_purpose),left(trim(target_name),160),target_email) returning reference_number into ref;
  insert into public.audit_logs(actor_id,action,entity_type,new_data) values(auth.uid(),'transcript_requested','transcript_request',jsonb_build_object('reference_number',ref));
  return ref;
end $$;

grant execute on function public.start_exam_attempt(uuid,text),public.get_exam_questions(uuid),public.save_exam_answer(uuid,uuid,jsonb),public.submit_exam_attempt(uuid),public.submit_research_project(uuid),public.request_transcript(text,text,citext) to authenticated;
commit;

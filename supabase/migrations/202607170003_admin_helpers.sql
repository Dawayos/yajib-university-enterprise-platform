begin;
create or replace function public.find_auth_user_id_by_email(target_email citext) returns uuid
language sql stable security definer set search_path='' as $$ select id from auth.users where lower(email)=lower(target_email::text) limit 1 $$;
revoke all on function public.find_auth_user_id_by_email(citext) from public,anon,authenticated;
grant execute on function public.find_auth_user_id_by_email(citext) to service_role;

revoke update on public.profiles from authenticated;
grant update(full_name,phone,locale,avatar_path,last_seen_at) on public.profiles to authenticated;
revoke insert,update,delete on public.audit_logs from authenticated;
grant select on public.audit_logs to authenticated;
commit;

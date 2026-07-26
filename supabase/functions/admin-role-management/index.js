import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const roles = new Set(["developer","admin","lecturer","student","coordinator","deo","hod","faculty","senate","registrar","vc","external","supervisor","pgcoordinator","invigilator","helpdesk","transcript_verification"]);
const allowedOrigin = Deno.env.get("APP_ORIGIN") || "";
const headers = { "content-type":"application/json; charset=utf-8", "cache-control":"no-store", "vary":"origin", ...(allowedOrigin ? {"access-control-allow-origin":allowedOrigin} : {}) };
const reply = (status,body) => new Response(JSON.stringify(body),{status,headers});

Deno.serve(async request => {
  if(request.method==="OPTIONS")return new Response(null,{status:204,headers:{...headers,"access-control-allow-methods":"POST, OPTIONS","access-control-allow-headers":"authorization, content-type, apikey, x-client-info"}});
  if(request.method!=="POST")return reply(405,{error:"METHOD_NOT_ALLOWED"});
  const authHeader=request.headers.get("authorization")||"";
  if(!authHeader.startsWith("Bearer "))return reply(401,{error:"AUTH_REQUIRED"});
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return reply(500,{error:"SERVER_CONFIGURATION_ERROR"});
  const userClient=createClient(url,anon,{global:{headers:{Authorization:authHeader}},auth:{persistSession:false}});
  const {data:{user}}=await userClient.auth.getUser();
  if(!user)return reply(401,{error:"INVALID_SESSION"});
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:callerRoles}=await admin.from("user_roles").select("role").eq("user_id",user.id).eq("is_active",true);
  if(!callerRoles?.some(r=>r.role==="developer"||r.role==="admin"))return reply(403,{error:"FORBIDDEN"});
  let body;try{body=await request.json()}catch{return reply(400,{error:"INVALID_JSON"})}
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.user_id||"")||!roles.has(body.role)||!["grant","revoke"].includes(body.action))return reply(422,{error:"INVALID_INPUT"});
  if(body.user_id===user.id&&body.role==="developer"&&body.action==="revoke")return reply(409,{error:"CANNOT_REVOKE_OWN_DEVELOPER_ROLE"});
  let error;
  if(body.action==="grant")({error}=await admin.from("user_roles").upsert({user_id:body.user_id,role:body.role,is_active:true,granted_by:user.id},{onConflict:"user_id,role"}));
  else ({error}=await admin.from("user_roles").update({is_active:false}).eq("user_id",body.user_id).eq("role",body.role));
  if(error)return reply(500,{error:"ROLE_CHANGE_FAILED"});
  await admin.from("audit_logs").insert({actor_id:user.id,action:`role_${body.action}`,entity_type:"user_role",entity_id:body.user_id,new_data:{role:body.role}});
  return reply(200,{success:true});
});

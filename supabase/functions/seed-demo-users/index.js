import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const jsonHeaders = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" };
const demoUsers = [
  { email:"yajibsms@gmail.com", password:"TempDev@1234", role:"developer", name:"YAJIB Platform Developer" },
  { email:"admin@yajib-demo.edu.ng", role:"admin", name:"Demo System Administrator" },
  { email:"lecturer@yajib-demo.edu.ng", role:"lecturer", name:"Dr Demo Lecturer" },
  { email:"coordinator@yajib-demo.edu.ng", role:"coordinator", name:"Demo Level Coordinator" },
  { email:"deo@yajib-demo.edu.ng", role:"deo", name:"Demo Departmental Exam Officer" },
  { email:"hod@yajib-demo.edu.ng", role:"hod", name:"Demo Head of Department" },
  { email:"faculty@yajib-demo.edu.ng", role:"faculty", name:"Demo Faculty Dean" },
  { email:"senate@yajib-demo.edu.ng", role:"senate", name:"Demo Senate Member" },
  { email:"registrar@yajib-demo.edu.ng", role:"registrar", name:"Demo Registrar" },
  { email:"vc@yajib-demo.edu.ng", role:"vc", name:"Demo Vice-Chancellor" },
  { email:"external@yajib-demo.edu.ng", role:"external", name:"Demo External Examiner" },
  { email:"supervisor@yajib-demo.edu.ng", role:"supervisor", name:"Demo Research Supervisor" },
  { email:"pgcoordinator@yajib-demo.edu.ng", role:"pgcoordinator", name:"Demo PG Coordinator" },
  { email:"invigilator@yajib-demo.edu.ng", role:"invigilator", name:"Demo Invigilator" },
  { email:"helpdesk@yajib-demo.edu.ng", role:"helpdesk", name:"Demo Help Desk Officer" },
  { email:"student001@yajib-demo.edu.ng", role:"student", name:"Demo Student", studentNumber:"YDU/CSC/2026/001" },
  { email:"transcriptverification@yajib-demo.edu.ng", role:"transcript_verification", name:"Transcript Verification Officer" }
];

function response(status, body) { return new Response(JSON.stringify(body), { status, headers:jsonHeaders }); }

Deno.serve(async request => {
  if (request.method !== "POST") return response(405, { error:"METHOD_NOT_ALLOWED" });
  if (Deno.env.get("ALLOW_DEMO_SEED") !== "true") return response(403, { error:"DEMO_SEED_DISABLED" });
  const suppliedSecret = request.headers.get("x-seed-secret") || "";
  const expectedSecret = Deno.env.get("DEMO_SEED_SECRET") || "";
  if (expectedSecret.length < 32 || suppliedSecret !== expectedSecret) return response(401, { error:"UNAUTHORIZED" });
  const url = Deno.env.get("SUPABASE_URL"), serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return response(500, { error:"SERVER_CONFIGURATION_ERROR" });
  const admin = createClient(url, serviceKey, { auth:{ persistSession:false,autoRefreshToken:false } });
  const { data: institution, error: institutionError } = await admin.from("institutions").select("id").eq("code","YDU").single();
  if (institutionError) return response(409, { error:"REFERENCE_DATA_REQUIRED" });
  const created = [], existing = [];
  for (const record of demoUsers) {
    const { data: found } = await admin.rpc("find_auth_user_id_by_email", { target_email:record.email });
    let userId = found;
    if (!userId) {
      const password = record.password || "DemoUser@1234";
      const { data, error } = await admin.auth.admin.createUser({ email:record.email,password,email_confirm:true,user_metadata:{full_name:record.name,locale:"en"} });
      if (error) return response(500, { error:"USER_CREATE_FAILED", account:record.email });
      userId = data.user.id; created.push(record.email);
    } else existing.push(record.email);
    const { error: profileError } = await admin.from("profiles").update({ institution_id:institution.id,full_name:record.name,student_number:record.studentNumber||null,is_active:true }).eq("id",userId);
    if (profileError) return response(500, { error:"PROFILE_UPDATE_FAILED", account:record.email });
    const { error: roleError } = await admin.from("user_roles").upsert({ user_id:userId,role:record.role,is_active:true },{ onConflict:"user_id,role" });
    if (roleError) return response(500, { error:"ROLE_ASSIGNMENT_FAILED", account:record.email });
  }
  return response(200, { success:true, created_count:created.length, existing_count:existing.length, next_action:"Set ALLOW_DEMO_SEED=false immediately." });
});

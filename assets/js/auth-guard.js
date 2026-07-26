import { getSupabase } from "./supabase-client.js";

const ROUTES = Object.freeze({ developer:"developer.html", admin:"admin.html", lecturer:"lecturer.html", student:"student.html", coordinator:"coordinator.html", deo:"deo.html", hod:"hod.html", faculty:"faculty.html", senate:"senate.html", registrar:"registrar.html", vc:"vc.html", external:"external.html", supervisor:"supervisor.html", pgcoordinator:"pgcoordinator.html", invigilator:"invigilator.html", helpdesk:"helpdesk.html", transcript_verification:"transcript-verification.html" });

export async function requireRole(requiredRole) {
  const supabase = await getSupabase();
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  if (sessionError || !session) return redirectToLogin();
  const { data, error } = await supabase.rpc("get_my_bootstrap");
  if (error) throw error;
  const bootstrap = Array.isArray(data) ? data[0] : data;
  const roles = (bootstrap?.roles || []).map(item => typeof item === "string" ? item : item.role);
  if (!bootstrap?.profile?.is_active) {
    await supabase.auth.signOut();
    return redirectToLogin("inactive");
  }
  if (!roles.includes(requiredRole)) {
    const fallback = roles.find(role => ROUTES[role]);
    location.replace(fallback ? ROUTES[fallback] : "../index.html?error=no-role");
    return new Promise(() => {});
  }
  await supabase.rpc("set_active_role", { requested_role: requiredRole });
  return { supabase, session, profile: bootstrap.profile, roles, permissions: bootstrap.permissions || [] };
}

export function redirectToLogin(reason = "session") {
  const url = new URL("../index.html", location.href);
  url.searchParams.set("reason", reason);
  location.replace(url.href);
  return new Promise(() => {});
}

export async function signOut() {
  try { (await getSupabase()).auth.signOut(); } finally { location.replace("../index.html"); }
}

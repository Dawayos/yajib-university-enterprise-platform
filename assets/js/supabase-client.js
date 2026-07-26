let clientPromise;

export function getSupabase() {
  if (clientPromise) return clientPromise;
  clientPromise = (async () => {
    const config = window.__YAJIB_CONFIG__ || {};
    if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(config.supabaseUrl || "")) {
      throw new Error("CONFIG_MISSING");
    }
    if (!(config.supabaseAnonKey || "").startsWith("eyJ")) {
      throw new Error("CONFIG_MISSING");
    }
    const { createClient } = await import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm");
    return createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: "yajib-nexus-auth" },
      global: { headers: { "X-Client-Info": "yajib-nexus-web/1.0" } }
    });
  })();
  return clientPromise;
}

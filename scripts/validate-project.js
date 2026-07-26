import { readFile, access } from "node:fs/promises";
import { resolve } from "node:path";

const root=resolve(import.meta.dirname,"..");
const required=["index.html","reset-password.html","runtime-config.js","assets/css/app.css","assets/js/dashboard.js","supabase/config.toml","supabase/migrations/202607170001_core_schema.sql","supabase/migrations/202607170002_security_and_workflows.sql","supabase/functions/seed-demo-users/index.js"];
const failures=[];
for(const file of required){try{await access(resolve(root,file))}catch{failures.push(`Missing ${file}`)}}
const index=await readFile(resolve(root,"index.html"),"utf8");
if(!index.includes('<html lang="en" dir="ltr">'))failures.push("index.html needs a default language and direction");
if(!index.includes("Content-Security-Policy"))failures.push("index.html needs CSP");
if(/TempDev@1234|DemoUser@1234|SUPABASE_SERVICE_ROLE_KEY/.test(index))failures.push("index.html contains forbidden secret material");
if(failures.length){console.error(failures.join("\n"));process.exit(1)}
console.log(`Project validation passed (${required.length} required artifacts checked).`);

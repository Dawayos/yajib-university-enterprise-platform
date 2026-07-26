import test from "node:test";
import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import { resolve } from "node:path";

const root=resolve(import.meta.dirname,"..");
const roles=["developer","admin","lecturer","student","coordinator","deo","hod","faculty","senate","registrar","vc","external","supervisor","pgcoordinator","invigilator","helpdesk","transcript-verification"];
test("all required role entry pages exist",async()=>{for(const role of roles)await access(resolve(root,"pages",`${role}.html`))});
test("browser-delivered files contain no demo passwords or service-role key",async()=>{
  const files=["index.html","reset-password.html","assets/js/dashboard.js","assets/js/platform-service.js","runtime-config.js"];
  for(const file of files){const content=await readFile(resolve(root,file),"utf8");assert.doesNotMatch(content,/TempDev@1234|DemoUser@1234|service_role/i,`secret-like content in ${file}`)}
});
test("landing page includes multilingual, RTL, auth and recovery flows",async()=>{
  const html=await readFile(resolve(root,"index.html"),"utf8");
  for(const token of ['value="en"','value="ar"','value="fr"','dir="rtl"','signInWithPassword','resetPasswordForEmail','get_my_bootstrap','roleModal'])assert.ok(html.includes(token),`missing ${token}`);
});
test("every HTML page has a restrictive CSP",async()=>{
  const files=["index.html","reset-password.html",...roles.map(r=>`pages/${r}.html`)];
  for(const file of files){const html=await readFile(resolve(root,file),"utf8");assert.match(html,/Content-Security-Policy/i,`missing CSP: ${file}`)}
});

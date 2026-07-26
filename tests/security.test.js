import test from "node:test";
import assert from "node:assert/strict";
import { safeText, validEmail, validUuid, statusClass } from "../assets/js/security.js";

test("safeText strips control characters and bounds input",()=>{
  assert.equal(safeText("  hello\u0000world  ",20),"helloworld");
  assert.equal(safeText("abcdef",3),"abc");
});
test("email validation rejects malformed and oversized addresses",()=>{
  assert.equal(validEmail("student@example.edu"),true);
  assert.equal(validEmail("student@@example.edu"),false);
  assert.equal(validEmail(`${"a".repeat(250)}@x.io`),false);
});
test("UUID validation accepts canonical UUIDs only",()=>{
  assert.equal(validUuid("8f0f0e42-f5f1-4e17-bf16-65f923f26a90"),true);
  assert.equal(validUuid("../../etc/passwd"),false);
});
test("statusClass cannot inject markup or arbitrary CSS",()=>{
  assert.equal(statusClass('<img src=x onerror="x">'),"imgsrcxonerrorx");
});

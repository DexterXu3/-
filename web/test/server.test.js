import assert from "node:assert/strict";
import test from "node:test";
import { auditThroughAgent, buildPrompt, evidenceDigestFor, isAuthorized, isRateLimited, maxCodeLength, parseAgentReport, validateAudit } from "../server.js";

function validReport({requestId, filename="route.js", language="javascript", code="const ok=true;", findings=[]}) {
  const scannedLines = code.split(/\r?\n/).length;
  return {requestId, title:"安全审计结果", filename, scannedLines, findings,
    toolEvidence:{provider:"octobus", capset:"local/security-review", method:"codesecurity.v1.CodeSecurityService/AnalyzeSnippet",
      evidenceDigest:evidenceDigestFor({filename, language, scannedLines, findings})},
    manualReview:[], disclaimer:"初筛"};
}

test("accepts a valid audit request", () => assert.equal(validateAudit({ filename:"route.js", language:"javascript", code:"const ok = true;" }), null));
test("rejects empty code", () => assert.match(validateAudit({ filename:"route.js", language:"javascript", code:"  " }), /代码/));
test("rejects oversized code", () => assert.match(validateAudit({ filename:"route.js", language:"javascript", code:"a".repeat(maxCodeLength+1) }), /200,000/));
test("rejects path-like filenames", () => assert.match(validateAudit({ filename:"../secret.js", language:"javascript", code:"x" }), /文件名/));
test("rejects unsafe request IDs", () => assert.match(validateAudit({ requestId:"bad id!", filename:"route.js", language:"javascript", code:"x" }), /请求 ID/));
test("rejects unsupported languages", () => assert.match(validateAudit({ filename:"route.js", language:"brainfuck", code:"x" }), /仅支持/));
test("rejects languages not implemented by the deterministic rules", () => assert.match(validateAudit({ filename:"route.py", language:"python", code:"print(1)" }), /仅支持/));

test("rejects unauthenticated requests", () => assert.equal(isAuthorized({headers:{}, socket:{}}), false));
test("rate limiter rejects requests beyond the configured window quota", () => {
  const client = `test-${Date.now()}`;
  for (let index = 0; index < 10; index += 1) assert.equal(isRateLimited(client, 1_000), false);
  assert.equal(isRateLimited(client, 1_000), true);
  assert.equal(isRateLimited(client, 62_000), false);
});

test("prompt requires the Agent to call Skill and OctoBus", () => {
  const prompt = buildPrompt({ requestId:"audit-1", filename:"route.js", language:"javascript", code:"const ok=true;" });
  assert.match(prompt, /必须调用 code-security Skill/);
  assert.match(prompt, /OctoBus/);
  assert.match(prompt, /audit-1/);
  assert.match(prompt, /codeBase64/);
  assert.match(prompt, /Y29uc3Qgb2s9dHJ1ZTs=/);
});

test("parses a successful structured Agent report and exposes run evidence", () => {
  const code = "const ok=true;";
  const report = parseAgentReport({ run:{ summary:{status:"RUN_STATUS_SUCCEEDED", runId:"run-123"}, resultJson:JSON.stringify(validReport({requestId:"audit-1", code})) } }, {requestId:"audit-1", filename:"route.js", language:"javascript", code, projectId:"project-1"});
  assert.equal(report.runId, "run-123");
  assert.equal(report.projectId, "project-1");
  assert.equal(report.pipeline.web, "agent-compose");
  assert.equal(report.pipeline.skill, "code-security");
});

test("rejects an Agent report without a verifiable OctoBus evidence digest", () => {
  const code = "const ok=true;";
  const report = validReport({requestId:"audit-no-proof", code});
  report.toolEvidence.evidenceDigest = "0".repeat(64);
  assert.throws(() => parseAgentReport({run:{summary:{status:"RUN_STATUS_SUCCEEDED"}, resultJson:JSON.stringify(report)}},
    {requestId:"audit-no-proof", filename:"route.js", language:"javascript", code}), /证据摘要/);
});

test("accepts a verified zero-finding tool result", () => {
  const code = "const ok=true;";
  const report = validReport({requestId:"audit-clean", code});
  assert.equal(parseAgentReport({run:{summary:{status:"RUN_STATUS_SUCCEEDED"}, resultJson:JSON.stringify(report)}},
    {requestId:"audit-clean", filename:"route.js", language:"javascript", code}).findings.length, 0);
});

test("accepts scanner line normalization of trailing blank lines but rejects overflow", () => {
  const code = "const ok=true;\n\n";
  const report = validReport({requestId:"audit-lines", code:"const ok=true;"});
  assert.equal(parseAgentReport({run:{summary:{status:"RUN_STATUS_SUCCEEDED"}, resultJson:JSON.stringify(report)}},
    {requestId:"audit-lines", filename:"route.js", language:"javascript", code}).scannedLines, 1);
  report.scannedLines = 4;
  report.toolEvidence.evidenceDigest = evidenceDigestFor({filename:"route.js", language:"javascript", scannedLines:4, findings:[]});
  assert.throws(() => parseAgentReport({run:{summary:{status:"RUN_STATUS_SUCCEEDED"}, resultJson:JSON.stringify(report)}},
    {requestId:"audit-lines", filename:"route.js", language:"javascript", code}), /扫描行数/);
});

test("Web audit calls Agent Compose project and run APIs, never OctoBus directly", async () => {
  const originalFetch = global.fetch;
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({url:String(url), body:JSON.parse(options.body)});
    if (String(url).endsWith("/ListProjects")) return new Response(JSON.stringify({projects:[{projectId:"project-1", name:"qwen-agent-mvp"}]}), {status:200});
    return new Response(JSON.stringify({run:{summary:{status:"RUN_STATUS_SUCCEEDED", runId:"run-e2e"}, resultJson:JSON.stringify(validReport({requestId:"audit-e2e"}))}}), {status:200});
  };
  try {
    const result = await auditThroughAgent({filename:"route.js", language:"javascript", code:"const ok=true;"}, "audit-e2e");
    assert.equal(result.runId, "run-e2e");
    assert.equal(calls.length, 2);
    assert.ok(calls.every(call => call.url.includes("agent-compose")));
    assert.ok(calls.every(call => !call.url.includes("octobus")));
    assert.equal(calls[1].body.agentName, "assistant");
    assert.match(calls[1].body.prompt, /code-security Skill/);
    assert.equal(calls[1].body.outputSchemaJson, undefined);
  } finally { global.fetch = originalFetch; }
});

test("retries once when the first Agent report fails evidence validation", async () => {
  const originalFetch = global.fetch;
  let runAttempt = 0;
  global.fetch = async (url) => {
    if (String(url).endsWith("/ListProjects")) return new Response(JSON.stringify({projects:[{projectId:"project-1", name:"qwen-agent-mvp"}]}), {status:200});
    runAttempt += 1;
    const report = validReport({requestId:"audit-retry"});
    if (runAttempt === 1) report.toolEvidence.evidenceDigest = "bad";
    return new Response(JSON.stringify({run:{summary:{status:"RUN_STATUS_SUCCEEDED", runId:`run-${runAttempt}`}, resultJson:JSON.stringify(report)}}), {status:200});
  };
  try {
    const result = await auditThroughAgent({filename:"route.js", language:"javascript", code:"const ok=true;"}, "audit-retry");
    assert.equal(result.attempts, 2);
    assert.equal(result.runId, "run-2");
  } finally { global.fetch = originalFetch; }
});

test("ignores Pi runner metadata and parses fenced Agent JSON output", () => {
  const code = "const ok=true;";
  const output = `\`\`\`json\n${JSON.stringify(validReport({requestId:"audit-fenced", code}))}\n\`\`\``;
  const report = parseAgentReport({run:{summary:{status:"RUN_STATUS_SUCCEEDED", runId:"run-fenced"}, resultJson:JSON.stringify({agent:"pi", success:true}), output}}, {requestId:"audit-fenced", filename:"route.js", language:"javascript", code});
  assert.equal(report.runId, "run-fenced");
});

test("Web audit fails closed when Agent Compose is unavailable", async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => { throw new Error("connection refused"); };
  try {
    await assert.rejects(() => auditThroughAgent({filename:"route.js", language:"javascript", code:"const ok=true;"}, "audit-down"), /connection refused/);
  } finally { global.fetch = originalFetch; }
});

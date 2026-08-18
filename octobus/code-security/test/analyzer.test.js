import assert from "node:assert/strict";
import test from "node:test";

import { analyzeSnippet } from "../lib/analyzer.js";

test("reports command injection with evidence and line number", () => {
  const result = analyzeSnippet({
    filename: "route.js",
    language: "javascript",
    code: "const safe = true;\nexec(req.query.command);"
  });

  assert.equal(result.findings.length, 1);
  assert.equal(result.findings[0].ruleId, "CMD_INJECTION");
  assert.equal(result.findings[0].line, 2);
  assert.match(result.findings[0].remediation, /allowlist/i);
});

test("reports command injection across input and execution lines", () => {
  const result = analyzeSnippet({
    filename: "diagnose.js", language: "javascript",
    code: ["const command = req.query.command;", "exec(command, (error, stdout) => stdout);"].join("\n")
  });
  assert.equal(result.findings.length, 1);
  assert.equal(result.findings[0].ruleId, "CMD_INJECTION");
  assert.equal(result.findings[0].line, 2);
});

test("does not report a fixed command with separate arguments", () => {
  const result = analyzeSnippet({
    filename: "diagnose.js", language: "javascript",
    code: ["const target = req.query.target;", "spawn('ping', ['-c', '1', target]);"].join("\n")
  });
  assert.deepEqual(result.findings, []);
});

test("does not claim a finding for ordinary code", () => {
  const result = analyzeSnippet({
    filename: "math.js",
    language: "javascript",
    code: "export const add = (left, right) => left + right;"
  });

  assert.deepEqual(result.findings, []);
});

test("rejects empty input", () => {
  assert.throws(() => analyzeSnippet({ code: "" }), /code is required/);
});

test("reports SQL injection", () => {
  const result = analyzeSnippet({
    filename: "users.js",
    language: "javascript",
    code: 'db.query("SELECT * FROM users WHERE id=" + req.query.id);'
  });

  assert.equal(result.findings[0].ruleId, "SQL_INJECTION");
  assert.equal(result.findings[0].severity, "high");
});

test("reports SQL injection across assignment and query lines", () => {
  const result = analyzeSnippet({
    filename: "users.js",
    language: "javascript",
    code: [
      "const username = req.query.username;",
      `const sql = "SELECT * FROM users WHERE username = '" + username + "'";`,
      "db.query(sql, (error, rows) => rows);"
    ].join("\n")
  });

  assert.equal(result.findings.length, 1);
  assert.equal(result.findings[0].ruleId, "SQL_INJECTION");
  assert.equal(result.findings[0].line, 2);
  assert.match(result.findings[0].evidence, /SELECT \* FROM users/);
});

test("does not report a parameterized SQL query", () => {
  const result = analyzeSnippet({
    filename: "users.js",
    language: "javascript",
    code: [
      "const username = req.query.username;",
      `const sql = "SELECT * FROM users WHERE username = ?";`,
      "db.query(sql, [username], (error, rows) => rows);"
    ].join("\n")
  });

  assert.deepEqual(result.findings, []);
});

test("reports path traversal", () => {
  const result = analyzeSnippet({
    filename: "download.js",
    language: "javascript",
    code: "readFile(req.query.filename);"
  });

  assert.equal(result.findings[0].ruleId, "PATH_TRAVERSAL");
});

test("reports hardcoded secrets", () => {
  const result = analyzeSnippet({
    filename: "config.js",
    language: "javascript",
    code: 'const apiKey = "demo-secret-value";'
  });

  assert.equal(result.findings[0].ruleId, "HARDCODED_SECRET");
});

test("reports weak hashes", () => {
  const result = analyzeSnippet({
    filename: "password.js",
    language: "javascript",
    code: "const digest = md5(password);"
  });

  assert.equal(result.findings[0].ruleId, "WEAK_HASH");
  assert.equal(result.findings[0].severity, "medium");
});

test("rejects oversized input", () => {
  assert.throws(() => analyzeSnippet({ code: "a".repeat(200_001) }), /200000 character limit/);
});

test("truncates evidence without losing the finding", () => {
  const result = analyzeSnippet({
    filename: "route.js",
    language: "javascript",
    code: `exec(req.query.command); // ${"x".repeat(220)}`
  });

  assert.equal(result.findings.length, 1);
  assert.equal(result.findings[0].evidence.length, 180);
  assert.match(result.findings[0].evidence, /\.\.\.$/);
});

test("returns a deterministic evidence digest for tool provenance", () => {
  const input = {filename:"route.js", language:"javascript", code:"exec(req.query.command);"};
  const first = analyzeSnippet(input);
  const second = analyzeSnippet(input);
  assert.match(first.evidenceDigest, /^[a-f0-9]{64}$/);
  assert.equal(first.evidenceDigest, second.evidenceDigest);
});

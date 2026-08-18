const RULES = [
  {
    id: "CMD_INJECTION",
    severity: "critical",
    title: "Possible command injection",
    pattern: /\b(exec|execSync|system|popen|shell_exec)\s*\([^\n]*(req\.|request\.|params|query|body|argv|input|user)/i,
    reason: "Untrusted input appears to be passed into a shell or command execution API.",
    remediation: "Avoid a shell; use an argument-array API and validate input against a strict allowlist."
  },
  {
    id: "SQL_INJECTION",
    severity: "high",
    title: "Possible SQL injection",
    pattern: /\b(query|execute|raw)\s*\([^\n]*(\+|\$\{|%s|format\()[^\n]*(req\.|request\.|params|query|body|input|user)/i,
    reason: "User-controlled input appears to be concatenated into a database query.",
    remediation: "Use parameterized queries or prepared statements and validate identifiers separately."
  },
  {
    id: "PATH_TRAVERSAL",
    severity: "high",
    title: "Possible path traversal",
    pattern: /\b(readFile|readFileSync|writeFile|createReadStream|open)\s*\([^\n]*(req\.|request\.|params|query|body|input|filename|path)/i,
    reason: "An externally influenced path appears to reach a filesystem API without containment checks.",
    remediation: "Resolve against a fixed base directory and reject paths that escape it."
  },
  {
    id: "HARDCODED_SECRET",
    severity: "high",
    title: "Possible hardcoded credential",
    pattern: /\b(api[_-]?key|secret|token|password)\b\s*[:=]\s*["'][^"']{8,}["']/i,
    reason: "A credential-like value is embedded directly in source code.",
    remediation: "Load credentials from a secret manager or runtime environment and rotate exposed values."
  },
  {
    id: "WEAK_HASH",
    severity: "medium",
    title: "Weak cryptographic hash",
    pattern: /\b(md5|sha1)\s*\(/i,
    reason: "MD5 or SHA-1 is unsuitable for password storage or collision-resistant security decisions.",
    remediation: "Use Argon2id, scrypt, or bcrypt for passwords; use SHA-256 or stronger where appropriate."
  }
];

function evidenceFor(line) {
  const trimmed = line.trim();
  return trimmed.length > 180 ? `${trimmed.slice(0, 177)}...` : trimmed;
}

function findMultilineSqlInjection(lines) {
  const taintedVariables = new Set();
  const unsafeSqlVariables = new Map();

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const taintedAssignment = line.match(
      /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:req|request)\.(?:query|body|params)\b/i
    );
    if (taintedAssignment) {
      taintedVariables.add(taintedAssignment[1]);
    }

    const sqlAssignment = line.match(
      /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(.+)/
    );
    if (sqlAssignment && /\b(?:select|insert|update|delete)\b/i.test(sqlAssignment[2])) {
      const source = sqlAssignment[2];
      for (const variable of taintedVariables) {
        const variablePattern = new RegExp(`\\b${variable.replace(/[$]/g, "\\$")}\\b`);
        if ((source.includes("+") || source.includes("${")) && variablePattern.test(source)) {
          unsafeSqlVariables.set(sqlAssignment[1], {
            line: index + 1,
            evidence: evidenceFor(line)
          });
        }
      }
    }
  }

  for (const line of lines) {
    const queryCall = line.match(/\b(?:query|execute|raw)\s*\(\s*([A-Za-z_$][\w$]*)\b/i);
    if (queryCall && unsafeSqlVariables.has(queryCall[1])) {
      const source = unsafeSqlVariables.get(queryCall[1]);
      return {
        ruleId: "SQL_INJECTION",
        severity: "high",
        line: source.line,
        title: "Possible SQL injection",
        evidence: source.evidence,
        reason: "User-controlled input appears to be concatenated into a database query.",
        remediation: "Use parameterized queries or prepared statements and validate identifiers separately."
      };
    }
  }

  return null;
}

function findMultilineCommandInjection(lines) {
  const taintedVariables = new Set();
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const assignment = line.match(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:req|request)\.(?:query|body|params)\b/i);
    if (assignment) taintedVariables.add(assignment[1]);
    const call = line.match(/\b(?:exec|execSync|system|popen|shell_exec)\s*\(\s*([A-Za-z_$][\w$]*)\b/i);
    if (call && taintedVariables.has(call[1])) {
      return {
        ruleId: "CMD_INJECTION", severity: "critical", line: index + 1,
        title: "Possible command injection", evidence: evidenceFor(line),
        reason: "Untrusted input appears to be passed into a shell or command execution API.",
        remediation: "Avoid a shell; use an argument-array API and validate input against a strict allowlist."
      };
    }
  }
  return null;
}

export function analyzeSnippet({ filename = "snippet", language = "unknown", code = "" }) {
  if (typeof code !== "string" || code.trim() === "") {
    throw new Error("code is required");
  }
  if (code.length > 200_000) {
    throw new Error("code exceeds the 200000 character limit");
  }

  const lines = code.split(/\r?\n/);
  const findings = [];
  for (let index = 0; index < lines.length; index += 1) {
    for (const rule of RULES) {
      if (rule.pattern.test(lines[index])) {
        findings.push({
          ruleId: rule.id,
          severity: rule.severity,
          line: index + 1,
          title: rule.title,
          evidence: evidenceFor(lines[index]),
          reason: rule.reason,
          remediation: rule.remediation
        });
      }
    }
  }

  if (!findings.some((finding) => finding.ruleId === "SQL_INJECTION")) {
    const multilineSqlFinding = findMultilineSqlInjection(lines);
    if (multilineSqlFinding) {
      findings.push(multilineSqlFinding);
    }
  }
  if (!findings.some((finding) => finding.ruleId === "CMD_INJECTION")) {
    const finding = findMultilineCommandInjection(lines);
    if (finding) findings.push(finding);
  }

  const evidencePayload = {
    filename,
    language,
    scannedLines: lines.length,
    findings: findings.map(({ ruleId, line, evidence }) => ({ ruleId, line, evidence }))
      .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
  };

  return {
    filename,
    language,
    scannedLines: lines.length,
    findings,
    evidenceDigest: createHash("sha256").update(JSON.stringify(evidencePayload)).digest("hex"),
    disclaimer: "Deterministic first-pass checks only; validate data flow and exploitability before remediation."
  };
}
import { createHash } from "node:crypto";

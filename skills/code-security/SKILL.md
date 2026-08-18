---
name: code-security
description: Analyze a source code snippet through the authorized OctoBus CodeSecurityService and use only its returned findings as scanner evidence.
---

# Code Security

When the user asks for a code security review, call the bundled helper exactly once:

Use the `codeBase64` value supplied by the audit request. Copy it byte-for-byte and call:

```bash
python3 scripts/analyze.py --filename <name> --language <language> --code-base64 <codeBase64>
```

Do not reconstruct the source text in the shell and do not use `--code` when `codeBase64` is present. This preserves
newlines and quotes exactly so OctoBus line numbers and evidence remain tied to the submitted code.

The helper handles capability authentication, gRPC routing, and same-input deduplication. Do not write your
own `grpcurl` command and do not print capability tokens. Treat its JSON output
as the scanner evidence. If it fails, report the failure and do not invent a
scanner result. If it succeeds, report file, line, severity, rule ID, evidence,
reason, impact, and remediation, then immediately return the final answer without
running more commands. Unless the user explicitly requests another language, the
entire final report must be written in Simplified Chinese, including headings and
field labels. The scanner findings section must contain only findings present in
the JSON response. Put any additional reasoning in a separate section labeled
“待人工复核” and state that it is not a scanner conclusion. Never change a returned
rule ID or line number, never replace it with a custom identifier such as SEC-001,
and never invent an additional scanner finding. State that deterministic checks
are not a complete SAST proof.

For requests carrying an audit request ID or an output JSON Schema, preserve the request ID and filename exactly.
Still call the helper exactly once. Populate every `findings` item only from the helper response. Translate the
tool-provided reason and remediation faithfully, add impact analysis based on that same finding, and place any
non-tool observation only in `manualReview`. Copy the tool's `evidenceDigest` exactly into
`toolEvidence.evidenceDigest`; set the other `toolEvidence` fields exactly as requested. Never calculate, replace,
or invent this digest. Output only the requested JSON object with no Markdown wrapper.

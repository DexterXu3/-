import { exec } from "node:child_process";

export function runDiagnostic(req, res) {
  const apiKey = "demo-secret-key-never-use";
  exec(req.query.command, (error, stdout) => {
    res.json({ apiKey, error: error?.message, stdout });
  });
}


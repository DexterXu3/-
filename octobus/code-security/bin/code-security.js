#!/usr/bin/env node

import { defineService, runServiceMain } from "@chaitin-ai/octobus-sdk";
import { analyzeSnippet } from "../lib/analyzer.js";

const service = defineService({
  handlers: {
    "codesecurity.v1.CodeSecurityService/AnalyzeSnippet": (ctx) => analyzeSnippet(ctx.request)
  }
});

runServiceMain(service);


const $ = (selector) => document.querySelector(selector);
const codeInput = $("#code");
const filenameInput = $("#filename");
const languageInput = $("#language");
const auditButton = $("#audit-button");
const fileInput = $("#file-input");
const states = { empty: $("#empty-state"), loading: $("#loading-state"), error: $("#error-state"), results: $("#results") };
const severityNames = { critical: "严重", high: "高", medium: "中", low: "低" };
const extensionLanguages = {js:"javascript", mjs:"javascript", cjs:"javascript", ts:"typescript"};
let loadingTimers = [];

function setState(name, message="") { Object.entries(states).forEach(([key,node]) => { node.hidden = key !== name; }); if (name === "error") states.error.textContent = message; }
function clearLoadingTimers(){ loadingTimers.forEach(clearTimeout); loadingTimers=[]; }
function setLoadingStep(index,title,detail){ document.querySelectorAll(".loading-steps li").forEach((node,i)=>{node.classList.toggle("active",i===index);node.classList.toggle("done",i<index);}); $("#loading-title").textContent=title; $("#loading-detail").textContent=detail; }
function startLoading(){ clearLoadingTimers(); setLoadingStep(0,"正在建立 Agent 审计请求","校验文件信息和代码长度"); loadingTimers.push(setTimeout(()=>setLoadingStep(1,"Agent 正在调用 Skill 与 OctoBus","获取规则、行号和代码证据"),450)); loadingTimers.push(setTimeout(()=>setLoadingStep(2,"Qwen 正在生成结构化报告","基于扫描证据整理影响和修复建议"),1100)); }
function updateCounts(){ const text=codeInput.value; $("#char-count").textContent=`${text.length.toLocaleString()} / 200,000 字符`; $("#line-count").textContent=`${text ? text.split(/\r?\n/).length : 1} 行`; }
function element(tag, className, text){ const node=document.createElement(tag); if(className)node.className=className; if(text!==undefined)node.textContent=text; return node; }
function field(grid,label,value,className=""){ grid.append(element("dt","",label)); const dd=element("dd",className,value); grid.append(dd); }
function renderResults(result){
  clearLoadingTimers(); setState("results"); const root=states.results; root.replaceChildren(); const findings=Array.isArray(result.findings)?result.findings:[];
  const summary=element("div","summary"); summary.append(element("strong","",findings.length?`发现 ${findings.length} 项风险`:"未发现明确风险"),element("span","",`Agent Run ${result.runId||"—"} · 扫描 ${result.scannedLines||0} 行 · ${result.filename||filenameInput.value}`)); root.append(summary);
  findings.forEach(finding=>{ const card=element("article",`finding ${finding.severity||""}`); const head=element("div","finding-head"); head.append(element("h3","",finding.ruleId||"UNKNOWN"),element("span","badge",severityNames[finding.severity]||finding.severity||"未知")); card.append(head); const grid=element("dl","finding-grid"); field(grid,"位置",`${result.filename}:${finding.line}`); field(grid,"代码证据",finding.evidence||"—","evidence"); field(grid,"原因",finding.reason||"需人工复核"); field(grid,"影响",finding.impact||"需结合业务上下文评估"); field(grid,"修复建议",finding.remediation||"需人工复核"); card.append(grid); root.append(card); });
  if(Array.isArray(result.manualReview)&&result.manualReview.length){const review=element("article","finding medium");review.append(element("h3","","待人工复核"));result.manualReview.forEach(item=>review.append(element("p","",item)));root.append(review);}
  root.hidden=false;
}

fileInput.addEventListener("change",async()=>{ const file=fileInput.files[0]; if(!file)return; if(file.size>1_000_000){setState("error","文件过大，请选择不超过 1 MB 的代码文件。");return;} filenameInput.value=file.name; const extension=file.name.split(".").pop().toLowerCase(); languageInput.value=extensionLanguages[extension]||"unknown"; codeInput.value=await file.text(); updateCounts(); setState("empty"); });
codeInput.addEventListener("input",updateCounts);
auditButton.addEventListener("click",async()=>{ const code=codeInput.value; if(!filenameInput.value.trim()){setState("error","请输入文件名。");return;} if(!code.trim()){setState("error","请粘贴或上传需要审计的代码。");return;} if(code.length>200000){setState("error","代码超过 200,000 字符限制。");return;} auditButton.disabled=true; $("#result-status").textContent="扫描中"; $("#result-status").className="result-status"; setState("loading"); startLoading(); try{ const request=fetch("/api/audit",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({filename:filenameInput.value.trim(),language:languageInput.value,code})}); const [response]=await Promise.all([request,new Promise(resolve=>setTimeout(resolve,1350))]); const result=await response.json(); if(!response.ok)throw new Error(result.error||"审计请求失败。"); renderResults(result); $("#result-status").textContent="扫描完成"; $("#result-status").className="result-status done"; }catch(error){clearLoadingTimers();setState("error",error.message); $("#result-status").textContent="扫描失败"; $("#result-status").className="result-status failed";}finally{auditButton.disabled=false;} });
updateCounts();

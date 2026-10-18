let currentPhase = "install";
let currentView = "graph";
let gZoom = 1;
let isPanning = false, panStart = {x:0,y:0}, vbStart = {x:0,y:0};
function countDeps(nodes) {
  let c = 0;
  (nodes||[]).forEach(n => { if (n.type==="pkg_dep") c++; if (n.children) c += countDeps(n.children); });
  return c;
}
function countConds(nodes) {
  let c = 0;
  (nodes||[]).forEach(n => { if (n.type==="use_cond") c++; if (n.children) c += countConds(n.children); });
  return c;
}
function countCandidates(nodes) {
  let c = 0;
  (nodes||[]).forEach(n => { if (n.candidates) c += n.candidates.length; if (n.children) c += countCandidates(n.children); });
  return c;
}
function countChildren(node) {
  if (node.type==="pkg_dep") return 0;
  return (node.children||[]).length;
}
function renderTree() {
  const data = depData[currentPhase] || [];
  const el = document.getElementById("tree-container");
  el.replaceChildren();
  if (!data.length) {
    const empty = currentPhase === "both"
      ? "No dependencies declared in both install and run."
      : "No dependencies for this phase.";
    const note = document.createElement("div");
    note.className = "tree-empty";
    note.textContent = empty;
    el.appendChild(note);
    updateSubtitle(); return;
  }
  el.appendChild(buildTreeDOM(data));
  updateSubtitle();
}
function updateSubtitle() {
  const data = depData[currentPhase] || [];
  const d = countDeps(data), c = countConds(data), k = countCandidates(data);
  document.getElementById("subtitle").textContent =
    d + " dependencies \u00b7 " + c + " use conditionals \u00b7 " + k + " candidates";
}
function textEl(tag, className, text) {
  const el = document.createElement(tag);
  if (className) el.className = className;
  el.textContent = text;
  return el;
}
function encodedEntryHref(id) {
  if (typeof id !== "string" || /[\u0000-\u001f\u007f\\]/.test(id)) return null;
  const parts = id.split("/");
  if (parts.length !== 2 || parts.some(p => !p || p === "." || p === "..")) return null;
  return "../" + parts.map(encodeURIComponent).join("/") + "-detail.html";
}
function buildTreeDOM(nodes) {
  const fragment = document.createDocumentFragment();
  (nodes||[]).forEach(node => {
    const wrapper = document.createElement("div");
    wrapper.className = "tree-node";
    if (node.type === "use_cond") {
      const cls = node.cond === "positive" ? "badge-use-pos" : "badge-use-neg";
      const sign = node.cond === "positive" ? "+" : "-";
      const n = countChildren(node);
      const row = document.createElement("div");
      row.className = "group-row";
      row.addEventListener("click", () => toggleGroup(row));
      row.append(textEl("span", "toggle-icon", "\u25be"));
      row.append(textEl("span", "type-badge " + cls, sign + String(node.flag)));
      row.append(textEl("span", "group-label", "use_conditional"));
      row.append(textEl("span", "group-count", n + " dep" + (n!==1?"s":"")));
      const children = document.createElement("div");
      children.className = "tree-children";
      children.appendChild(buildTreeDOM(node.children));
      wrapper.append(row, children);
    } else if (["any_of","all_of","exactly_one_of","at_most_one_of"].indexOf(node.type) >= 0) {
      const info = {any_of:["any of","badge-any-of","at least one required"],
                    all_of:["all of","badge-all-of","all required"],
                    exactly_one_of:["exactly one of","badge-exactly-one","exactly one required"],
                    at_most_one_of:["at most one of","badge-at-most-one","at most one required"]};
      const [label, cls, desc] = info[node.type];
      const n = (node.children||[]).length;
      const row = document.createElement("div");
      row.className = "group-row";
      row.addEventListener("click", () => toggleGroup(row));
      row.append(textEl("span", "toggle-icon", "\u25be"));
      row.append(textEl("span", "type-badge " + cls, label));
      row.append(textEl("span", "group-label", desc));
      row.append(textEl("span", "group-count", n + " option" + (n!==1?"s":"")));
      const children = document.createElement("div");
      children.className = "tree-children";
      children.appendChild(buildTreeDOM(node.children));
      wrapper.append(row, children);
    } else if (node.type === "pkg_dep") {
      const nc = (node.candidates||[]).length;
      const firstId = nc > 0 ? node.candidates[0].id : "";
      const row = document.createElement("div");
      row.className = "pkg-row";
      row.append(textEl("span", "pkg-connector", ""));
      row.append(textEl("span", "pkg-cat", String(node.cat) + "/"));
      const nameSpan = textEl("span", "pkg-name", "");
      const firstHref = encodedEntryHref(firstId);
      if (firstHref) {
        const link = textEl("a", "", String(node.name));
        link.setAttribute("href", firstHref);
        nameSpan.appendChild(link);
      } else {
        nameSpan.textContent = String(node.name);
      }
      row.append(nameSpan);
      row.append(textEl("span", "pkg-constraint", String(node.constraint)));
      if (node.strength !== "no") {
        const strength = ["weak", "strong"].includes(node.strength) ? node.strength : "weak";
        row.append(textEl("span", "pkg-blocker " + strength, strength + " blocker"));
      }
      const toggle = textEl("span", "candidates-toggle", nc + " candidate" + (nc!==1?"s":"") + " ");
      toggle.append(textEl("span", "arrow", "\u25be"));
      toggle.addEventListener("click", () => toggleCandidates(toggle));
      row.append(toggle);
      const list = document.createElement("div");
      list.className = "candidates-list open";
      (node.candidates||[]).forEach(c => {
        const item = document.createElement("div");
        item.className = "candidate-item";
        const href = encodedEntryHref(c.id);
        if (href) {
          const link = textEl("a", "", String(c.id));
          link.setAttribute("href", href);
          item.appendChild(link);
        } else {
          item.appendChild(document.createTextNode(String(c.id)));
        }
        if (c.inst) item.append(" ", textEl("span", "candidate-installed", "installed"));
        list.appendChild(item);
      });
      wrapper.append(row, list);
    }
    fragment.appendChild(wrapper);
  });
  return fragment;
}
function toggleGroup(row) {
  const icon = row.querySelector(".toggle-icon");
  const ch = row.parentElement.querySelector(".tree-children");
  if (!ch) return;
  if (ch.style.display === "none") { ch.style.display = "block"; icon.classList.remove("collapsed"); }
  else { ch.style.display = "none"; icon.classList.add("collapsed"); }
}
function toggleCandidates(el) {
  const list = el.parentElement.nextElementSibling;
  if (!list || !list.classList.contains("candidates-list")) return;
  list.classList.toggle("open");
  const arrow = el.querySelector(".arrow");
  arrow.textContent = list.classList.contains("open") ? "\u25be" : "\u25b8";
}
function expandAll() {
  document.querySelectorAll(".tree-children").forEach(c => c.style.display = "block");
  document.querySelectorAll(".toggle-icon").forEach(i => i.classList.remove("collapsed"));
}
function collapseAll() {
  document.querySelectorAll(".tree-children").forEach(c => c.style.display = "none");
  document.querySelectorAll(".toggle-icon").forEach(i => i.classList.add("collapsed"));
}
function expandCandidates() {
  document.querySelectorAll(".candidates-list").forEach(c => c.classList.add("open"));
  document.querySelectorAll(".candidates-toggle .arrow").forEach(a => a.textContent = "\u25be");
}
function collapseCandidates() {
  document.querySelectorAll(".candidates-list").forEach(c => c.classList.remove("open"));
  document.querySelectorAll(".candidates-toggle .arrow").forEach(a => a.textContent = "\u25b8");
}
const CARD_W = 160, CARD_H = 36, LAYER_X = 210, GAP_Y = 10;
const nodeColors = {
  ebuild:         {fill:"var(--blue-bg)",   stroke:"var(--accent)",  text:"var(--accent)"},
  use_cond_pos:   {fill:"var(--green-bg)",  stroke:"var(--green)",   text:"var(--green)"},
  use_cond_neg:   {fill:"var(--red-bg)",    stroke:"var(--red)",     text:"var(--red)"},
  any_of:         {fill:"var(--orange-bg)", stroke:"var(--orange)",  text:"var(--orange)"},
  all_of:         {fill:"var(--blue-bg)",   stroke:"var(--blue)",    text:"var(--blue)"},
  exactly_one_of: {fill:"var(--purple-bg)", stroke:"var(--purple)",  text:"var(--purple)"},
  at_most_one_of: {fill:"var(--gray-bg)",   stroke:"var(--gray-c)",  text:"var(--gray-c)"},
  pkg_dep:        {fill:"var(--node-bg)",   stroke:"var(--node-border)", text:"var(--text)"},
  blocker_weak:   {fill:"var(--orange-bg)", stroke:"var(--orange)",  text:"var(--orange)"},
  blocker_strong: {fill:"var(--red-bg)",    stroke:"var(--red)",     text:"var(--red)"},
  candidate:      {fill:"var(--surface2)",  stroke:"var(--border2)", text:"var(--text2)"},
  candidate_inst: {fill:"var(--green-bg)",  stroke:"var(--green-border)", text:"var(--green)"}
};
function flattenTree(nodes, parentId, depth) {
  const flat = [], edges = [];
  (nodes||[]).forEach((node, i) => {
    const id = parentId + "_" + i;
    let nodeType = node.type;
    let label1 = "", label2 = "";
    let edgeStyle = "solid";
    if (node.type === "use_cond") {
      nodeType = node.cond === "positive" ? "use_cond_pos" : "use_cond_neg";
      label1 = (node.cond === "positive" ? "+" : "-") + node.flag;
      label2 = "use_conditional";
      edgeStyle = "dashed";
    } else if (node.type === "pkg_dep") {
      if (node.strength === "weak") nodeType = "blocker_weak";
      else if (node.strength === "strong") nodeType = "blocker_strong";
      label1 = node.cat + "/" + node.name;
      label2 = node.constraint;
    } else {
      label1 = node.type.replace(/_/g, " ");
      edgeStyle = node.type === "all_of" ? "solid" : "dotted";
    }
    flat.push({id, nodeType, label1, label2, depth});
    if (parentId !== "root") edges.push({from: parentId, to: id, style: edgeStyle});
    else edges.push({from: "root", to: id, style: "solid"});
    if (node.candidates && node.candidates.length) {
      node.candidates.forEach((c, ci) => {
        const cid = id + "_c" + ci;
        const cType = c.inst ? "candidate_inst" : "candidate";
        const parts = c.id.split("/");
        const cLabel = parts.length > 1 ? parts[1] : c.id;
        flat.push({id: cid, nodeType: cType, label1: cLabel, label2: c.inst ? "installed" : "", depth: depth + 1});
        edges.push({from: id, to: cid, style: "dotted"});
      });
    }
    if (node.children) {
      const sub = flattenTree(node.children, id, depth + 1);
      flat.push(...sub.flat); edges.push(...sub.edges);
    }
  });
  return {flat, edges};
}
function renderGraph() {
  const data = depData[currentPhase] || [];
  const svg = document.getElementById("graph-svg");
  if (!data.length) { svg.replaceChildren(); return; }
  const {flat, edges} = flattenTree(data, "root", 1);
  flat.unshift({id:"root", nodeType:"ebuild", label1:rootLabel, label2:"ebuild", depth:0});
  const positions = layoutGraph(flat, edges);
  const ns = "http://www.w3.org/2000/svg";
  const graph = document.createElementNS(ns, "g");
  graph.setAttribute("id", "graph-g");
  const makeSvg = (name, attrs, text) => {
    const el = document.createElementNS(ns, name);
    Object.entries(attrs || {}).forEach(([key, value]) => el.setAttribute(key, String(value)));
    if (text !== undefined) el.textContent = String(text);
    return el;
  };
  edges.forEach(e => {
    const fp = positions[e.from], tp = positions[e.to];
    if (!fp || !tp) return;
    const x1 = fp.x + CARD_W, y1 = fp.y + CARD_H / 2;
    const x2 = tp.x, y2 = tp.y + CARD_H / 2;
    const mx = (x1 + x2) / 2;
    let dash = "";
    if (e.style === "dashed") dash = "6,3";
    if (e.style === "dotted") dash = "2,4";
    const path = makeSvg("path", {
      d: `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`,
      fill: "none", stroke: "var(--edge-color)",
      "stroke-width": "1.3", opacity: "0.5"
    });
    if (dash) path.setAttribute("stroke-dasharray", dash);
    graph.appendChild(path);
    const aS = 4;
    graph.appendChild(makeSvg("polygon", {
      points: `${x2},${y2} ${x2-aS*1.5},${y2-aS} ${x2-aS*1.5},${y2+aS}`,
      fill: "var(--edge-color)", opacity: "0.5"
    }));
  });
  flat.forEach(n => {
    const pos = positions[n.id];
    if (!pos) return;
    const c = nodeColors[n.nodeType] || nodeColors.pkg_dep;
    const group = makeSvg("g");
    group.appendChild(makeSvg("rect", {
      x: pos.x, y: pos.y, width: CARD_W, height: CARD_H,
      rx: 5, fill: c.fill, stroke: c.stroke, "stroke-width": "1.5"
    }));
    group.appendChild(makeSvg("text", {
      x: pos.x + CARD_W/2, y: pos.y + 14,
      "text-anchor": "middle", "font-size": "11",
      "font-weight": "600", fill: c.text
    }, n.label1));
    if (n.label2) {
      group.appendChild(makeSvg("text", {
        x: pos.x + CARD_W/2, y: pos.y + 27,
        "text-anchor": "middle", "font-size": "10", fill: "var(--text2)"
      }, n.label2));
    }
    graph.appendChild(group);
  });
  let maxX = 0, maxY = 0;
  flat.forEach(n => { const p = positions[n.id]; if (p) { if (p.x+CARD_W > maxX) maxX = p.x+CARD_W; if (p.y+CARD_H > maxY) maxY = p.y+CARD_H; }});
  const pad = 40;
  svg.setAttribute("viewBox", (-pad) + " " + (-pad) + " " + (maxX+pad*2) + " " + (maxY+pad*2));
  svg.replaceChildren(graph);
}
function layoutGraph(nodes, edges) {
  const layers = {};
  nodes.forEach(n => { if (!layers[n.depth]) layers[n.depth] = []; layers[n.depth].push(n); });
  const childMap = {};
  nodes.forEach(n => childMap[n.id] = []);
  edges.forEach(e => { if (childMap[e.from]) childMap[e.from].push(e.to); });
  const positions = {};
  const maxDepth = Math.max(0, ...Object.keys(layers).map(Number));
  for (let d = 0; d <= maxDepth; d++) {
    const ids = layers[d] || [];
    ids.forEach((n, i) => {
      positions[n.id] = {x: d * LAYER_X + 20, y: i * (CARD_H + GAP_Y) + 20};
    });
  }
  for (let pass = 0; pass < 4; pass++) {
    for (let d = maxDepth; d >= 0; d--) {
      const ids = (layers[d]||[]);
      ids.forEach(n => {
        const ch = (childMap[n.id]||[]).filter(c => positions[c]);
        if (ch.length > 0) {
          positions[n.id].y = ch.reduce((s,c) => s + positions[c].y, 0) / ch.length;
        }
      });
      spreadLayerY(ids.map(n => n.id), positions);
    }
    for (let d = 0; d <= maxDepth; d++) {
      const ids = (layers[d]||[]);
      ids.forEach(n => {
        const ch = (childMap[n.id]||[]).filter(c => positions[c]);
        if (ch.length > 0) {
          positions[n.id].y = ch.reduce((s,c) => s + positions[c].y, 0) / ch.length;
        }
      });
      spreadLayerY(ids.map(n => n.id), positions);
    }
  }
  return positions;
}
function spreadLayerY(ids, positions) {
  if (!ids || ids.length <= 1) return;
  for (let i = 1; i < ids.length; i++) {
    const prev = positions[ids[i-1]], curr = positions[ids[i]];
    if (!prev || !curr) continue;
    const minY = prev.y + CARD_H + GAP_Y;
    if (curr.y < minY) curr.y = minY;
  }
}
(function() {
  const container = document.getElementById("graph-container");
  const svg = document.getElementById("graph-svg");
  let vbX=0,vbY=0,vbW=0,vbH=0,lastDx=0,lastDy=0,ctmA=1,ctmD=1;
  function syncVB(){const v=svg.getAttribute("viewBox");if(!v)return false;const p=v.split(" ");vbX=+p[0];vbY=+p[1];vbW=+p[2];vbH=+p[3];return true;}
  function applyVB(){svg.setAttribute("viewBox",vbX+" "+vbY+" "+vbW+" "+vbH);}
  function endPan(){
    if(!isPanning)return;isPanning=false;container.style.cursor="";
    vbX=vbStart.x-lastDx/ctmA;vbY=vbStart.y-lastDy/ctmD;applyVB();
    svg.style.transform="";svg.style.willChange="";
    lastDx=0;lastDy=0;
  }
  container.addEventListener("mousedown", e => {
    if (e.target.closest("g")) return;
    if (!syncVB()) return;
    isPanning = true; lastDx = 0; lastDy = 0;
    panStart = {x: e.clientX, y: e.clientY};
    vbStart = {x: vbX, y: vbY};
    const ctm = svg.getScreenCTM();
    if (ctm) { ctmA = ctm.a; ctmD = ctm.d; }
    svg.style.willChange = "transform";
    container.style.cursor = "grabbing";
  });
  container.addEventListener("mousemove", e => {
    if (!isPanning) return;
    lastDx = e.clientX - panStart.x;
    lastDy = e.clientY - panStart.y;
    svg.style.transform = "translate(" + lastDx + "px," + lastDy + "px)";
  });
  container.addEventListener("mouseup", endPan);
  container.addEventListener("mouseleave", endPan);
  container.addEventListener("wheel", e => {
    e.preventDefault();
    if (!syncVB()) return;
    const factor = e.deltaY > 0 ? 0.9 : 1.1;
    gZoom *= factor; gZoom = Math.max(0.25, Math.min(4, gZoom));
    const rect = container.getBoundingClientRect();
    const mx = (e.clientX - rect.left) / rect.width;
    const my = (e.clientY - rect.top) / rect.height;
    const nw = vbW / factor, nh = vbH / factor;
    vbX += (vbW - nw) * mx;
    vbY += (vbH - nh) * my;
    vbW = nw; vbH = nh;
    applyVB();
    document.getElementById("zoom-level").textContent = Math.round(gZoom * 100) + "%";
  }, {passive: false});
})();
function switchPhase(phase, btn) {
  currentPhase = phase;
  document.querySelectorAll(".phase-tab").forEach(t => t.classList.remove("active"));
  if (btn) btn.classList.add("active");
  if (currentView === "tree") renderTree(); else renderGraph();
}
function switchView(view, btn) {
  currentView = view;
  document.querySelectorAll(".view-btn").forEach(b => b.classList.remove("active"));
  if (btn) btn.classList.add("active");
  const treeEl = document.getElementById("tree-container");
  const toolbar = document.getElementById("tree-toolbar");
  const graphEl = document.getElementById("graph-container");
  if (view === "tree") {
    treeEl.style.display = "block"; toolbar.style.display = "flex"; graphEl.style.display = "none";
    renderTree();
  } else {
    treeEl.style.display = "none"; toolbar.style.display = "none"; graphEl.style.display = "block";
    renderGraph();
  }
}
function zoomIn() {
  gZoom = Math.min(gZoom * 1.25, 4);
  applyZoom();
}
function zoomOut() {
  gZoom = Math.max(gZoom / 1.25, 0.25);
  applyZoom();
}
function applyZoom() {
  const svg = document.getElementById("graph-svg");
  const vb = svg.getAttribute("viewBox");
  if (!vb) return;
  const parts = vb.split(" ").map(Number);
  const cx = parts[0] + parts[2] / 2, cy = parts[1] + parts[3] / 2;
  const nw = parts[2] / gZoom, nh = parts[3] / gZoom;
  svg.setAttribute("viewBox", (cx - nw/2) + " " + (cy - nh/2) + " " + nw + " " + nh);
  document.getElementById("zoom-level").textContent = Math.round(gZoom * 100) + "%";
}
function resetView() {
  gZoom = 1;
  document.getElementById("zoom-level").textContent = "100%";
  renderGraph();
}
(function() {
  ["install","run","both"].forEach(p => {
    const el = document.getElementById("badge-" + p);
    if (el) el.textContent = countDeps(depData[p] || []);
  });
  renderGraph();
})();

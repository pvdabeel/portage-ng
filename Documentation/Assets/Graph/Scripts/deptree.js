let currentType = "rdepend";
let collapsed = new Set();
let viewBox = {x:0, y:0, w:0, h:0};
let zoom = 1;
let isPanning = false, panStart = {x:0,y:0}, vbStart = {x:0,y:0};
let autoCollapsed = false;
const CARD_W = 130, CARD_H = 44, LAYER_H = 90, LAYER_W = 210, MIN_GAP = 16;
const MIN_SCALE = 0.75, MAX_SCALE = 1.5;
const AUTO_COLLAPSE_THRESHOLD = 60;
const svg = document.getElementById("graph-svg");
const container = document.getElementById("graph-container");
const tooltip = document.getElementById("tooltip");
const ns = "http://www.w3.org/2000/svg";
function getTree() { return treeData[currentType]; }
function autoCollapseIfLarge() {
  const tree = getTree();
  if (!tree || tree.nodes.length <= AUTO_COLLAPSE_THRESHOLD) return;
  const childMap = {};
  tree.nodes.forEach(n => childMap[n.id] = []);
  tree.edges.forEach(e => { if (childMap[e.from]) childMap[e.from].push(e.to); });
  const directChildren = new Set(childMap[tree.root]||[]);
  tree.nodes.forEach(n => {
    if ((childMap[n.id]||[]).length > 0 && n.id !== tree.root && !directChildren.has(n.id)) collapsed.add(n.id);
  });
  autoCollapsed = true;
}
autoCollapseIfLarge();
function pickRankdir(layers, maxDepth) {
  let maxLayer = 1;
  Object.values(layers).forEach(ids => { if (ids.length > maxLayer) maxLayer = ids.length; });
  const nLevels = maxDepth + 1;
  const tdW = Math.max(maxLayer * (CARD_W + MIN_GAP) - MIN_GAP, CARD_W);
  const tdH = Math.max(nLevels * LAYER_H, CARD_H);
  const lrW = Math.max(nLevels * LAYER_W, CARD_W);
  const lrH = Math.max(maxLayer * (CARD_H + MIN_GAP) - MIN_GAP, CARD_H);
  const cW = container.clientWidth || tdW, cH = container.clientHeight || tdH;
  const tdScale = Math.min(cW / tdW, cH / tdH, 1);
  const lrScale = Math.min(cW / lrW, cH / lrH, 1);
  return lrScale > tdScale + 0.05 ? "lr" : "tb";
}
function buildLayout() {
  const empty = {positions:{},hiddenSet:new Set(),childMap:{},nodeMap:{},rankdir:"tb",maxDepth:0};
  const tree = getTree();
  if (!tree || !tree.nodes.length) return empty;
  const childMap = {}, nodeMap = {};
  const parentMap = {};
  tree.nodes.forEach(n => { nodeMap[n.id] = n; childMap[n.id] = []; parentMap[n.id] = []; });
  tree.edges.forEach(e => {
    if (childMap[e.from]) childMap[e.from].push(e.to);
    if (parentMap[e.to]) parentMap[e.to].push(e.from);
  });
  const hiddenSet = new Set();
  function markHidden(id) { (childMap[id]||[]).forEach(c => { hiddenSet.add(c); markHidden(c); }); }
  collapsed.forEach(id => markHidden(id));
  const layers = {};
  const visited = new Set();
  function bfs(startId) {
    const queue = [{id: startId, depth: 0}];
    visited.add(startId);
    while (queue.length) {
      const {id, depth} = queue.shift();
      if (!layers[depth]) layers[depth] = [];
      layers[depth].push(id);
      (childMap[id]||[]).forEach(c => {
        if (!visited.has(c) && !hiddenSet.has(c)) { visited.add(c); queue.push({id:c, depth:depth+1}); }
      });
    }
  }
  bfs(tree.root);
  const positions = {};
  const maxDepth = Math.max(0, ...Object.keys(layers).map(Number));
  const rankdir = pickRankdir(layers, maxDepth);
  const axis = rankdir === "lr" ? "y" : "x";
  const size = rankdir === "lr" ? CARD_H : CARD_W;
  const layerSpan = {};
  for (let d = maxDepth; d >= 0; d--) {
    const ids = layers[d] || [];
    layerSpan[d] = ids.length * size + Math.max(0, ids.length - 1) * MIN_GAP;
  }
  const maxSpan = Math.max(...Object.values(layerSpan), size);
  for (let d = maxDepth; d >= 0; d--) {
    const ids = layers[d] || [];
    if (ids.length === 0) continue;
    const total = ids.length * size + Math.max(0, ids.length - 1) * MIN_GAP;
    const start = (maxSpan - total) / 2;
    ids.forEach((id, i) => {
      const along = start + i * (size + MIN_GAP) + size / 2;
      positions[id] = rankdir === "lr"
        ? {x: d * LAYER_W + CARD_W / 2 + 24, y: along}
        : {x: along, y: d * LAYER_H + CARD_H / 2 + 24};
    });
  }
  function barycenter(ids, neighbors) {
    ids.forEach(id => {
      const ns = (neighbors[id]||[]).filter(n => !hiddenSet.has(n) && positions[n]);
      if (ns.length) positions[id][axis] = ns.reduce((s, n) => s + positions[n][axis], 0) / ns.length;
    });
  }
  for (let pass = 0; pass < 4; pass++) {
    for (let d = maxDepth; d >= 0; d--) {
      const ids = layers[d] || [];
      barycenter(ids, childMap);
      packLayer(ids, positions, axis, size);
    }
    for (let d = 0; d <= maxDepth; d++) {
      const ids = layers[d] || [];
      barycenter(ids, parentMap);
      packLayer(ids, positions, axis, size);
    }
  }
  alignLayers(layers, maxDepth, positions, axis, tree.root);
  return {positions, hiddenSet, childMap, nodeMap, rankdir, maxDepth};
}
function packLayer(ids, positions, axis, size) {
  if (!ids || ids.length <= 1) return;
  ids.sort((a, b) => {
    const d = positions[a][axis] - positions[b][axis];
    return d !== 0 ? d : (a < b ? -1 : 1);
  });
  let cursor = positions[ids[0]][axis];
  for (let i = 1; i < ids.length; i++) {
    cursor += size + MIN_GAP;
    positions[ids[i]][axis] = cursor;
  }
}
function alignLayers(layers, maxDepth, positions, axis, rootId) {
  if (!positions[rootId]) return;
  const target = positions[rootId][axis];
  for (let d = 0; d <= maxDepth; d++) {
    const ids = layers[d] || [];
    if (!ids.length) continue;
    let lo = Infinity, hi = -Infinity;
    ids.forEach(id => {
      const v = positions[id][axis];
      if (v < lo) lo = v; if (v > hi) hi = v;
    });
    const shift = target - (lo + hi) / 2;
    if (shift) ids.forEach(id => { positions[id][axis] += shift; });
  }
}
function precomputeDescendants(childMap) {
  const counts = {};
  const memo = {};
  function dfs(id) {
    if (memo[id] !== undefined) return memo[id];
    memo[id] = 0;
    let c = 0;
    (childMap[id]||[]).forEach(ch => { c += 1 + dfs(ch); });
    memo[id] = c;
    return c;
  }
  Object.keys(childMap).forEach(id => { counts[id] = dfs(id); });
  return counts;
}
function fitView(positions) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  Object.values(positions).forEach(p => {
    const x0 = p.x - CARD_W / 2, x1 = p.x + CARD_W / 2;
    const y0 = p.y - CARD_H / 2, y1 = p.y + CARD_H / 2;
    if (x0 < minX) minX = x0; if (x1 > maxX) maxX = x1;
    if (y0 < minY) minY = y0; if (y1 > maxY) maxY = y1;
  });
  if (minX === Infinity) { minX = 0; minY = 0; maxX = 400; maxY = 200; }
  const pad = 36;
  const contentW = Math.max(maxX - minX, CARD_W) + pad * 2;
  const contentH = Math.max(maxY - minY, CARD_H) + pad * 2;
  const cW = container.clientWidth || contentW, cH = container.clientHeight || contentH;
  let scale = Math.min(cW / contentW, cH / contentH);
  if (!isFinite(scale) || scale <= 0) scale = 1;
  scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, scale));
  const viewW = cW / scale, viewH = cH / scale;
  const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  viewBox = {x: cx - viewW / 2, y: cy - viewH / 2, w: viewW, h: viewH};
  zoom = 1;
  svg.setAttribute("viewBox", `${viewBox.x} ${viewBox.y} ${viewBox.w} ${viewBox.h}`);
  const zl = document.getElementById("zoom-level");
  if (zl) zl.textContent = "100%";
}
function render() {
  const tree = getTree();
  if (!tree || !tree.nodes.length) { svg.innerHTML = ""; return; }
  const {positions, hiddenSet, childMap, nodeMap, rankdir} = buildLayout();
  const descCounts = precomputeDescendants(childMap);
  fitView(positions);
  const parts = [];
  parts.push("<defs>");
  ["normal","weak","strong"].forEach(t => {
    const col = t === "weak" ? "var(--edge-weak)" : t === "strong" ? "var(--edge-strong)" : "var(--edge-normal)";
    parts.push(`<marker id="arrow-${t}" markerWidth="7" markerHeight="5" refX="7" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="${col}"/></marker>`);
  });
  parts.push("</defs><g class=\"edge-layer\">");
  tree.edges.forEach(e => {
    if (hiddenSet.has(e.to) || !positions[e.from] || !positions[e.to]) return;
    const fp = positions[e.from], tp = positions[e.to];
    let d;
    if (rankdir === "lr") {
      const x1 = fp.x + CARD_W / 2, y1 = fp.y, x2 = tp.x - CARD_W / 2, y2 = tp.y;
      const mx = (x1 + x2) / 2;
      d = `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`;
    } else {
      const x1 = fp.x, y1 = fp.y + CARD_H / 2, x2 = tp.x, y2 = tp.y - CARD_H / 2;
      const my = (y1 + y2) / 2;
      d = `M${x1},${y1} C${x1},${my} ${x2},${my} ${x2},${y2}`;
    }
    const col = e.type === "weak" ? "var(--edge-weak)" : e.type === "strong" ? "var(--edge-strong)" : "var(--edge-normal)";
    const mt = e.type === "no" ? "normal" : e.type;
    let extra = "";
    if (e.type === "weak") extra = ' stroke-dasharray="5,3"';
    if (e.type === "strong") extra = ' stroke-dasharray="3,2"';
    parts.push(`<path d="${d}" stroke="${col}" stroke-width="1.3" fill="none" marker-end="url(#arrow-${mt})" opacity="0.6"${extra}/>`);
  });
  parts.push("</g><g class=\"node-layer\">");
  tree.nodes.forEach(n => {
    if (hiddenSet.has(n.id) || !positions[n.id]) return;
    const pos = positions[n.id], isRoot = n.id === tree.root;
    const isColl = collapsed.has(n.id);
    const cc = (childMap[n.id]||[]).length;
    const dc = descCounts[n.id]||0;
    const x = pos.x - CARD_W / 2, y = pos.y - CARD_H / 2;
    const cursor = cc > 0 ? "pointer" : "default";
    let s = `<g class="node-g" data-id="${n.id}" style="cursor:${cursor}">`;
    if (n.installed) {
      s += `<rect x="${x}" y="${y}" width="3" height="${CARD_H}" fill="var(--node-installed)" rx="2"/>`;
    }
    const rx = n.installed ? x + 3 : x, rw = n.installed ? CARD_W - 3 : CARD_W;
    const sc = isRoot ? "var(--node-root-border)" : "var(--node-border)";
    const sw = isRoot ? 2 : 1.5;
    const op = isColl ? ' opacity="0.7"' : "";
    s += `<rect x="${rx}" y="${y}" width="${rw}" height="${CARD_H}" rx="5" ry="5" fill="var(--node-bg)" stroke="${sc}" stroke-width="${sw}"${op}/>`;
    s += `<text x="${pos.x}" y="${pos.y - 4}" text-anchor="middle" font-size="11" font-weight="600" fill="var(--text)" font-family="Helvetica Neue,Helvetica,sans-serif">${n.name}</text>`;
    const vt = n.ver + (n.slot !== "0" ? "  :" + n.slot : "");
    s += `<text x="${pos.x}" y="${pos.y + 10}" text-anchor="middle" font-size="10" fill="var(--text2)" font-family="Helvetica Neue,Helvetica,sans-serif">${vt}</text>`;
    if (cc > 0) {
      const fc = isColl ? "var(--rdepend)" : "var(--text2)";
      const fw = isColl ? "600" : "normal";
      const txt = isColl ? "+" + dc : "\u25BE";
      s += `<text x="${pos.x + CARD_W/2 - 6}" y="${pos.y + CARD_H/2 - 3}" text-anchor="end" font-size="9" fill="${fc}" font-weight="${fw}" font-family="Helvetica Neue,Helvetica,sans-serif">${txt}</text>`;
    }
    s += "</g>";
    parts.push(s);
  });
  parts.push("</g>");
  svg.innerHTML = parts.join("");
}
const nodeIndex = {};
Object.values(treeData).forEach(t => t.nodes.forEach(n => nodeIndex[n.id] = n));
let lastChildMap = null;
function getChildMap() {
  if (lastChildMap && lastChildMap._type === currentType) return lastChildMap;
  const tree = getTree(), cm = {};
  tree.nodes.forEach(n => cm[n.id] = []);
  tree.edges.forEach(e => { if (cm[e.from]) cm[e.from].push(e.to); });
  cm._type = currentType; lastChildMap = cm; return cm;
}
svg.addEventListener("click", ev => {
  const g = ev.target.closest(".node-g"); if (!g) return;
  const id = g.dataset.id, cm = getChildMap();
  if (!(cm[id]||[]).length) return;
  if (collapsed.has(id)) collapsed.delete(id); else collapsed.add(id);
  render();
});
svg.addEventListener("mouseover", ev => {
  const g = ev.target.closest(".node-g"); if (!g) return;
  const n = nodeIndex[g.dataset.id]; if (!n) return;
  showTooltip(ev, n);
});
svg.addEventListener("mousemove", ev => {
  if (ev.target.closest(".node-g")) moveTooltip(ev); else hideTooltip();
});
svg.addEventListener("mouseout", ev => {
  const g = ev.target.closest(".node-g");
  if (g && !g.contains(ev.relatedTarget)) hideTooltip();
});
function showTooltip(ev, n) {
  const useHtml = (n.use||[]).map(u => {
    const on = u.startsWith("+");
    return `<span class="use-flag ${on?"on":"off"}">${u}</span>`;
  }).join("");
  tooltip.innerHTML = `
    <div class="tt-title">${n.cat}/${n.name}-${n.ver}</div>
    ${n.desc ? `<div class="tt-desc">${n.desc}</div>` : ""}
    <div class="tt-row"><span class="tt-label">Slot</span><span class="tt-value">${n.slot}</span></div>
    <div class="tt-row"><span class="tt-label">Status</span><span class="${n.installed?"tt-installed":"tt-not-installed"}">${n.installed?"Installed":"Not installed"}</span></div>
    ${n.homepage ? `<div class="tt-row"><span class="tt-label">Home</span><a class="tt-link" href="${n.homepage}" target="_blank">${n.homepage.replace(/https?:\/\//,"").substring(0,40)}...</a></div>` : ""}
    ${useHtml ? `<div style="margin-top:4px"><span class="tt-label">USE</span><div class="use-flags">${useHtml}</div></div>` : ""}
  `; tooltip.style.display = "block"; moveTooltip(ev);
}
function moveTooltip(ev) {
  const pad = 12; let x = ev.clientX + pad, y = ev.clientY + pad;
  const tw = tooltip.offsetWidth, th = tooltip.offsetHeight;
  if (x + tw > window.innerWidth - pad) x = ev.clientX - tw - pad;
  if (y + th > window.innerHeight - pad) y = ev.clientY - th - pad;
  tooltip.style.left = x + "px"; tooltip.style.top = y + "px";
}
function hideTooltip() { tooltip.style.display = "none"; }
function switchDepType(type) {
  if (!treeData[type]) return;
  currentType = type; collapsed.clear(); lastChildMap = null;
  autoCollapseIfLarge();
  document.querySelectorAll(".dep-tab").forEach(b => {
    b.classList.toggle("active", b.dataset.type === type);
    b.classList.toggle("off", b.dataset.type !== type);
  }); render();
}
function expandAll() {
  const tree = getTree();
  if (tree && tree.nodes.length > 500 && !confirm("This tree has " + tree.nodes.length + " nodes. Expanding all may be slow. Continue?")) return;
  collapsed.clear(); lastChildMap = null; render();
}
function collapseAll() {
  const tree = getTree(); if (!tree) return;
  const cm = getChildMap();
  collapsed.clear();
  tree.nodes.forEach(n => { if ((cm[n.id]||[]).length > 0) collapsed.add(n.id); });
  lastChildMap = null; render();
}
function resetView() {
  collapsed.clear(); lastChildMap = null; autoCollapsed = false;
  autoCollapseIfLarge();
  render();
}
function zoomIn() { zoom = Math.min(zoom * 1.25, 4); applyZoom(); }
function zoomOut() { zoom = Math.max(zoom / 1.25, 0.25); applyZoom(); }
function applyZoom() {
  const cx = viewBox.x + viewBox.w / 2, cy = viewBox.y + viewBox.h / 2;
  const nw = viewBox.w / zoom, nh = viewBox.h / zoom;
  svg.setAttribute("viewBox", `${cx - nw/2} ${cy - nh/2} ${nw} ${nh}`);
  document.getElementById("zoom-level").textContent = Math.round(zoom * 100) + "%";
}
container.addEventListener("mousedown", e => {
  if (e.target.closest(".node-g")) return;
  isPanning = true; panStart = {x: e.clientX, y: e.clientY};
  const vb = svg.getAttribute("viewBox").split(" ").map(Number);
  vbStart = {x: vb[0], y: vb[1]}; container.style.cursor = "grabbing";
});
container.addEventListener("mousemove", e => {
  if (!isPanning) return;
  const vb = svg.getAttribute("viewBox").split(" ").map(Number);
  const scale = vb[2] / container.clientWidth;
  const dx = (e.clientX - panStart.x) * scale, dy = (e.clientY - panStart.y) * scale;
  svg.setAttribute("viewBox", `${vbStart.x - dx} ${vbStart.y - dy} ${vb[2]} ${vb[3]}`);
});
container.addEventListener("mouseup", () => { isPanning = false; container.style.cursor = ""; });
container.addEventListener("mouseleave", () => { isPanning = false; container.style.cursor = ""; });
container.addEventListener("wheel", e => {
  e.preventDefault();
  const factor = e.deltaY > 0 ? 0.9 : 1.1;
  zoom *= factor; zoom = Math.max(0.25, Math.min(4, zoom));
  const vb = svg.getAttribute("viewBox").split(" ").map(Number);
  const rect = container.getBoundingClientRect();
  const mx = (e.clientX - rect.left) / rect.width, my = (e.clientY - rect.top) / rect.height;
  const nw = vb[2] / factor, nh = vb[3] / factor;
  const nx = vb[0] + (vb[2] - nw) * mx, ny = vb[1] + (vb[3] - nh) * my;
  svg.setAttribute("viewBox", `${nx} ${ny} ${nw} ${nh}`);
  document.getElementById("zoom-level").textContent = Math.round(zoom * 100) + "%";
}, {passive: false});
let resizeTimer = 0;
window.addEventListener("resize", () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(render, 120);
});
render();

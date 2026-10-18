const bugChips = () => Array.from(document.querySelectorAll("#bug-filters .filter-btn"));
const bugRows = () => Array.from(document.querySelectorAll("details.bug-item"));
const bugDefaults = {};
bugChips().forEach(b => { (bugDefaults[b.dataset.group] = bugDefaults[b.dataset.group] || []); if (b.classList.contains("active")) bugDefaults[b.dataset.group].push(b.dataset.value); });
function bugsSetAll(open) { bugRows().forEach(d => { d.open = open; }); }
function bugsLit() {
  const lit = {};
  bugChips().forEach(b => { lit[b.dataset.group] = lit[b.dataset.group] || new Set(); if (b.classList.contains("active")) lit[b.dataset.group].add(b.dataset.value); });
  return lit;
}
function bugsApply() {
  const lit = bugsLit();
  const has = (g, v) => !lit[g] || lit[g].has(v);
  const box = document.getElementById("bug-search");
  const q = box ? box.value.trim().toLowerCase() : "";
  const days = lit.age ? parseInt(Array.from(lit.age)[0] || "0", 10) : 0;
  const cutoff = days ? new Date(Date.now() - days * 86400000).toISOString().slice(0, 10) : "";
  let shown = 0, total = 0;
  bugRows().forEach(d => {
    const s = d.dataset; total++;
    let ok = has("status", s.status) && has("version", s.version) && has("component", s.component) && has("severity", s.severity);
    if (ok && s.status === "resolved") ok = has("resolution", s.resolution);
    if (ok && lit.keyword && lit.keyword.size) ok = s.keyword.split(" ").some(k => lit.keyword.has(k));
    if (ok && cutoff) ok = s.changed >= cutoff;
    if (ok && q) ok = s.search.indexOf(q) >= 0;
    d.classList.toggle("hidden", !ok); if (ok) shown++;
  });
  const el = document.getElementById("bugs-shown");
  if (el) el.textContent = shown === total ? "" : " \u00b7 showing " + shown;
  const badge = document.getElementById("bug-filters-count");
  if (badge) { const n = bugsChanged(lit).length; badge.textContent = n ? String(n) : ""; badge.classList.toggle("affected", n > 0); }
}
function bugsChanged(lit) {
  return Object.keys(lit).filter(g => Array.from(lit[g]).sort().join(",") !== (bugDefaults[g] || []).slice().sort().join(","));
}
function bugsToggleFilters(open) {
  const box = document.getElementById("bug-filters"), btn = document.getElementById("bug-filters-toggle");
  if (!box) return;
  const show = open === undefined ? box.classList.contains("collapsed") : open;
  box.classList.toggle("collapsed", !show);
  if (btn) { btn.setAttribute("aria-expanded", show ? "true" : "false"); btn.classList.toggle("active", show); }
}
function bugsToggle(btn) {
  if (btn.dataset.group === "age") bugChips().filter(b => b.dataset.group === "age").forEach(b => b.classList.toggle("active", b === btn));
  else btn.classList.toggle("active");
  bugsApply(); bugsWriteHash();
}
function bugsReset() {
  bugChips().forEach(b => b.classList.toggle("active", bugDefaults[b.dataset.group].indexOf(b.dataset.value) >= 0));
  const box = document.getElementById("bug-search"); if (box) box.value = "";
  bugsApply(); history.replaceState(null, "", location.pathname + location.search);
}
function bugsWriteHash() {
  const lit = bugsLit(), parts = [];
  bugsChanged(lit).forEach(g => parts.push(g + "=" + Array.from(lit[g]).sort().join(",")));
  const box = document.getElementById("bug-search");
  if (box && box.value.trim()) parts.push("q=" + encodeURIComponent(box.value.trim()));
  history.replaceState(null, "", location.pathname + location.search + (parts.length ? "#" + parts.join("&") : ""));
}
(function () {
  const h = location.hash.slice(1);
  if (h.indexOf("bug-") === 0) {
    const el = document.getElementById(h);
    if (el && el.tagName === "DETAILS") {
      bugChips().forEach(b => { const v = el.dataset[b.dataset.group]; if (v !== undefined && v.split(" ").indexOf(b.dataset.value) >= 0 && b.dataset.group !== "keyword") b.classList.add("active"); });
      bugsApply(); el.open = true; el.scrollIntoView();
      return;
    }
  }
  if (h && h.indexOf("=") > 0) {
    h.split("&").forEach(p => {
      const i = p.indexOf("="), g = p.slice(0, i), vs = p.slice(i + 1);
      if (g === "q") { const box = document.getElementById("bug-search"); if (box) box.value = decodeURIComponent(vs); return; }
      const want = vs ? vs.split(",") : [];
      bugChips().filter(b => b.dataset.group === g).forEach(b => b.classList.toggle("active", want.indexOf(b.dataset.value) >= 0));
    });
    bugsToggleFilters(true);
  }
  bugsApply();
})();

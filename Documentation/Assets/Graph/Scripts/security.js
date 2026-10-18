function glsaSetAll(open) {
  document.querySelectorAll("details.glsa-item").forEach(d => { d.open = open; });
}
function glsaFilter(mode, btn) {
  document.querySelectorAll("details.glsa-item").forEach(d => {
    d.classList.toggle("hidden", mode === "affecting" && d.dataset.status !== "vulnerable");
  });
  document.querySelectorAll(".glsa-toolbar .filter-btn").forEach(b => b.classList.toggle("active", b === btn));
}
(function () {
  if (!location.hash) return;
  const el = document.getElementById(location.hash.slice(1));
  if (el && el.tagName === "DETAILS") { el.open = true; el.scrollIntoView(); }
})();

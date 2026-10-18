const filters = {
  download:true, fetchonly:true, install:true, update:true, reinstall:true, downgrade:true, run:true,
  unmask:true, keyword:true, useflag:true, license:true,
  bdepend:true, depend:true, rdepend:true, pdepend:true, idepend:true
};
const depColors = {bdepend:"#ef6c00",depend:"#e53935",rdepend:"#7e57c2",pdepend:"#00897b",idepend:"#6d4c41"};
const depDash = {bdepend:"",depend:"",rdepend:"",pdepend:"6,3",idepend:"3,3"};
let hoverMode=false, hoverPkg=null, critMode=false, timeMode=false;
function toggleFilter(btn){
  const a=btn.dataset.action; filters[a]=!filters[a];
  btn.classList.toggle("active",filters[a]); btn.classList.toggle("off",!filters[a]);
  applyFilters();
}
function toggleDetail(t){
  t.classList.toggle("open");
  const p=t.closest("tr").dataset.pkg;
  document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.toggle("visible"));
  setTimeout(drawOverlays,20);
}
function expandAll(){
  document.querySelectorAll("#gantt tbody tr[data-pkg]:not(.row-hidden)").forEach(r=>{
    const t=r.querySelector(".toggle"); if(t&&!t.classList.contains("open")) t.classList.add("open");
    const p=r.dataset.pkg;
    document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.add("visible"));
  });
  setTimeout(drawOverlays,20);
}
function collapseAll(){
  document.querySelectorAll(".toggle.open").forEach(t=>t.classList.remove("open"));
  document.querySelectorAll("tr.detail-row.visible").forEach(d=>d.classList.remove("visible"));
  setTimeout(drawOverlays,20);
}
function applyFilters(){
  document.querySelectorAll(".cell[data-type]").forEach(c=>c.classList.toggle("hidden",filters[c.dataset.type]===false));
  document.querySelectorAll("#gantt tbody tr[data-pkg]").forEach(r=>{
    const a=(r.dataset.actions||"").split(" ").filter(Boolean), v=a.some(x=>filters[x]!==false);
    r.classList.toggle("row-hidden",!v);
    if(!v){const p=r.dataset.pkg;
      document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.remove("visible"));
      const t=r.querySelector(".toggle");if(t)t.classList.remove("open");}
  });
  syncTimeRows();
  if(timeMode)layoutTimeView();
  drawOverlays();
}
function secs(n){const s=parseFloat(n.dataset.seconds);return Number.isFinite(s)?s:1;}
function fmtDur(s){s=Math.max(0,Math.round(s));
  if(s>=3600){const h=Math.floor(s/3600),m=Math.floor((s%3600)/60);return m?`${h}h ${m}m`:`${h}h`;}
  if(s>=60){const m=Math.floor(s/60),r=s%60;return r?`${m}m ${r}s`:`${m}m`;}
  return `${s}s`;}
function rowOf(el){return el.closest(timeMode?".gantt-time-row":"tr");}
function cellOf(id){const root=timeMode?document.getElementById("gantt-time"):document.getElementById("gantt");
  return root?root.querySelector(`[data-id="${id}"]`):null;}
function waveOf(c){if(c.dataset.wave)return +c.dataset.wave;const td=c.closest("td");return td?td.cellIndex:0;}
function stepOf(c){return timeMode?parseFloat(c.dataset.es||"0"):waveOf(c);}
function visRows(){return timeMode
  ?[...document.querySelectorAll("#gantt-time .gantt-time-row:not(.row-hidden)")]
  :[...document.querySelectorAll("#gantt tbody tr[data-pkg]:not(.row-hidden)")];}
function rowCells(row){const cs=timeMode
  ?[...row.querySelectorAll(".cell:not(.hidden)")].sort((a,b)=>waveOf(a)-waveOf(b))
  :[];if(!timeMode){row.querySelectorAll("td:not(.pkg)").forEach(td=>{const s=td.querySelector(".cell:not(.hidden)");if(s)cs.push(s);});}
  return cs;}
function clipSeg(x1,y1,x2,y2,w,h){
  const dx=x2-x1,dy=y2-y1,p=[-dx,dx,-dy,dy],q=[x1,w-x1,y1,h-y1];
  let u1=0,u2=1;
  for(let i=0;i<4;i++){
    if(p[i]===0){if(q[i]<0)return null;}
    else{const t=q[i]/p[i];
      if(p[i]<0){if(t>u2)return null;if(t>u1)u1=t;}
      else{if(t<u1)return null;if(t<u2)u2=t;}}
  }
  return [x1+u1*dx,y1+u1*dy,x1+u2*dx,y1+u2*dy];
}
function dashPath(x1,y1,x2,y2){
  const dx=x2-x1,dy=y2-y1,len=Math.hypot(dx,dy);
  if(len<0.5) return "";
  const ux=dx/len,uy=dy/len,on=5,step=9;
  let d="",t=0;
  while(t<len){const b=Math.min(t+on,len);
    d+=`M${x1+ux*t},${y1+uy*t}L${x1+ux*b},${y1+uy*b}`;t+=step;}
  return d;
}
function drawOverlays(){
  const svg=document.getElementById("dep-svg"),wr=document.getElementById("gantt-wrapper"),
        wR=wr.getBoundingClientRect(),ns="http://www.w3.org/2000/svg",
        barColor=getComputedStyle(document.documentElement).getPropertyValue("--bar").trim();
  /* Pin the overlay to the visible scrollport. Edge coordinates are
     relative to that viewport; scroll redraws them so curves that
     leave the first screen stay attached to their bars. */
  svg.style.left=wr.scrollLeft+"px";svg.style.top=wr.scrollTop+"px";
  svg.style.width=wr.clientWidth+"px";svg.style.height=wr.clientHeight+"px";
  svg.setAttribute("width",wr.clientWidth);svg.setAttribute("height",wr.clientHeight);svg.innerHTML="";
  const defs=document.createElementNS(ns,"defs");
  for(const[t,c]of Object.entries(depColors)){
    const m=document.createElementNS(ns,"marker");m.setAttribute("id","arrow-"+t);
    m.setAttribute("markerWidth","6");m.setAttribute("markerHeight","5");
    m.setAttribute("refX","6");m.setAttribute("refY","2.5");m.setAttribute("orient","auto");
    const p=document.createElementNS(ns,"polygon");p.setAttribute("points","0 0,6 2.5,0 5");
    p.setAttribute("fill",c);m.appendChild(p);defs.appendChild(m);
  }svg.appendChild(defs);
  const edges=[];
  visRows().forEach(row=>{
    const f=rowCells(row);
    for(let i=0;i<f.length-1;i++){
      const a=f[i].getBoundingClientRect(),b=f[i+1].getBoundingClientRect(),
            x1=a.right-wR.left,y1=a.top+a.height/2-wR.top,
            x2=b.left-wR.left,y2=b.top+b.height/2-wR.top,
            seg=clipSeg(x1,y1,x2,y2,wr.clientWidth,wr.clientHeight),
            l=document.createElementNS(ns,"path");
      /* stroke-dasharray on a long connector stops painting partway.
         Each dash is its own short stroke. */
      if(seg){
        const d=dashPath(seg[0],seg[1],seg[2],seg[3]);
        if(d){l.setAttribute("d",d);
        l.setAttribute("fill","none");
        l.setAttribute("stroke",barColor);l.setAttribute("stroke-width","2");
        l.setAttribute("class","bar-edge");
        l.dataset.pkg=row.dataset.pkg;svg.appendChild(l);}}
      edges.push({el:l,from:f[i],to:f[i+1]});}
  });
  deps.forEach(([fid,tid,dt])=>{
    if(!filters[dt])return;
    const fe=cellOf(fid),te=cellOf(tid);
    if(!fe||!te||fe.classList.contains("hidden")||te.classList.contains("hidden"))return;
    const fr=rowOf(fe),tr2=rowOf(te);
    if(!fr||!tr2||fr.classList.contains("row-hidden")||tr2.classList.contains("row-hidden"))return;
    const fR=fe.getBoundingClientRect(),tR=te.getBoundingClientRect(),
          x1=fR.right-wR.left+2,y1=fR.top+fR.height/2-wR.top,
          x2=tR.left-wR.left-2,y2=tR.top+tR.height/2-wR.top,
          mx=(x1+x2)/2,p=document.createElementNS(ns,"path");
    p.setAttribute("d",`M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`);
    p.setAttribute("stroke",depColors[dt]);p.setAttribute("stroke-width","1.2");
    p.setAttribute("fill","none");p.setAttribute("marker-end",`url(#arrow-${dt})`);
    p.setAttribute("opacity","0.7");if(depDash[dt])p.setAttribute("stroke-dasharray",depDash[dt]);
    p.setAttribute("class","dep-edge");p.dataset.fromPkg=fr.dataset.pkg;p.dataset.toPkg=tr2.dataset.pkg;p.dataset.depType=dt;
    svg.appendChild(p);
    if(waveOf(fe)<waveOf(te))edges.push({el:p,from:fe,to:te});
    else{p.classList.add("back-edge");
      if(dt==="rdepend")p.setAttribute("stroke-dasharray","4,3");}
  });
  markCritical(edges);
  if(hoverMode&&hoverPkg)litEdges(hoverPkg);
}
function toggleCritMode(btn){
  critMode=!critMode;
  btn.classList.toggle("active",critMode);btn.setAttribute("aria-pressed",critMode);
  document.getElementById("dep-svg").classList.toggle("crit-mode",critMode);
  document.getElementById("gantt").classList.toggle("crit-mode",critMode);
  const tv=document.getElementById("gantt-time");if(tv)tv.classList.toggle("crit-mode",critMode);
  drawOverlays();
}
function markCritical(edges){
  document.querySelectorAll(".cell.crit").forEach(c=>c.classList.remove("crit"));
  const btn=document.getElementById("crit-mode-btn");
  if(!critMode){btn.textContent="Critical path";return;}
  const len=new Map(),pred=new Map(),nodes=new Set();
  edges.forEach(e=>{nodes.add(e.from);nodes.add(e.to);});
  const order=[...nodes].sort((a,b)=>waveOf(a)-waveOf(b)||stepOf(a)-stepOf(b));
  order.forEach(n=>len.set(n,secs(n)));
  edges.slice().sort((a,b)=>waveOf(a.from)-waveOf(b.from)).forEach(e=>{
    const l=len.get(e.from)+secs(e.to);if(l>len.get(e.to)){len.set(e.to,l);pred.set(e.to,e);}
  });
  let end=null;
  order.forEach(n=>{if(!end||len.get(n)>len.get(end)||(len.get(n)===len.get(end)&&waveOf(n)>waveOf(end)))end=n;});
  const total=end?len.get(end):0;
  if(total<=0){btn.textContent="Critical path";return;}
  const path=[];for(let c=end;c;){path.push(c);const e=pred.get(c);if(!e)break;c=e.from;}
  const timed=path.some(n=>n.dataset.timed==="1");
  btn.textContent=timed?`Critical path (${fmtDur(total)})`:`Critical path (${Math.round(total)})`;
  if(path.length<2)return;
  path.forEach(c=>c.classList.add("crit"));
  for(let c=end;;){const e=pred.get(c);if(!e)break;e.el.classList.add("crit");c=e.from;}
}
function toggleHoverMode(btn){
  hoverMode=!hoverMode;
  btn.classList.toggle("active",hoverMode);btn.setAttribute("aria-pressed",hoverMode);
  document.getElementById("dep-svg").classList.toggle("hover-mode",hoverMode);
  document.getElementById("gantt").classList.toggle("hover-mode",hoverMode);
  const tv=document.getElementById("gantt-time");if(tv)tv.classList.toggle("hover-mode",hoverMode);
  if(!hoverMode)litEdges(null);
}
function litEdges(p){
  hoverPkg=p;
  document.querySelectorAll("#dep-svg .lit").forEach(e=>e.classList.remove("lit"));
  document.querySelectorAll(".hover-lit").forEach(r=>r.classList.remove("hover-lit"));
  if(!p)return;
  document.querySelectorAll(`#dep-svg [data-pkg="${p}"],#dep-svg [data-from-pkg="${p}"],#dep-svg [data-to-pkg="${p}"]`)
    .forEach(e=>e.classList.add("lit"));
  document.querySelectorAll(`#gantt tr[data-pkg="${p}"],#gantt-time .gantt-time-row[data-pkg="${p}"]`)
    .forEach(r=>r.classList.add("hover-lit"));
}
(function(){
  const wr=document.getElementById("gantt-wrapper");if(!wr)return;
  wr.addEventListener("mouseover",e=>{
    if(!hoverMode)return;
    const r=e.target.closest("tr[data-pkg],tr.detail-row,.gantt-time-row"),p=r?(r.dataset.pkg||r.dataset.parent):null;
    if(p!==hoverPkg)litEdges(p);
  });
  wr.addEventListener("mouseleave",()=>{if(hoverMode)litEdges(null);});
})();
function toggleTimeMode(btn){
  timeMode=!timeMode;
  btn.classList.toggle("active",timeMode);btn.setAttribute("aria-pressed",timeMode);
  document.getElementById("gantt-wrapper").classList.toggle("time-mode",timeMode);
  if(timeMode)layoutTimeView();
  drawOverlays();
}
function ensureTimeView(){
  let tv=document.getElementById("gantt-time");if(tv)return tv;
  tv=document.createElement("div");tv.id="gantt-time";tv.className="gantt-time"+(critMode?" crit-mode":"");
  const ruler=document.createElement("div");ruler.className="gantt-time-ruler";ruler.id="gantt-time-ruler";tv.appendChild(ruler);
  document.querySelectorAll("#gantt tbody tr[data-pkg]").forEach(row=>{
    const r=document.createElement("div");r.className="gantt-time-row";r.dataset.pkg=row.dataset.pkg;
    const lab=document.createElement("div");lab.className="gantt-time-label";
    lab.textContent=(row.querySelector("td.pkg")||{}).innerText||row.dataset.pkg;
    const track=document.createElement("div");track.className="gantt-time-track";
    row.querySelectorAll(".cell").forEach(c=>{
      const b=c.cloneNode(true);b.removeAttribute("id");b.dataset.wave=String(c.closest("td").cellIndex);
      track.appendChild(b);});
    r.appendChild(lab);r.appendChild(track);tv.appendChild(r);});
  document.getElementById("gantt-wrapper").appendChild(tv);
  return tv;}
function syncTimeRows(){
  document.querySelectorAll("#gantt-time .gantt-time-row").forEach(r=>{
    const src=document.querySelector(`#gantt tr[data-pkg="${r.dataset.pkg}"]`);
    if(src)r.classList.toggle("row-hidden",src.classList.contains("row-hidden"));});
}
function layoutTimeView(){
  const tv=ensureTimeView();syncTimeRows();
  const bars=[...tv.querySelectorAll(".gantt-time-row:not(.row-hidden) .cell:not(.hidden)")];
  const waveMax=new Map();
  bars.forEach(b=>{const w=waveOf(b);waveMax.set(w,Math.max(waveMax.get(w)||0,secs(b)));});
  const waves=[...waveMax.keys()].sort((a,b)=>a-b);
  const waveStart=new Map();let t=0;
  waves.forEach(w=>{waveStart.set(w,t);t+=waveMax.get(w);});
  const maxEnd=t;
  bars.forEach(b=>b.dataset.es=String(waveStart.get(waveOf(b))||0));
  const px=Math.max(0.5,Math.min(8,1400/Math.max(maxEnd,1)));
  const width=Math.max(400,Math.ceil(maxEnd*px)+24);
  /* One width for the whole timeline. Per-row max-content ends each
     rule at that row's own last bar. */
  tv.style.width=(210+width)+"px";
  tv.querySelectorAll(".gantt-time-track").forEach(tr=>{tr.style.flex="none";tr.style.width=width+"px";});
  bars.forEach(b=>{const d=Math.max(secs(b),0);b.style.left=((waveStart.get(waveOf(b))||0)*px)+"px";
    b.style.width=Math.max(d>0?d*px:8,8)+"px";});
  const ruler=document.getElementById("gantt-time-ruler");ruler.innerHTML="";
  ruler.style.width=width+"px";
  const step=maxEnd<=120?30:maxEnd<=600?60:maxEnd<=1800?300:maxEnd<=7200?600:1800;
  for(let u=0;u<=maxEnd;u+=step){const tick=document.createElement("span");tick.className="gantt-time-tick";
    tick.style.left=(u*px)+"px";tick.textContent=fmtDur(u);ruler.appendChild(tick);}
}
function toggleUseExpand(){
  const f=document.getElementById("global-use-flags"),
        b=f.previousElementSibling;
  f.classList.toggle("collapsed");
  b.classList.toggle("open");
}
let overlayFrame=0;
function scheduleOverlays(){
  if(overlayFrame)return;
  overlayFrame=requestAnimationFrame(()=>{overlayFrame=0;drawOverlays();});
}
window.addEventListener("load",drawOverlays);
window.addEventListener("resize",scheduleOverlays);
document.getElementById("gantt-wrapper").addEventListener("scroll",scheduleOverlays);

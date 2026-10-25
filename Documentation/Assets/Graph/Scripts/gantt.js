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
  setTimeout(()=>{markOverlayDirty();drawOverlays();},20);
}
function expandAll(){
  document.querySelectorAll("#gantt tbody tr[data-pkg]:not(.row-hidden)").forEach(r=>{
    const t=r.querySelector(".toggle"); if(t&&!t.classList.contains("open")) t.classList.add("open");
    const p=r.dataset.pkg;
    document.querySelectorAll(`tr.detail-row[data-parent="${p}"]`).forEach(d=>d.classList.add("visible"));
  });
  setTimeout(()=>{markOverlayDirty();drawOverlays();},20);
}
function collapseAll(){
  document.querySelectorAll(".toggle.open").forEach(t=>t.classList.remove("open"));
  document.querySelectorAll("tr.detail-row.visible").forEach(d=>d.classList.remove("visible"));
  setTimeout(()=>{markOverlayDirty();drawOverlays();},20);
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
  markOverlayDirty();
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
/* Overlay rendering is split into a layout model and a scroll render.
   The model (cell geometry in content coordinates, the edge list, the
   critical-path sets) is rebuilt only when the layout can change:
   load, resize, filter/expand/collapse and time-mode changes mark it
   dirty. The SVG itself is anchored in *content* coordinates over the
   visible viewport plus one viewport of overscan on every side, so
   ordinary scrolling moves it natively with the page (compositor
   scroll, no DOM mutation per scroll frame). Only when the viewport
   approaches the overscan edge does a scroll frame re-anchor and
   re-cull the cached edges, reusing a pool of SVG path nodes.
   Clipping and dash construction are unchanged, so a settled frame is
   the live SVG on every browser.
   Safari still repaints those antialiased strokes for every newly
   exposed tile, which shows up as row-by-row redraws. While a scroll
   gesture is in progress there, the live SVG is taken out of painting
   and a retina bitmap of the same edges (the whole chart, when that
   fits in one image) scrolls in its place. The bitmap is not rebuilt
   during the gesture. When the gesture settles the bitmap is hidden
   and the live SVG is shown again, so hover, critical-path and filter
   styling stay on the SVG and a still frame matches Chrome. */
const SVGNS="http://www.w3.org/2000/svg";
let overlayDirty=true;
let overlayGeom=new Map();
let overlayEdges=[];
let critPathEdges=new Set();
let svgDefsReady=false;
let overlayAnchor=null;
let overlayEpoch=0;
const svgPathPool=[];
/* Desktop Safari only. Chrome's UA also contains "Safari/". */
const overlayBitmapScroll=/Safari\//.test(navigator.userAgent)
  && !/Chrome\/|Chromium\/|CriOS\/|Edg\/|Android/.test(navigator.userAgent);
let overlayHeld=false;
let overlayHoldTimer=0;
let overlayRestTop=0;
let overlayRestLeft=0;
let overlayBitmapKey="";
let overlayBitmapToken=0;
let overlayBitmapBusy=false;
let overlayBitmapPending=false;
let overlayBitmapTimer=0;
function markOverlayDirty(){
  overlayDirty=true;overlayEpoch++;
  overlayBitmapKey="";overlayBitmapToken++;overlayBitmapPending=true;
}
function measureOverlayGeometry(){
  const wr=document.getElementById("gantt-wrapper");
  const wR=wr.getBoundingClientRect(),sl=wr.scrollLeft,st=wr.scrollTop;
  overlayGeom.clear();
  document.querySelectorAll("#gantt .cell, #gantt-time .cell").forEach(c=>{
    const r=c.getBoundingClientRect();
    overlayGeom.set(c,{l:r.left-wR.left+sl,t:r.top-wR.top+st,
                       r:r.right-wR.left+sl,b:r.bottom-wR.top+st,h:r.height});
  });
}
function buildOverlayModel(){
  overlayEdges=[];
  measureOverlayGeometry();
  visRows().forEach(row=>{
    const f=rowCells(row);
    for(let i=0;i<f.length-1;i++)
      overlayEdges.push({kind:"bar",from:f[i],to:f[i+1],rowPkg:row.dataset.pkg,crit:true});
  });
  deps.forEach(([fid,tid,dt])=>{
    if(!filters[dt])return;
    const fe=cellOf(fid),te=cellOf(tid);
    if(!fe||!te||fe.classList.contains("hidden")||te.classList.contains("hidden"))return;
    const fr=rowOf(fe),tr2=rowOf(te);
    if(!fr||!tr2||fr.classList.contains("row-hidden")||tr2.classList.contains("row-hidden"))return;
    const fwd=waveOf(fe)<waveOf(te);
    overlayEdges.push({kind:"dep",from:fe,to:te,dt:dt,fromPkg:fr.dataset.pkg,toPkg:tr2.dataset.pkg,
                       crit:fwd,back:!fwd});
  });
  overlayDirty=false;
  refreshCritical();
}
function refreshCritical(){
  critPathEdges=new Set();
  document.querySelectorAll(".cell.crit").forEach(c=>c.classList.remove("crit"));
  const btn=document.getElementById("crit-mode-btn");
  if(!btn)return;
  if(!critMode){btn.textContent="Critical path";return;}
  const edges=overlayEdges.filter(e=>e.crit);
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
  for(let c=end;;){const e=pred.get(c);if(!e)break;critPathEdges.add(e);c=e.from;}
}
function makeArrowDefs(){
  const defs=document.createElementNS(SVGNS,"defs");
  for(const[t,c]of Object.entries(depColors)){
    const m=document.createElementNS(SVGNS,"marker");m.setAttribute("id","arrow-"+t);
    m.setAttribute("markerWidth","6");m.setAttribute("markerHeight","5");
    m.setAttribute("refX","6");m.setAttribute("refY","2.5");m.setAttribute("orient","auto");
    const p=document.createElementNS(SVGNS,"polygon");p.setAttribute("points","0 0,6 2.5,0 5");
    p.setAttribute("fill",c);m.appendChild(p);defs.appendChild(m);
  }
  return defs;
}
function ensureSvgDefs(svg){
  if(svgDefsReady)return;
  svg.appendChild(makeArrowDefs());svgDefsReady=true;
}
function paintOverlayEdges(svg,ax,ay,aw,ah,usePool){
  const barColor=getComputedStyle(document.documentElement).getPropertyValue("--bar").trim();
  let used=0;
  for(const e of overlayEdges){
    const a=overlayGeom.get(e.from),b=overlayGeom.get(e.to);
    if(!a||!b)continue;
    let x1,y1,x2,y2,d;
    if(e.kind==="bar"){
      x1=a.r-ax;y1=(a.t+a.h/2)-ay;x2=b.l-ax;y2=(b.t+b.h/2)-ay;
      if(Math.max(x1,x2)<-8||Math.min(x1,x2)>aw+8||Math.max(y1,y2)<-8||Math.min(y1,y2)>ah+8)continue;
      const seg=clipSeg(x1,y1,x2,y2,aw,ah);
      if(!seg)continue;
      /* stroke-dasharray on a long connector stops painting partway.
         Each dash is its own short stroke. */
      d=dashPath(seg[0],seg[1],seg[2],seg[3]);
      if(!d)continue;
    }else{
      x1=a.r-ax+2;y1=(a.t+a.h/2)-ay;x2=b.l-ax-2;y2=(b.t+b.h/2)-ay;
      if(Math.max(x1,x2)<-8||Math.min(x1,x2)>aw+8||Math.max(y1,y2)<-8||Math.min(y1,y2)>ah+8)continue;
      const mx=(x1+x2)/2;
      d=`M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`;
    }
    let p;
    if(usePool){
      p=svgPathPool[used];
      if(!p){p=document.createElementNS(SVGNS,"path");svgPathPool.push(p);svg.appendChild(p);}
    }else{p=document.createElementNS(SVGNS,"path");svg.appendChild(p);}
    used++;
    p.setAttribute("d",d);
    p.setAttribute("fill","none");
    p.removeAttribute("marker-end");p.removeAttribute("stroke-dasharray");p.removeAttribute("opacity");
    let cls;
    if(e.kind==="bar"){
      p.setAttribute("stroke",barColor);p.setAttribute("stroke-width","2");
      cls="bar-edge";p.dataset.pkg=e.rowPkg;delete p.dataset.fromPkg;delete p.dataset.toPkg;delete p.dataset.depType;
    }else{
      p.setAttribute("stroke",depColors[e.dt]);p.setAttribute("stroke-width","1.2");
      p.setAttribute("marker-end",`url(#arrow-${e.dt})`);
      p.setAttribute("opacity","0.7");
      const dash=e.back&&e.dt==="rdepend"?"4,3":depDash[e.dt];
      if(dash)p.setAttribute("stroke-dasharray",dash);
      cls="dep-edge"+(e.back?" back-edge":"");
      delete p.dataset.pkg;p.dataset.fromPkg=e.fromPkg;p.dataset.toPkg=e.toPkg;p.dataset.depType=e.dt;
    }
    if(critPathEdges.has(e))cls+=" crit";
    if(hoverMode&&hoverPkg&&(e.rowPkg===hoverPkg||e.fromPkg===hoverPkg||e.toPkg===hoverPkg))cls+=" lit";
    p.setAttribute("class",cls);
  }
  if(usePool)while(svgPathPool.length>used){const p=svgPathPool.pop();p.remove();}
}
function overlayCoversViewport(wr){
  if(!overlayAnchor)return false;
  const a=overlayAnchor,vw=wr.clientWidth,vh=wr.clientHeight,
        sl=wr.scrollLeft,st=wr.scrollTop;
  return (a.x===0||sl>=a.x+vw/2) && (a.y===0||st>=a.y+vh/2) &&
         (sl+vw>=wr.scrollWidth-1||sl+vw<=a.x+a.w-vw/2) &&
         (st+vh>=wr.scrollHeight-1||st+vh<=a.y+a.h-vh/2);
}
function renderOverlays(){
  const svg=document.getElementById("dep-svg"),wr=document.getElementById("gantt-wrapper");
  if(!svg||!wr)return;
  const vw=wr.clientWidth,vh=wr.clientHeight,sl=wr.scrollLeft,st=wr.scrollTop;
  /* Anchor the overlay in content coordinates over the viewport plus
     one viewport of overscan on every side. It scrolls natively with
     the content; edge coordinates are relative to the anchor. */
  const content=document.getElementById(timeMode?"gantt-time":"gantt"),
        cw=content?content.offsetLeft+content.offsetWidth:wr.scrollWidth,
        ch=content?content.offsetTop+content.offsetHeight:wr.scrollHeight,
        ax=Math.max(0,sl-vw),ay=Math.max(0,st-vh),
        aw=Math.min(sl+vw+vw,cw)-ax,ah=Math.min(st+vh+vh,ch)-ay;
  overlayAnchor={x:ax,y:ay,w:aw,h:ah};
  svg.style.left=ax+"px";svg.style.top=ay+"px";
  svg.style.width=aw+"px";svg.style.height=ah+"px";
  svg.setAttribute("width",aw);svg.setAttribute("height",ah);
  ensureSvgDefs(svg);
  paintOverlayEdges(svg,ax,ay,aw,ah,true);
  if(hoverMode&&hoverPkg)litEdges(hoverPkg);
}
/* A standalone SVG image does not see the page stylesheet, so hover and
   critical-path styling has to be written onto the clone as attributes. */
function bakeOverlayLook(clone){
  if(!critMode&&!hoverMode)return;
  const accent=getComputedStyle(document.documentElement).getPropertyValue("--accent").trim();
  clone.querySelectorAll("path").forEach(p=>{
    const crit=p.classList.contains("crit"),lit=p.classList.contains("lit"),bar=p.classList.contains("bar-edge");
    if(hoverMode&&!lit&&!(critMode&&crit)){p.setAttribute("visibility","hidden");return;}
    if(critMode&&crit){
      p.setAttribute("opacity","1");p.setAttribute("stroke-width",bar?"3":"2.4");
      if(bar&&accent)p.setAttribute("stroke",accent);
    }else if(critMode)p.setAttribute("opacity","0.12");
    else if(lit)p.setAttribute("opacity","1");
  });
}
function overlayBitmapBox(){
  const wr=document.getElementById("gantt-wrapper");
  if(!wr)return null;
  const dpr=Math.min(window.devicePixelRatio||1,2);
  const content=document.getElementById(timeMode?"gantt-time":"gantt");
  const cw=content?content.offsetLeft+content.offsetWidth:wr.scrollWidth;
  const ch=content?content.offsetTop+content.offsetHeight:wr.scrollHeight;
  /* One retina image of the whole chart scrolls with no further
     rasterization. Past the pixel cap, fall back to the live anchor. */
  if(cw>0&&ch>0&&cw*ch*dpr*dpr<=32e6)return {x:0,y:0,w:cw,h:ch,dpr:dpr};
  if(!overlayAnchor)return null;
  const a=overlayAnchor;
  if(a.w<1||a.h<1||a.w*a.h*dpr*dpr>32e6)return null;
  return {x:a.x,y:a.y,w:a.w,h:a.h,dpr:dpr};
}
function overlayBitmapWantedKey(){
  const b=overlayBitmapBox();
  if(!b)return "";
  return [b.x,b.y,b.w,b.h,hoverMode?1:0,critMode?1:0,hoverPkg||"",overlayEpoch].join(":");
}
function ensureOverlayCanvas(){
  let c=document.getElementById("dep-canvas");
  if(c)return c;
  const svg=document.getElementById("dep-svg");
  c=document.createElement("canvas");
  c.id="dep-canvas";c.setAttribute("aria-hidden","true");
  c.style.position="absolute";c.style.pointerEvents="none";c.style.display="none";
  svg.parentNode.insertBefore(c,svg.nextSibling);
  return c;
}
function buildOverlayBitmap(){
  if(!overlayBitmapScroll)return;
  /* A warm that runs before the redraw would bake the previous edges
     under the new epoch and then look up to date. Wait for the redraw. */
  if(overlayDirty){overlayBitmapPending=true;return;}
  const box=overlayBitmapBox();
  if(!box){
    overlayBitmapKey="";
    const stale=document.getElementById("dep-canvas");
    if(stale)stale.style.display="none";
    return;
  }
  const key=overlayBitmapWantedKey();
  if(!key||key===overlayBitmapKey)return;
  if(overlayBitmapBusy){overlayBitmapPending=true;return;}
  const ax=box.x,ay=box.y,aw=box.w,ah=box.h,dpr=box.dpr;
  overlayBitmapBusy=true;overlayBitmapPending=false;
  const token=++overlayBitmapToken;
  const shot=document.createElementNS(SVGNS,"svg");
  shot.setAttribute("xmlns",SVGNS);
  shot.setAttribute("width",String(aw*dpr));
  shot.setAttribute("height",String(ah*dpr));
  shot.setAttribute("viewBox","0 0 "+aw+" "+ah);
  shot.appendChild(makeArrowDefs());
  paintOverlayEdges(shot,ax,ay,aw,ah,false);
  bakeOverlayLook(shot);
  const url=URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(shot)],{type:"image/svg+xml;charset=utf-8"}));
  const img=new Image();
  const finish=function(ok){
    URL.revokeObjectURL(url);
    overlayBitmapBusy=false;
    if(token!==overlayBitmapToken)ok=false;
    if(ok){
      const c=ensureOverlayCanvas();
      c.width=Math.round(aw*dpr);c.height=Math.round(ah*dpr);
      c.style.left=ax+"px";c.style.top=ay+"px";c.style.width=aw+"px";c.style.height=ah+"px";
      const ctx=c.getContext("2d");
      ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,c.width,c.height);ctx.drawImage(img,0,0,c.width,c.height);
      overlayBitmapKey=key;
      c.style.display=overlayHeld?"block":"none";
    }
    if(overlayBitmapPending){overlayBitmapPending=false;buildOverlayBitmap();}
  };
  img.onload=function(){finish(true);};
  img.onerror=function(){finish(false);};
  img.src=url;
}
function scheduleOverlayBitmap(){
  if(!overlayBitmapScroll||overlayHeld)return;
  clearTimeout(overlayBitmapTimer);
  overlayBitmapTimer=setTimeout(()=>{overlayBitmapTimer=0;if(!overlayHeld)buildOverlayBitmap();},80);
}
/* A nudge below this distance keeps the live SVG. Past it, Safari is
   about to repaint the stroke overlay tile by tile, so the gesture
   switches to the bitmap until it has been still for a moment. */
function noteOverlayScroll(){
  const wr=document.getElementById("gantt-wrapper");
  if(!wr)return;
  if(!overlayHeld){
    if(Math.abs(wr.scrollTop-overlayRestTop)<32&&Math.abs(wr.scrollLeft-overlayRestLeft)<32){
      clearTimeout(overlayHoldTimer);
      overlayHoldTimer=setTimeout(()=>{
        overlayHoldTimer=0;
        const w=document.getElementById("gantt-wrapper");
        if(w&&!overlayHeld){overlayRestTop=w.scrollTop;overlayRestLeft=w.scrollLeft;}
      },160);
      return;
    }
    beginOverlayHold();
  }
  clearTimeout(overlayHoldTimer);
  overlayHoldTimer=setTimeout(releaseOverlayScroll,140);
}
function beginOverlayHold(){
  overlayHeld=true;
  const readyKey=overlayBitmapKey&&overlayBitmapKey===overlayBitmapWantedKey();
  const c=document.getElementById("dep-canvas");
  if(readyKey&&c)c.style.display="block";
  const svg=document.getElementById("dep-svg");
  if(svg)svg.style.display="none";
  if(!readyKey)buildOverlayBitmap();
}
function releaseOverlayScroll(){
  overlayHoldTimer=0;overlayHeld=false;
  const wr=document.getElementById("gantt-wrapper");
  const svg=document.getElementById("dep-svg");
  if(overlayDirty||!wr||!overlayCoversViewport(wr))drawOverlays();
  if(svg)svg.style.display="";
  const c=document.getElementById("dep-canvas");
  if(c)c.style.display="none";
  if(wr){overlayRestTop=wr.scrollTop;overlayRestLeft=wr.scrollLeft;}
  scheduleOverlayBitmap();
}
function drawOverlays(){
  if(overlayDirty)buildOverlayModel();
  renderOverlays();
  scheduleOverlayBitmap();
}
function toggleCritMode(btn){
  critMode=!critMode;
  btn.classList.toggle("active",critMode);btn.setAttribute("aria-pressed",critMode);
  document.getElementById("dep-svg").classList.toggle("crit-mode",critMode);
  document.getElementById("gantt").classList.toggle("crit-mode",critMode);
  const tv=document.getElementById("gantt-time");if(tv)tv.classList.toggle("crit-mode",critMode);
  if(!overlayDirty)refreshCritical();
  drawOverlays();
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
  if(p){
    document.querySelectorAll(`#dep-svg [data-pkg="${p}"],#dep-svg [data-from-pkg="${p}"],#dep-svg [data-to-pkg="${p}"]`)
      .forEach(e=>e.classList.add("lit"));
    document.querySelectorAll(`#gantt tr[data-pkg="${p}"],#gantt-time .gantt-time-row[data-pkg="${p}"]`)
      .forEach(r=>r.classList.add("hover-lit"));
  }
  scheduleOverlayBitmap();
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
  markOverlayDirty();
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
  const ruler=document.getElementById("gantt-time-ruler");ruler.replaceChildren();
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
  overlayFrame=requestAnimationFrame(()=>{overlayFrame=0;
    /* A matching bitmap is already scrolling. Re-anchoring the live
       SVG here would rasterize it again, which is the Safari cost. */
    if(overlayHeld){
      if(!overlayBitmapKey||overlayBitmapKey!==overlayBitmapWantedKey())buildOverlayBitmap();
      return;
    }
    const wr=document.getElementById("gantt-wrapper");
    if(overlayDirty||!wr||!overlayCoversViewport(wr))drawOverlays();});
}
window.addEventListener("load",drawOverlays);
if(document.fonts&&document.fonts.ready)document.fonts.ready.then(()=>{markOverlayDirty();scheduleOverlays();});
window.addEventListener("resize",()=>{markOverlayDirty();scheduleOverlays();});
document.getElementById("gantt-wrapper").addEventListener("scroll",()=>{
  if(overlayBitmapScroll)noteOverlayScroll();
  scheduleOverlays();
});

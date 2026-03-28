#!/usr/bin/env python3
"""Generate clean, focused .dot dependency graphs for overlay test cases.

One testNN.dot per test.  Only shows what is relevant to the scenario.

Visual conventions:
  - Entry-point node:  lightcoral fill, white text
  - Normal node:       lightyellow fill, rounded box
  - Missing dep:       dashed border, mistyrose fill
  - Installed (VDB):   lightblue fill
  - Plain edge:        black, solid
  - Blocker:           red dashed, "!!" or "!" label
  - PDEPEND:           dashed, "PDEPEND" label
  - BDEPEND:           dotted, "BDEPEND" label
  - IDEPEND:           dotted, "IDEPEND" label
  - Version constraint: label on edge
  - USE dep:           "[flag]" label on edge
  - USE conditional:   "flag?" label on edge
  - Self-loop:         red
  - Choice group:      diamond node
"""

import re, sys
from pathlib import Path

OVERLAY = Path(__file__).resolve().parent.parent.parent / "Repository" / "Overlay"
CACHE   = OVERLAY / "metadata" / "md5-cache"
OUTDIR  = Path(__file__).resolve().parent

# ─── tokeniser / parser ─────────────────────────────────────────────────────

def tokenize(s):
    toks, i = [], 0
    while i < len(s):
        if s[i] in " \t\n": i += 1; continue
        if s[i] in "()": toks.append(s[i]); i += 1
        else:
            j = i
            while j < len(s) and s[j] not in " \t\n()": j += 1
            toks.append(s[i:j]); i = j
    return toks

def parse(toks, pos=0):
    out = []
    while pos < len(toks):
        t = toks[pos]
        if t == ")": return out, pos+1
        if t in ("||","^^","??"):
            pos += 1
            if pos < len(toks) and toks[pos] == "(":
                pos += 1; ch, pos = parse(toks, pos)
                out.append(("group", t, ch))
            else: out.append(t)
        elif t == "(":
            pos += 1; ch, pos = parse(toks, pos)
            out.append(("group", "all-of", ch))
        elif t.endswith("?") and not t[0] in (">","<","=","~"):
            flag = t[:-1]; neg = flag.startswith("!"); flag = flag.lstrip("!")
            pos += 1
            if pos < len(toks) and toks[pos] == "(":
                pos += 1; ch, pos = parse(toks, pos)
                out.append(("cond", flag, neg, ch))
            else: out.append(t)
        else: out.append(t); pos += 1
    return out, pos

# ─── atom helpers ────────────────────────────────────────────────────────────

def atom_parts(atom):
    a = atom; blocker = ""
    if a.startswith("!!"): blocker = "!!"; a = a[2:]
    elif a.startswith("!"): blocker = "!"; a = a[1:]
    op = ""
    for v in (">=","<=",">","<","=","~"):
        if a.startswith(v): op = v; a = a[len(v):]; break
    use_dep = ""
    if "[" in a: idx = a.index("["); use_dep = a[idx:]; a = a[:idx]
    slot = ""
    if ":" in a: idx = a.index(":"); slot = a[idx:]; a = a[:idx]
    base = a.split("/")[-1] if "/" in a else a
    return blocker, op, base, slot, use_dep

def pkg_base(versioned_name):
    """'app-1.0' -> 'app', 'lib-2.0-r1' -> 'lib'."""
    m = re.match(r'^(.+?)-\d', versioned_name)
    return m.group(1) if m else versioned_name

def safe_id(s):
    return re.sub(r'[^a-zA-Z0-9_]', '_', s)

# ─── per-test metadata ──────────────────────────────────────────────────────

ENTRY_POINTS = {
    "test01":"web-1.0","test02":"web-2.0","test03":"web-1.0","test04":"web-1.0",
    "test05":"web-1.0","test06":"web-1.0","test07":"web-1.0","test08":"web-1.0",
    "test09":"os-1.0","test10":"os-1.0","test11":"os-1.0","test12":"web-1.0",
    "test13":"web-2.0","test14":"web-1.0","test15":"web-1.0","test16":"web-1.0",
    "test17":"web-1.0","test18":"web-1.0","test19":"web-1.0",
    "test20":"web-1.0","test21":"web-1.0","test22":"web-1.0",
    "test23":"web-1.0","test24":"web-1.0","test25":"web-1.0",
    "test26":"web-1.0","test27":"web-1.0","test28":"web-1.0",
    "test29":"web-1.0","test30":"web-1.0","test31":"web-1.0",
    "test32":"os-1.0","test40":"os-1.0",
    "test47":"api-docs-1.0","test51":"app-1.0",
    "test57":"web-1.0","test58":"web-1.0","test59":"web-1.0","test60":"web-1.0",
    "test62":"web-1.0","test71":"web-1.0","test78":"web-1.0",
    "test79":"server-1.0",
}

TITLES = {
    "test01":"Basic dependency ordering","test02":"Version selection (2.0 over 1.0)",
    "test03":"Self-dependency (compile)","test04":"Self-dependency (runtime)",
    "test05":"Self-dependency (compile+runtime)","test06":"Indirect cycle (compile)",
    "test07":"Indirect cycle (runtime)","test08":"Indirect cycle (compile+runtime)",
    "test09":"Missing dep (compile)","test10":"Missing dep (runtime)",
    "test11":"Missing dep (compile+runtime)",
    "test12":"Keywords: stable vs unstable","test13":"Pinpointed version =pkg-ver",
    "test14":"USE conditional lib? ( )","test15":"Negative USE !nolib? ( )",
    "test16":"Explicit all-of group ( )","test17":"Exactly-one-of ^^ (compile)",
    "test18":"Exactly-one-of ^^ (runtime)","test19":"Exactly-one-of ^^ (both)",
    "test20":"Any-of || (compile)","test21":"Any-of || (runtime)",
    "test22":"Any-of || (both)","test23":"At-most-one-of ?? (compile)",
    "test24":"At-most-one-of ?? (runtime)","test25":"At-most-one-of ?? (both)",
    "test26":"Strong blocker !! (runtime)","test27":"Weak blocker ! (runtime)",
    "test28":"Strong blocker !! (compile)","test29":"Strong blocker !! (both)",
    "test30":"Weak blocker ! (compile)","test31":"Weak blocker ! (both)",
    "test32":"REQUIRED_USE ^^","test33":"USE dep [linux]",
    "test34":"USE dep [-linux]","test35":"USE dep [linux=]",
    "test36":"Chained USE [linux=]","test37":"Inverse USE [!linux=]",
    "test38":"Weak USE [linux?]","test39":"Negative weak [-linux?]",
    "test40":"REQUIRED_USE ||","test41":"Slot :1","test42":"Slot :*",
    "test43":"Slot :=","test44":"Sub-slot :1/A",
    "test45":"Irreconcilable USE conflict","test46":"Deep diamond USE conflict",
    "test47":"Three-way cycle","test48":"Slot conflict",
    "test49":"USE default (+) vs REQUIRED_USE","test50":"Transitive RDEPEND",
    "test51":"USE dep vs REQUIRED_USE","test52":"Multi-USE on shared dep",
    "test53":"USE merge + conditional dep","test54":"USE flag expansion",
    "test55":"Version range >3 <6","test56":"Version range via dep chains",
    "test57":"Virtual-style ebuild","test58":"PROVIDE virtual (XFAIL)",
    "test59":"Any-of || regression (XFAIL)","test60":"Versioned blocker (XFAIL)",
    "test61":"Mutual recursion [foo]","test62":"Simple mutual cycle",
    "test63":"REQUIRED_USE loop (openmpi)","test64":"USE-conditional churn (openmp)",
    "test65":"build_with_use reinstall","test66":"PDEPEND (post-merge)",
    "test67":"BDEPEND (build-only)","test68":"Multi-slot co-install",
    "test69":"Version >=","test70":"Version ~ (revision)","test71":"Fetchonly",
    "test72":"IDEPEND (install-time)","test73":"Update (VDB)",
    "test74":"Downgrade (VDB)","test75":"Reinstall / emptytree (VDB)",
    "test76":"Newuse rebuild (VDB)","test77":"Depclean (VDB)",
    "test78":"Onlydeps (skip target)","test79":"PDEPEND cycle",
    "test80":"Version <=",
}

VDB_INSTALLED = {
    "test73": {"lib"}, "test74": {"lib"}, "test75": {"os"},
    "test76": {"os"}, "test77": {"app","os","orphan"},
}

MISSING_BASES = {
    "test09": {"notexists"}, "test10": {"notexists"}, "test11": {"notexists"},
    "test58": {"virtualsdk"},
}

# ─── graph builder ───────────────────────────────────────────────────────────

def read_cache(test):
    entries = {}
    d = CACHE / test
    if not d.is_dir(): return entries
    for f in sorted(d.iterdir()):
        if f.is_file():
            data = {}
            for line in f.read_text().splitlines():
                if "=" in line: k, v = line.split("=", 1); data[k] = v
            entries[f.name] = data
    return entries


def build_graph(test, entries):
    entry = ENTRY_POINTS.get(test)
    if not entry:
        for n in sorted(entries):
            if n.startswith("web-") or n.startswith("app-"):
                entry = n; break
        if not entry and entries: entry = sorted(entries)[0]

    title = TITLES.get(test, test)
    vdb = VDB_INSTALLED.get(test, set())
    miss = MISSING_BASES.get(test, set())

    base_to_versions = {}
    for name in entries:
        b = pkg_base(name)
        base_to_versions.setdefault(b, []).append(name)

    multi_version = {b for b, vs in base_to_versions.items() if len(vs) > 1}

    nodes = {}
    edges = []
    gcounter = [0]

    def ensure_node(versioned_name, base=None):
        if base is None: base = pkg_base(versioned_name)
        use_versioned_id = base in multi_version
        nid = safe_id(versioned_name) if use_versioned_id else safe_id(base)
        if nid not in nodes:
            label = versioned_name if use_versioned_id else versioned_name
            slot = entries.get(versioned_name, {}).get("SLOT", "0")
            if slot not in ("0", "") and base not in multi_version:
                label += f":{slot}"
            style = ""
            if versioned_name == entry:
                style = 'fillcolor=lightcoral,fontcolor=white'
            elif base in vdb:
                style = 'fillcolor=lightblue'
            elif base in miss:
                style = 'style="rounded,dashed,filled",fillcolor=mistyrose'
            nodes[nid] = (label, style)
        return nid

    def resolve_dep(dep_base):
        """Map a dependency base name to the node id(s) it should target."""
        if dep_base in base_to_versions:
            versions = base_to_versions[dep_base]
            if len(versions) == 1:
                return [ensure_node(versions[0], dep_base)]
            else:
                return [ensure_node(v, dep_base) for v in sorted(versions)]
        nid = safe_id(dep_base)
        if nid not in nodes:
            style = ""
            if dep_base in miss:
                style = 'style="rounded,dashed,filled",fillcolor=mistyrose'
            nodes[nid] = (dep_base, style)
        return [nid]

    for vname in sorted(entries):
        ensure_node(vname)

    for mbase in miss:
        nid = safe_id(mbase)
        if nid not in nodes:
            nodes[nid] = (mbase, 'style="rounded,dashed,filled",fillcolor=mistyrose')

    for pkg_name, data in sorted(entries.items()):
        src_base = pkg_base(pkg_name)
        src_nid = safe_id(pkg_name) if src_base in multi_version else safe_id(src_base)

        for field in ("DEPEND","BDEPEND","RDEPEND","PDEPEND","IDEPEND"):
            dep_str = data.get(field, "").strip()
            if not dep_str: continue
            tree, _ = parse(tokenize(dep_str))
            walk(test, src_nid, tree, field, edges, nodes, resolve_dep,
                 gcounter, miss, multi_version, base_to_versions)

    lines = []
    lines.append(f'digraph {test} {{')
    lines.append(f'  label="{test} \\u2014 {title}";')
    lines.append(f'  labelloc=t; fontname=Helvetica; fontsize=12;')
    lines.append(f'  graph [rankdir=LR];')
    lines.append(f'  node  [fontname=Helvetica,fontsize=10,shape=box,'
                 f'style="rounded,filled",fillcolor=lightyellow];')
    lines.append(f'')

    for nid in sorted(nodes):
        label, style = nodes[nid]
        extra = f",{style}" if style else ""
        lines.append(f'  {nid} [label="{label}"{extra}];')

    lines.append(f'')

    seen = set()
    for s, d, attrs in edges:
        key = (s, d, tuple(sorted(attrs.items())))
        if key in seen: continue
        seen.add(key)
        astr = ",".join(f'{k}="{v}"' for k,v in sorted(attrs.items()))
        astr = f" [{astr}]" if astr else ""
        lines.append(f'  {s} -> {d}{astr};')

    lines.append(f'}}')
    return "\n".join(lines)


def walk(test, src, tree, field, edges, nodes, resolve_dep,
         gcounter, miss, multi_version, base_to_versions):
    for node in tree:
        if isinstance(node, str):
            blocker, op, base, slot, use_dep = atom_parts(node)
            attrs = {}

            if blocker:
                attrs["color"] = "red"; attrs["style"] = "dashed"
                attrs["label"] = blocker
            elif field == "PDEPEND":
                attrs["style"] = "dashed"; attrs["label"] = "PDEPEND"
            elif field == "BDEPEND":
                attrs["style"] = "dotted"; attrs["label"] = "BDEPEND"
            elif field == "IDEPEND":
                attrs["style"] = "dotted"; attrs["label"] = "IDEPEND"

            if op and not blocker:
                ver_part = base if op in (">=","<=",">","<","~") else ""
                attrs["label"] = f"{op}{ver_part}"
                base_only = re.match(r'^(.+?)-\d', base)
                if base_only: base = base_only.group(1)

            if use_dep and not blocker:
                lbl = attrs.get("label","")
                attrs["label"] = f"{lbl} {use_dep}".strip() if lbl else use_dep

            if slot and slot not in (":0","") and not blocker:
                lbl = attrs.get("label","")
                attrs["label"] = f"{lbl} {slot}".strip() if lbl else slot

            targets = resolve_dep(base)
            for t in targets:
                ea = dict(attrs)
                if src == t: ea["color"] = ea.get("color", "red")
                edges.append((src, t, ea))

        elif isinstance(node, tuple):
            if node[0] == "group":
                op_sym, children = node[1], node[2]
                gcounter[0] += 1
                gid = f"g{gcounter[0]}"
                nodes[gid] = (op_sym, 'shape=diamond,fillcolor=lightyellow,'
                              'fontsize=9,width=0.4,height=0.4')
                edges.append((src, gid, {}))
                walk(test, gid, children, field, edges, nodes, resolve_dep,
                     gcounter, miss, multi_version, base_to_versions)
            elif node[0] == "cond":
                flag, neg, children = node[1], node[2], node[3]
                pol = "!" if neg else ""
                cond_label = f"{pol}{flag}?"
                walk(test, src, children, field, edges, nodes, resolve_dep,
                     gcounter, miss, multi_version, base_to_versions)
                for child in children:
                    if isinstance(child, str):
                        _, _, cbase, _, _ = atom_parts(child)
                        cb = re.match(r'^(.+?)-\d', cbase)
                        if cb: cbase = cb.group(1)
                        targets = resolve_dep(cbase)
                        for t in targets:
                            for i, (s, d, a) in enumerate(edges):
                                if s == src and d == t and not a:
                                    edges[i] = (s, d, {"label": cond_label})
                                    break


def main():
    tests = sorted(d.name for d in CACHE.iterdir()
                   if d.is_dir() and d.name.startswith("test"))
    print(f"Generating graphs for {len(tests)} tests")
    for test in tests:
        entries = read_cache(test)
        if not entries: print(f"  {test}: skip"); continue
        outdir = OUTDIR / test
        outdir.mkdir(parents=True, exist_ok=True)
        dot = build_graph(test, entries)
        (outdir / f"{test}.dot").write_text(dot)
        print(f"  {test}: {len(entries)} pkgs")
    print("Done")


if __name__ == "__main__":
    main()

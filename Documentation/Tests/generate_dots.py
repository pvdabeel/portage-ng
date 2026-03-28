#!/usr/bin/env python3
"""Generate all 80 test .dot graphs with clean, focused styling.

Style conventions:
  - Title uses HTML label: <B>testNN</B> — description
  - Entry point: lightcoral fill, white text
  - Missing dep: dashed border, mistyrose fill
  - VDB installed: lightblue fill
  - Conditional dep: dashed border on node, dashed edge
  - Group diamonds: || orange, ^^ purple, ?? darkcyan, () gray60
  - Cycle edges: red bold, labeled C / R / C+R
  - Strong blocker: red bold edge, "strong blocker"
  - Soft blocker: red dashed edge, "soft blocker"
  - PDEPEND/BDEPEND/IDEPEND: dashed/dotted with labels
  - Multi-version unversioned deps: cluster per package
"""

from pathlib import Path

OUTDIR = Path(__file__).resolve().parent


# ── style constants ──────────────────────────────────────────────────────────

ENTRY = 'fillcolor=lightcoral,fontcolor=white'
MISS  = 'style="rounded,dashed,filled",fillcolor=mistyrose'
VDB   = 'fillcolor=lightblue'
COND  = 'style="rounded,dashed,filled"'

def diamond(sym, color):
    return (f'shape=diamond,fillcolor={color},'
            f'fontcolor=white,fontsize=11,width=0.5,height=0.5')

OR_D    = diamond("||", "orange")
XOR_D   = diamond("^^", "purple")
ATMOST_D = diamond("??", "darkcyan")
ALLOF_D = diamond("()", "gray60")

CYCLE_C   = 'color=red,style=bold,label="C",fontcolor=red'
CYCLE_R   = 'color=red,style=bold,label="R",fontcolor=red'
CYCLE_CR  = 'color=red,style=bold,label="C+R",fontcolor=red'
STRONG_B  = 'color=red,style=bold,label="strong blocker",fontcolor=red'
SOFT_B    = 'color=red,style=dashed,label="soft blocker",fontcolor=red'
PDEP_E    = 'style=dashed,label="PDEPEND"'
BDEP_E    = 'style=dotted,label="BDEPEND"'
IDEP_E    = 'style=dotted,label="IDEPEND"'


def hdr(test, title, compound=False):
    c = ",compound=true" if compound else ""
    return (f'digraph {test} {{\n'
            f'  label=<<B>{test}</B> \u2014 {title}>;\n'
            f'  labelloc=t; fontname=Helvetica; fontsize=12;\n'
            f'  graph [rankdir=LR{c}];\n'
            f'  node  [fontname=Helvetica,fontsize=10,shape=box,'
            f'style="rounded,filled",fillcolor=lightyellow];\n'
            f'  edge  [fontname=Helvetica,fontsize=9];\n')


def node(nid, label, extra=""):
    e = f",{extra}" if extra else ""
    return f'  {nid} [label="{label}"{e}];'


def edge(src, dst, attrs=""):
    a = f" [{attrs}]" if attrs else ""
    return f'  {src} -> {dst}{a};'


def cluster(name, label, members):
    lines = [f'  subgraph cluster_{name} {{',
             f'    label="{label}"; style=dashed; color=gray;']
    for nid, lbl, extra in members:
        e = f",{extra}" if extra else ""
        lines.append(f'    {nid} [label="{lbl}"{e}];')
    lines.append('  }')
    return "\n".join(lines)


def dot(test, title, nodes, edges_list, clusters_list=None, compound=False,
        rank_min=None, extra_lines=None):
    lines = [hdr(test, title, compound)]
    if clusters_list:
        for c in clusters_list:
            lines.append(c)
        lines.append("")
    for n in nodes:
        lines.append(n)
    if rank_min:
        items = "; ".join(rank_min)
        lines.append(f'  {{rank=min; {items}}}')
    if extra_lines:
        for el in extra_lines:
            lines.append(el)
    lines.append("")
    for e in edges_list:
        lines.append(e)
    lines.append("}")
    return "\n".join(lines)


# ── test graph definitions ───────────────────────────────────────────────────

def test01():
    return dot("test01", "Basic dependency ordering", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
    ])


def test02():
    return dot("test02", "Version selection", [],[
        edge("web_2", "app_1", 'lhead=cluster_app'),
        edge("web_2", "db_1", 'lhead=cluster_db'),
        edge("web_2", "os_1", 'lhead=cluster_os'),
        edge("app_2", "os_1", 'lhead=cluster_os'),
        edge("app_2", "db_1", 'lhead=cluster_db'),
        edge("db_2", "os_1", 'lhead=cluster_os'),
    ], clusters_list=[
        cluster("web", "web", [
            ("web_2", "web-2.0", ENTRY), ("web_1", "web-1.0", ""),
        ]),
        cluster("app", "app", [
            ("app_2", "app-2.0", ""), ("app_1", "app-1.0", ""),
        ]),
        cluster("db", "db", [
            ("db_2", "db-2.0", ""), ("db_1", "db-1.0", ""),
        ]),
        cluster("os", "os", [
            ("os_2", "os-2.0", ""), ("os_1", "os-1.0", ""),
        ]),
    ], compound=True)


def test03():
    return dot("test03", "Self-dependency (compile)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "os", CYCLE_C),
    ])


def test04():
    return dot("test04", "Self-dependency (runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "os", CYCLE_R),
    ])


def test05():
    return dot("test05", "Self-dependency (compile+runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "os", CYCLE_CR),
    ])


def test06():
    return dot("test06", "Indirect cycle (compile)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "web", CYCLE_C),
    ], rank_min=["web"])


def test07():
    return dot("test07", "Indirect cycle (runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "web", CYCLE_R),
    ], rank_min=["web"])


def test08():
    return dot("test08", "Indirect cycle (compile+runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "web", CYCLE_CR),
    ], rank_min=["web"])


def test09():
    return dot("test09", "Missing dep (compile)", [
        node("os", "os-1.0", ENTRY),
        node("notexists", "notexists", MISS),
    ], [
        edge("os", "notexists"),
    ])


def test10():
    return dot("test10", "Missing dep (runtime)", [
        node("os", "os-1.0", ENTRY),
        node("notexists", "notexists", MISS),
    ], [
        edge("os", "notexists"),
    ])


def test11():
    return dot("test11", "Missing dep (compile+runtime)", [
        node("os", "os-1.0", ENTRY),
        node("notexists", "notexists", MISS),
    ], [
        edge("os", "notexists"),
    ])


def test12():
    return dot("test12", "Stable vs unstable keywords", [], [
        edge("web_1", "app_1", 'lhead=cluster_app'),
        edge("web_1", "db_1", 'lhead=cluster_db'),
        edge("web_1", "os_1", 'lhead=cluster_os'),
        edge("app_1", "os_1", 'lhead=cluster_os'),
        edge("app_1", "db_1", 'lhead=cluster_db'),
        edge("db_1", "os_1", 'lhead=cluster_os'),
    ], clusters_list=[
        cluster("web", "web", [
            ("web_1", "web-1.0", ENTRY), ("web_2", "web-2.0", ""),
        ]),
        cluster("app", "app", [
            ("app_1", "app-1.0", ""), ("app_2", "app-2.0", ""),
        ]),
        cluster("db", "db", [
            ("db_1", "db-1.0", ""), ("db_2", "db-2.0", ""),
        ]),
        cluster("os", "os", [
            ("os_1", "os-1.0", ""), ("os_2", "os-2.0 (~kw)", 'fillcolor=wheat'),
        ]),
    ], compound=True)


def test13():
    return dot("test13", "Pinpointed version =pkg-ver", [
        node("web", "web-2.0", ENTRY),
        node("app", "app-2.0"),
        node("db", "db-2.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app", 'label="=app-2.0"'),
        edge("web", "db", 'label="=db-2.0"'),
        edge("web", "os"),
        edge("app", "db", 'label="=db-2.0"'),
        edge("app", "os"),
        edge("db", "os"),
    ])


def test14():
    return dot("test14", "USE conditional lib? ( )", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("lib", "lib-1.0", COND),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "lib", 'style=dashed,label="lib?"'),
        edge("db", "os"),
        edge("lib", "os"),
    ])


def test15():
    return dot("test15", "Negative USE !nolib? ( )", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("lib", "lib-1.0", COND),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "lib", 'style=dashed,label="!nolib?"'),
        edge("db", "os"),
        edge("lib", "os"),
    ])


def test16():
    return dot("test16", "Explicit all-of group ( )", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "()", ALLOF_D),
    ], [
        edge("web", "app"), edge("web", "os"),
        edge("web", "g1"),
        edge("g1", "db"), edge("g1", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
    ])


def test17():
    return dot("test17", "Exactly-one-of ^^ (compile)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "^^", XOR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test18():
    return dot("test18", "Exactly-one-of ^^ (runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "^^", XOR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test19():
    return dot("test19", "Exactly-one-of ^^ (both)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "^^", XOR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test20():
    return dot("test20", "Any-of || (compile)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test21():
    return dot("test21", "Any-of || (runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test22():
    return dot("test22", "Any-of || (both)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test23():
    return dot("test23", "At-most-one-of ?? (compile)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "??", ATMOST_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test24():
    return dot("test24", "At-most-one-of ?? (runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "??", ATMOST_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test25():
    return dot("test25", "At-most-one-of ?? (both)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "??", ATMOST_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test26():
    return dot("test26", "Strong blocker !! (runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "windows", STRONG_B),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test27():
    return dot("test27", "Weak blocker ! (runtime)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "windows", SOFT_B),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test28():
    return dot("test28", "Strong blocker !! (compile)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "windows", STRONG_B),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test29():
    return dot("test29", "Strong blocker !! (both)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "windows", STRONG_B),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test30():
    return dot("test30", "Weak blocker ! (compile)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "windows", SOFT_B),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test31():
    return dot("test31", "Weak blocker ! (both)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("linux", "linux-1.0"),
        node("bsd", "bsd-1.0"),
        node("windows", "windows-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "windows", SOFT_B),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "linux"), edge("g1", "bsd"), edge("g1", "windows"),
    ])


def test32():
    return dot("test32", "REQUIRED_USE ^^", [
        node("os", "os-1.0", ENTRY),
        node("g1", "^^", XOR_D),
        node("linux", "linux", 'style="rounded,filled",fillcolor=lightyellow'),
        node("darwin", "darwin", 'style="rounded,filled",fillcolor=lightyellow'),
    ], [
        edge("os", "g1", 'label="REQUIRED_USE"'),
        edge("g1", "linux"), edge("g1", "darwin"),
    ])


def test33():
    return dot("test33", "USE dep [linux]", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0"),
    ], [
        edge("app", "os", 'label="[linux]"'),
    ])


def test34():
    return dot("test34", "USE dep [-linux]", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0"),
    ], [
        edge("app", "os", 'label="[-linux]"'),
    ])


def test35():
    return dot("test35", "USE dep [linux=]", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0"),
    ], [
        edge("app", "os", 'label="[linux=]"'),
    ])


def test36():
    return dot("test36", "Chained USE [linux=]", [
        node("app", "app-1.0", ENTRY),
        node("lib", "lib-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("app", "lib", 'label="[linux=]"'),
        edge("lib", "os", 'label="[linux=]"'),
    ])


def test37():
    return dot("test37", "Inverse USE [!linux=]", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0"),
    ], [
        edge("app", "os", 'label="[!linux=]"'),
    ])


def test38():
    return dot("test38", "Weak USE [linux?]", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0"),
    ], [
        edge("app", "os", 'label="[linux?]"'),
    ])


def test39():
    return dot("test39", "Negative weak [-linux?]", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0"),
    ], [
        edge("app", "os", 'label="[!linux?]"'),
    ])


def test40():
    return dot("test40", "REQUIRED_USE ||", [
        node("os", "os-1.0", ENTRY),
        node("g1", "||", OR_D),
        node("linux", "linux", 'style="rounded,filled",fillcolor=lightyellow'),
        node("darwin", "darwin", 'style="rounded,filled",fillcolor=lightyellow'),
    ], [
        edge("os", "g1", 'label="REQUIRED_USE"'),
        edge("g1", "linux"), edge("g1", "darwin"),
    ])


def test41():
    return dot("test41", "Slot :1", [
        node("app", "app-1.0", ENTRY),
        node("lib1", "lib-1.0 :1"),
        node("lib2", "lib-2.0 :2"),
    ], [
        edge("app", "lib1", 'label=":1"'),
    ])


def test42():
    return dot("test42", "Slot :*", [
        node("app", "app-1.0", ENTRY),
        node("lib1", "lib-1.0 :1"),
        node("lib2", "lib-2.0 :2"),
    ], [
        edge("app", "lib1", 'label=":*"'),
        edge("app", "lib2", 'label=":*",style=dashed,color=gray'),
    ])


def test43():
    return dot("test43", "Slot :=", [
        node("app", "app-1.0", ENTRY),
        node("lib1", "lib-1.0 :1"),
        node("lib2", "lib-2.0 :2"),
    ], [
        edge("app", "lib1", 'label=":="'),
        edge("app", "lib2", 'label=":=",style=dashed,color=gray'),
    ])


def test44():
    return dot("test44", "Sub-slot :1/A", [
        node("app", "app-1.0", ENTRY),
        node("lib10", "lib-1.0 :1/A"),
        node("lib11", "lib-1.1 :1/B"),
        node("lib20", "lib-2.0 :2/A"),
    ], [
        edge("app", "lib10", 'label=":1/A"'),
    ])


def test45():
    return dot("test45", "Irreconcilable USE conflict", [
        node("app", "app-1.0", ENTRY),
        node("liba", "liba-1.0"),
        node("libb", "libb-1.0"),
        node("os", "os-1.0"),
        node("g1", "^^", XOR_D),
        node("linux", "linux", 'style="rounded,filled"'),
        node("darwin", "darwin", 'style="rounded,filled"'),
    ], [
        edge("app", "liba"), edge("app", "libb"),
        edge("liba", "os", 'label="[linux]"'),
        edge("libb", "os", 'label="[darwin]"'),
        edge("os", "g1", 'label="REQUIRED_USE"'),
        edge("g1", "linux"), edge("g1", "darwin"),
    ])


def test46():
    return dot("test46", "Deep diamond USE conflict", [
        node("app", "app-1.0", ENTRY),
        node("liba", "liba-1.0"),
        node("libb", "libb-1.0"),
        node("libc", "libc-1.0"),
        node("libd", "libd-1.0"),
        node("core", "core-utils-1.0"),
        node("g1", "^^", XOR_D),
        node("fx", "feature_x", 'style="rounded,filled"'),
        node("fy", "feature_y", 'style="rounded,filled"'),
    ], [
        edge("app", "liba"), edge("app", "libb"),
        edge("liba", "libc"), edge("libb", "libd"),
        edge("libc", "core", 'label="[feature_x]"'),
        edge("libd", "core", 'label="[-feature_x]"'),
        edge("core", "g1", 'label="REQUIRED_USE"'),
        edge("g1", "fx"), edge("g1", "fy"),
    ])


def test47():
    return dot("test47", "Three-way cycle", [
        node("apidocs", "api-docs-1.0", ENTRY),
        node("appserver", "app-server-1.0"),
        node("appclient", "app-client-1.0"),
    ], [
        edge("apidocs", "appserver"),
        edge("appserver", "appclient", CYCLE_R),
        edge("appclient", "apidocs", CYCLE_C),
    ])


def test48():
    return dot("test48", "Slot conflict", [
        node("app", "app-1.0", ENTRY),
        node("libgraphics", "libgraphics-1.0"),
        node("libphysics", "libphysics-1.0"),
        node("libmatrix10", "libmatrix-1.0 :1/A"),
        node("libmatrix11", "libmatrix-1.1 :1/B"),
    ], [
        edge("app", "libgraphics"), edge("app", "libphysics"),
        edge("libgraphics", "libmatrix10", 'label="=1.0 :1/A"'),
        edge("libphysics", "libmatrix11", 'label="=1.1 :1/B"'),
    ])


def test49():
    return dot("test49", "USE default (+) vs REQUIRED_USE", [
        node("app", "app-1.0", ENTRY),
        node("libhelper", "libhelper-1.0"),
    ], [
        edge("app", "libhelper", 'label="[feature_z(+)]"'),
    ])


def test50():
    return dot("test50", "Transitive RDEPEND", [
        node("app", "app-1.0", ENTRY),
        node("foo", "foo-1.0"),
        node("bar", "bar-1.0"),
    ], [
        edge("app", "foo"),
        edge("foo", "bar"),
    ])


def test51():
    return dot("test51", "USE dep vs REQUIRED_USE", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0"),
    ], [
        edge("app", "os", 'label="[linux]"'),
    ])


def test52():
    return dot("test52", "Multi-USE on shared dep", [
        node("app", "app-1.0", ENTRY),
        node("liba", "liba-1.0"),
        node("libb", "libb-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("app", "liba"), edge("app", "libb"),
        edge("liba", "os", 'label="[threads]"'),
        edge("libb", "os", 'label="[hardened]"'),
    ])


def test53():
    return dot("test53", "USE merge + conditional dep", [
        node("app", "app-1.0", ENTRY),
        node("liba", "liba-1.0"),
        node("libb", "libb-1.0"),
        node("os", "os-1.0"),
        node("libhardened", "libhardened-1.0", COND),
    ], [
        edge("app", "liba"), edge("app", "libb"),
        edge("liba", "os", 'label="[threads]"'),
        edge("libb", "os", 'label="[hardened]"'),
        edge("os", "libhardened", 'style=dashed,label="hardened?"'),
    ])


def test54():
    return dot("test54", "USE flag expansion", [
        node("app", "app-1.0", ENTRY),
    ], [])


def test55():
    members = []
    for v in range(1, 10):
        fill = 'fillcolor=palegreen' if 3 < v < 7 else ""
        members.append((f"lib{v}", f"lib-{v}.0", fill))
    return dot("test55", "Version range &gt;3 &lt;7", [
        node("app", "app-1.0", ENTRY),
    ], [
        edge("app", "lib4", 'lhead=cluster_lib,label=">3 <7"'),
    ], clusters_list=[
        cluster("lib", "lib", members),
    ], compound=True)


def test56():
    members = []
    for v in range(1, 10):
        fill = 'fillcolor=palegreen' if 3 < v < 7 else ""
        members.append((f"lib{v}", f"lib-{v}.0", fill))
    return dot("test56", "Version range via dep chains", [
        node("app", "app-1.0", ENTRY),
        node("modulea", "modulea-1.0"),
        node("moduleb", "moduleb-1.0"),
    ], [
        edge("app", "modulea"), edge("app", "moduleb"),
        edge("modulea", "lib4", 'lhead=cluster_lib,label=">3"'),
        edge("moduleb", "lib6", 'lhead=cluster_lib,label="<7"'),
    ], clusters_list=[
        cluster("lib", "lib", members),
    ], compound=True)


def test57():
    return dot("test57", "Virtual-style ebuild", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("virtualsdk", "virtualsdk-1.0"),
        node("linux", "linux-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "virtualsdk"),
        edge("virtualsdk", "linux"),
    ])


def test58():
    return dot("test58", "PROVIDE virtual (XFAIL)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("virtualsdk", "virtualsdk", MISS),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "virtualsdk"),
    ])


def test59():
    return dot("test59", "Any-of || regression (XFAIL)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("data_fast", "data_fast-1.0"),
        node("data_best", "data_best-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "data_fast"), edge("g1", "data_best"),
    ])


def test60():
    return dot("test60", "Versioned blocker (XFAIL)", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
        node("g1", "||", OR_D),
        node("windows1", "windows-1.0"),
        node("windows2", "windows-2.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("app", "windows1",
             'color=red,style=bold,label="!<2.0",fontcolor=red'),
        edge("db", "os"),
        edge("os", "g1"),
        edge("g1", "windows1", 'label="=1.0"'),
        edge("g1", "windows2", 'label="=2.0"'),
    ])


def test61():
    return dot("test61", "Mutual recursion [foo]", [
        node("app", "app-1.0", ENTRY),
        node("a", "a-1.0"),
        node("b", "b-1.0"),
    ], [
        edge("app", "a"),
        edge("a", "b", 'color=red,style=bold,label="[foo]",fontcolor=red'),
        edge("b", "a", 'color=red,style=bold,label="[foo]",fontcolor=red'),
    ])


def test62():
    return dot("test62", "Simple mutual cycle", [
        node("web", "web-1.0", ENTRY),
        node("a", "a-1.0"),
        node("b", "b-1.0"),
    ], [
        edge("web", "a"), edge("web", "b"),
        edge("a", "b", CYCLE_R),
        edge("b", "a", CYCLE_R),
    ])


def test63():
    return dot("test63", "REQUIRED_USE loop", [
        node("app", "app-1.0", ENTRY),
        node("mpibash", "mpibash-1.3-r1"),
        node("openmpi", "openmpi-4.1.6-r1"),
    ], [
        edge("app", "mpibash"),
        edge("mpibash", "openmpi"),
    ])


def test64():
    return dot("test64", "USE-conditional churn", [
        node("app", "app-1.0", ENTRY),
        node("openmp", "openmp-1.0"),
        node("python", "python-1.0"),
        node("hwloc", "hwloc-1.0"),
        node("perl", "perl-1.0"),
        node("ninja", "ninja-1.0"),
        node("cmake", "cmake-1.0"),
        node("g1", "||", OR_D),
        node("gpg", "gpg-1.0"),
        node("gnupg", "gnupg-1.0"),
    ], [
        edge("app", "openmp"),
        edge("openmp", "python", 'style=dashed,label="gdb-plugin?"'),
        edge("openmp", "hwloc", 'style=dashed,label="hwloc?"'),
        edge("openmp", "perl", BDEP_E),
        edge("openmp", "ninja", BDEP_E),
        edge("openmp", "cmake", BDEP_E),
        edge("openmp", "g1", 'style=dashed,label="verify-sig?"'),
        edge("g1", "gpg"), edge("g1", "gnupg"),
        edge("python", "openmp", CYCLE_CR),
    ])


def test65():
    return dot("test65", "build_with_use reinstall", [
        node("app", "app-1.0", ENTRY),
    ], [])


def test66():
    return dot("test66", "PDEPEND (post-merge)", [
        node("app", "app-1.0", ENTRY),
        node("lib", "lib-1.0"),
        node("plugin", "plugin-1.0"),
    ], [
        edge("app", "lib"),
        edge("lib", "plugin", PDEP_E),
    ])


def test67():
    return dot("test67", "BDEPEND (build-only)", [
        node("app", "app-1.0", ENTRY),
        node("lib", "lib-1.0"),
        node("toolchain", "toolchain-1.0"),
    ], [
        edge("app", "lib"),
        edge("app", "toolchain", BDEP_E),
    ])


def test68():
    return dot("test68", "Multi-slot co-install", [
        node("app", "app-1.0", ENTRY),
        node("lib1", "lib-1.0 :1"),
        node("lib2", "lib-2.0 :2"),
    ], [
        edge("app", "lib1", 'label=":1"'),
        edge("app", "lib2", 'label=":2"'),
    ])


def test69():
    members = []
    for v in range(1, 6):
        fill = 'fillcolor=palegreen' if v >= 3 else ""
        members.append((f"lib{v}", f"lib-{v}.0", fill))
    return dot("test69", "Version &gt;=", [
        node("app", "app-1.0", ENTRY),
    ], [
        edge("app", "lib3", 'lhead=cluster_lib,label=">=3.0"'),
    ], clusters_list=[
        cluster("lib", "lib", members),
    ], compound=True)


def test70():
    return dot("test70", "Version ~ (revision)", [
        node("app", "app-1.0", ENTRY),
    ], [
        edge("app", "lib20", 'lhead=cluster_lib,label="~2.0"'),
    ], clusters_list=[
        cluster("lib", "lib", [
            ("lib20", "lib-2.0", 'fillcolor=palegreen'),
            ("lib20r1", "lib-2.0-r1", 'fillcolor=palegreen'),
            ("lib30", "lib-3.0", ""),
        ]),
    ], compound=True)


def test71():
    return dot("test71", "Fetchonly", [
        node("web", "web-1.0", ENTRY),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app"), edge("web", "db"), edge("web", "os"),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
    ])


def test72():
    return dot("test72", "IDEPEND (install-time)", [
        node("app", "app-1.0", ENTRY),
        node("installer", "installer-1.0"),
    ], [
        edge("app", "installer", IDEP_E),
    ])


def test73():
    return dot("test73", "Update (VDB)", [
        node("app", "app-1.0", ENTRY),
    ], [
        edge("app", "lib2", 'lhead=cluster_lib,label="newest"'),
    ], clusters_list=[
        cluster("lib", "lib", [
            ("lib1", "lib-1.0", VDB),
            ("lib2", "lib-2.0", ""),
        ]),
    ], compound=True)


def test74():
    return dot("test74", "Downgrade (VDB)", [
        node("app", "app-1.0", ENTRY),
    ], [
        edge("app", "lib1", 'lhead=cluster_lib,label="=lib-1.0"'),
    ], clusters_list=[
        cluster("lib", "lib", [
            ("lib1", "lib-1.0", ""),
            ("lib2", "lib-2.0", VDB),
        ]),
    ], compound=True)


def test75():
    return dot("test75", "Reinstall / emptytree (VDB)", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0", VDB),
    ], [
        edge("app", "os"),
    ])


def test76():
    return dot("test76", "Newuse rebuild (VDB)", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0", VDB),
    ], [
        edge("app", "os", 'label="[linux]"'),
    ])


def test77():
    return dot("test77", "Depclean (VDB)", [
        node("app", "app-1.0", ENTRY),
        node("os", "os-1.0", VDB),
        node("orphan", "orphan-1.0", 'fillcolor=lightsalmon'),
    ], [
        edge("app", "os"),
    ])


def test78():
    return dot("test78", "Onlydeps (skip target)", [
        node("web", "web-1.0", 'fillcolor=lightgray,style="rounded,dashed,filled"'),
        node("app", "app-1.0"),
        node("db", "db-1.0"),
        node("os", "os-1.0"),
    ], [
        edge("web", "app", 'style=dashed'), edge("web", "db", 'style=dashed'),
        edge("web", "os", 'style=dashed'),
        edge("app", "os"), edge("app", "db"),
        edge("db", "os"),
    ])


def test79():
    return dot("test79", "PDEPEND cycle", [
        node("server", "server-1.0", ENTRY),
        node("client", "client-1.0"),
    ], [
        edge("server", "client"),
        edge("client", "server",
             'color=red,style=bold,label="PDEPEND",fontcolor=red'),
    ])


def test80():
    members = []
    for v in range(1, 6):
        fill = 'fillcolor=palegreen' if v <= 3 else ""
        members.append((f"lib{v}", f"lib-{v}.0", fill))
    return dot("test80", "Version &lt;=", [
        node("app", "app-1.0", ENTRY),
    ], [
        edge("app", "lib1", 'lhead=cluster_lib,label="<=3.0"'),
    ], clusters_list=[
        cluster("lib", "lib", members),
    ], compound=True)


# ── main ─────────────────────────────────────────────────────────────────────

TESTS = {f"test{i:02d}": globals()[f"test{i:02d}"]
         for i in range(1, 81)}


def main():
    for name, fn in sorted(TESTS.items()):
        outdir = OUTDIR / name
        outdir.mkdir(parents=True, exist_ok=True)
        content = fn()
        (outdir / f"{name}.dot").write_text(content)
        print(f"  {name}")
    print(f"Generated {len(TESTS)} .dot files")


if __name__ == "__main__":
    main()

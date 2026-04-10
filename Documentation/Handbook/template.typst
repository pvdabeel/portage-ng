// portage-ng handbook template — PMS-inspired layout
// Serif body (Palatino), sans-serif headings (Helvetica Neue), mono code (Menlo)

#let conf(
  title: none,
  subtitle: none,
  authors: (),
  keywords: (),
  date: none,
  lang: "en",
  region: "US",
  abstract-title: none,
  abstract: none,
  thanks: none,
  margin: (left: 20mm, right: 30mm, top: 25mm, bottom: 30mm),
  paper: "a4",
  font: (),
  fontsize: 11pt,
  mathfont: (),
  codefont: (),
  linestretch: 1.0,
  sectionnumbering: "1.1.1",
  pagenumbering: none,
  linkcolor: none,
  citecolor: none,
  filecolor: none,
  cols: 1,
  doc,
) = {

  // ── Page setup ──────────────────────────────────────────────────────────────
  set page(
    paper: paper,
    margin: margin,
    header: context {
      let loc = here()
      let page-nr = counter(page).at(loc).first()
      if page-nr > 1 {
        let elems = query(heading.where(level: 1).before(loc))
        let chapter-title = if elems.len() > 0 {
          let el = elems.last()
          let num = counter(heading).at(el.location())
          [Chapter #num.first(): #el.body]
        }
        set text(size: 9pt, font: "Helvetica Neue")
        grid(
          columns: (1fr, 1fr),
          align(left, chapter-title),
          align(right, [portage-ng]),
        )
        v(2pt)
        line(length: 100%, stroke: 0.4pt + luma(180))
      }
    },
    footer: context {
      let page-nr = counter(page).at(here()).first()
      if page-nr > 1 {
        set text(size: 9pt, font: "Helvetica Neue")
        align(center, str(page-nr))
      }
    },
  )

  // ── Typography ──────────────────────────────────────────────────────────────
  set text(
    font: "Palatino",
    size: fontsize,
    lang: lang,
    region: region,
  )
  set par(
    leading: 0.7em,
    first-line-indent: 0em,
    spacing: 1.2em,
    justify: true,
  )

  // ── Links ───────────────────────────────────────────────────────────────────
  show link: set text(fill: rgb("#1a5276"))

  // ── Headings — sans-serif, numbered ─────────────────────────────────────────
  set heading(numbering: sectionnumbering)

  // Chapter headings (level 1)
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    v(40pt)
    set text(font: "Helvetica Neue", weight: "bold")
    block(below: 20pt)[
      #text(size: 16pt, fill: luma(100))[Chapter #counter(heading).display("1")]
      #v(6pt)
      #text(size: 24pt)[#it.body]
    ]
    v(10pt)
  }

  // Section headings (level 2)
  show heading.where(level: 2): it => {
    v(16pt)
    set text(font: "Helvetica Neue", weight: "bold", size: 15pt)
    block(below: 8pt)[
      #text(fill: luma(80))[#counter(heading).display("1.1")] #h(6pt) #it.body
    ]
    v(4pt)
  }

  // Subsection headings (level 3)
  show heading.where(level: 3): it => {
    v(12pt)
    set text(font: "Helvetica Neue", weight: "bold", size: 12pt)
    block(below: 6pt)[
      #text(fill: luma(80))[#counter(heading).display("1.1.1")] #h(6pt) #it.body
    ]
    v(3pt)
  }

  // Sub-subsection headings (level 4)
  show heading.where(level: 4): it => {
    v(10pt)
    set text(font: "Helvetica Neue", weight: "bold", size: 11pt)
    block(below: 5pt)[#it.body]
    v(2pt)
  }

  // ── Code blocks ─────────────────────────────────────────────────────────────
  show raw.where(block: true): it => {
    set text(font: "Menlo", size: 8.5pt)
    block(
      width: 100%,
      fill: luma(248),
      stroke: 0.5pt + luma(210),
      radius: 2pt,
      inset: (x: 10pt, y: 8pt),
      breakable: true,
      it,
    )
  }

  // Inline code
  show raw.where(block: false): it => {
    set text(font: "Menlo", size: 9pt)
    box(
      fill: luma(245),
      outset: (x: 2pt, y: 3pt),
      radius: 2pt,
      it,
    )
  }

  // ── Tables ──────────────────────────────────────────────────────────────────
  set table(
    inset: 6pt,
    stroke: (x: none, y: 0.5pt + luma(200)),
  )
  show table: set text(size: 10pt)

  // ── Images / Figures ────────────────────────────────────────────────────────
  show image: it => {
    align(center, it)
  }
  set figure(numbering: "1")
  set figure.caption(separator: [ — ])
  show figure.caption: it => {
    v(6pt)
    set text(size: 10pt)
    align(center)[
      *Figure #it.counter.display(it.numbering)#it.separator*#it.body
    ]
    v(10pt)
  }

  // ── Block quotes ────────────────────────────────────────────────────────────
  show quote: it => {
    block(
      inset: (left: 16pt, right: 8pt, y: 6pt),
      stroke: (left: 2pt + luma(180)),
      fill: luma(252),
      it.body,
    )
  }

  // ── Title page ──────────────────────────────────────────────────────────────
  if title != none {
    v(1fr)
    align(center)[
      #text(font: "Helvetica Neue", size: 24pt, weight: "bold")[#title]
    ]
    if subtitle != none {
      v(16pt)
      align(center)[
        #text(font: "Palatino", size: 12pt, fill: luma(80))[#subtitle]
      ]
    }
    v(40pt)
    if authors.len() > 0 {
      let author-names = authors.map(a => a.name)
      align(center)[
        #text(size: 14pt)[#author-names.join(", ")]
      ]
      let emails = authors.filter(a => a.email != "" and a.email != none).map(a => a.email)
      if emails.len() > 0 {
        v(4pt)
        align(center)[
          #text(size: 11pt, fill: luma(100))[#emails.join(", ")]
        ]
      }
    }
    if date != none {
      v(12pt)
      align(center)[
        #text(size: 12pt, fill: luma(100))[#date]
      ]
    }
    v(1fr)
    align(center)[
      #text(size: 10pt, fill: luma(120))[
        Copyright © 2005–2026, Pieter Van den Abeele. All rights reserved.
      ]
    ]
    v(20pt)
    pagebreak()
  }

  // ── Copyright / license page ────────────────────────────────────────────────
  v(1fr)
  align(center)[
    #text(size: 9pt, fill: luma(120))[
      This work is licensed under the Creative Commons \
      Attribution-NonCommercial-ShareAlike 4.0 International License. \
      To view a copy of this license, visit \
      #link("https://creativecommons.org/licenses/by-nc-sa/4.0/")[https://creativecommons.org/licenses/by-nc-sa/4.0/]. \
      \
      No part of this publication may be reproduced, distributed, or transmitted \
      for commercial purposes without the prior written permission of the author.
    ]
  ]
  v(20pt)
  pagebreak()

  // ── Dedication page (uncomment for print edition) ──────────────────────────
  // v(1fr)
  // align(center)[
  //   #text(font: "Palatino", size: 12pt, style: "italic", fill: luma(80))[
  //     In memory of Prof. Em. Dirk Vermeir (1956–2023) \
  //     #v(4pt)
  //     whose guidance and vision shaped this work.
  //   ]
  // ]
  // v(2fr)
  // pagebreak()

  // ── Table of contents ───────────────────────────────────────────────────────
  show outline.entry.where(level: 1): it => {
    v(6pt)
    set text(font: "Helvetica Neue", weight: "bold", size: 11pt)
    link(it.element.location(),
      it.indented(it.prefix(), it.body() + sym.space + box(width: 1fr, it.fill) + sym.space + sym.wj + it.page())
    )
  }
  v(40pt)
  text(font: "Helvetica Neue", size: 24pt, weight: "bold")[Contents]
  v(16pt)
  outline(title: none, depth: 3)

  // ── Body ────────────────────────────────────────────────────────────────────
  doc
}

# Building the handbook

The portage-ng handbook is written as individual Markdown chapters
(`01-doc-introduction.md` through `26-doc-closing.md`) and compiled into
a single PDF using **Pandoc** with the **Typst** PDF engine.

## Prerequisites

- [Pandoc](https://pandoc.org/) >= 3.0
- [Typst](https://typst.app/) (used as the PDF engine)
- Fonts: Palatino, Helvetica Neue, Menlo (available by default on macOS)

## Building the PDF

From anywhere in the repository:

```sh
Documentation/Handbook/Build/build-pdf.sh
```

This produces `Documentation/Handbook/portage-ng-handbook.pdf`.

## How it works

The build pipeline is:

```
Markdown chapters ──> Pandoc ──> Typst ──> PDF
```

1. **Pandoc** reads all 26 chapter Markdown files in order, resolves
   image references from the `Diagrams/` directory, and applies the
   metadata from `metadata.yaml` (title, subtitle, author).

2. Pandoc converts the Markdown to Typst markup using its built-in
   writer, passing `template.typst` as a Typst template variable.

3. **Typst** renders the final PDF with the custom layout defined in
   `template.typst`: Palatino body text, Helvetica Neue headings,
   Menlo code blocks, numbered chapters with running headers, and a
   generated table of contents.

## Files in this directory

| File                  | Purpose                                              |
| --------------------- | ---------------------------------------------------- |
| `build-pdf.sh`        | Shell script that drives the Pandoc build             |
| `template.typst`      | Custom Typst template (page layout, typography, TOC)  |
| `metadata.yaml`       | Pandoc metadata (title, subtitle, author)             |
| `handbook.typ`        | Standalone Typst variant of the template              |
| `handbook_full.typ`   | Pandoc-generated Typst intermediate (full handbook)   |
| `handbook_debug.typ`  | Pandoc-generated Typst intermediate (debug subset)    |
| `handbook_query.typ`  | Pandoc-generated Typst intermediate (query subset)    |

The `handbook_*.typ` files are generated intermediates useful for
debugging Typst layout issues. They can be compiled directly with
`typst compile handbook_full.typ` without going through Pandoc.

## Diagrams

All diagrams live in `Documentation/Handbook/Diagrams/` as Graphviz
`.dot` source files with pre-rendered `.svg` outputs. To regenerate a
diagram after editing its `.dot` source:

```sh
dot -Tsvg Diagrams/09-reprove-loop.dot -o Diagrams/09-reprove-loop.svg
```

Screenshots (`.png` files in `Diagrams/`) are used as-is.

#!/bin/sh
# Build the portage-ng handbook PDF from all chapter markdown files.
# Requires: pandoc (>= 3.0), typst
# Usage: cd Documentation/Handbook && ./build-pdf.sh

set -e

cd "$(dirname "$0")"

OUTFILE="portage-ng-handbook.pdf"

pandoc \
  --pdf-engine=typst \
  -f markdown-citations \
  --template=default \
  -V template="template.typst" \
  -V papersize=a4 \
  -V section-numbering="1.1.1" \
  -V page-numbering="1" \
  --resource-path=. \
  --metadata-file=metadata.yaml \
  -V date="$(date '+%B %Y')" \
  -o "$OUTFILE" \
  01-doc-introduction.md \
  02-doc-installation.md \
  03-doc-gentoo.md \
  04-doc-architecture.md \
  05-doc-proof-literals.md \
  06-doc-knowledgebase.md \
  07-doc-eapi-grammar.md \
  08-doc-prover.md \
  09-doc-prover-assumptions.md \
  10-doc-version-domains.md \
  11-doc-rules.md \
  12-doc-planning.md \
  13-doc-building.md \
  14-doc-cli.md \
  15-doc-output.md \
  16-doc-explainer.md \
  17-doc-tls-certificates.md \
  18-doc-upstream-bugs.md \
  19-doc-contextual-logic-programming.md \
  20-doc-context-terms.md \
  21-doc-resolver-comparison.md \
  22-doc-dependency-ordering.md \
  23-doc-testing.md \
  24-doc-performance.md \
  25-doc-contributing.md \
  26-doc-closing.md

echo "Built $OUTFILE ($(wc -c < "$OUTFILE" | tr -d ' ') bytes)"

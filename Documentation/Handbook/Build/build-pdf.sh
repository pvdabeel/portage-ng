#!/bin/sh
# Build the portage-ng handbook PDF from all chapter markdown files.
# Requires: pandoc (>= 3.0), typst
# Usage: Documentation/Handbook/Build/build-pdf.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HANDBOOK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$HANDBOOK_DIR"

OUTFILE="portage-ng-handbook.pdf"

pandoc \
  --pdf-engine=typst \
  -f markdown-citations \
  --template=default \
  -V template="Build/template.typst" \
  -V papersize=a4 \
  -V section-numbering="1.1.1" \
  -V page-numbering="1" \
  --resource-path=. \
  --metadata-file=Build/metadata.yaml \
  -V date="$(date '+%B %Y')" \
  -o "$OUTFILE" \
  01-doc-introduction.md \
  02-doc-installation.md \
  03-doc-configuration.md \
  04-doc-architecture.md \
  05-doc-proof-literals.md \
  06-doc-knowledgebase.md \
  07-doc-eapi-grammar.md \
  08-doc-prover.md \
  09-doc-prover-assumptions.md \
  10-doc-version-domains.md \
  11-doc-rules.md \
  12-doc-resolution.md \
  13-doc-planning.md \
  14-doc-output.md \
  15-doc-cli.md \
  16-doc-building.md \
  17-doc-llm.md \
  18-doc-distributed.md \
  19-doc-upstream-bugs.md \
  20-doc-glsa.md \
  21-doc-contextual-logic-programming.md \
  22-doc-context-terms.md \
  23-doc-resolver-comparison.md \
  24-doc-dependency-ordering.md \
  25-doc-academic-position.md \
  26-doc-testing.md \
  27-doc-performance.md \
  28-doc-contributing.md \
  29-doc-closing.md

echo "Built $OUTFILE ($(wc -c < "$OUTFILE" | tr -d ' ') bytes)"

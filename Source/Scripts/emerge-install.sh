#!/usr/bin/env bash
# emerge-install.sh — set up a minimal gentoo-prefix for running emerge -vp
#
# Creates ~/gentoo-prefix/ with configuration symlinked from portage-ng,
# so that "emerge -vp <target>" can be used for quick comparison against
# portage-ng output on any machine (Linux or macOS).
#
# Prerequisites:
#   - python3
#   - A local clone of the portage source tree (for bin/emerge + lib/portage)
#   - A local clone of the Gentoo portage tree (gentoo.git or portage-git)
#   - The portage-ng project checked out (for config files)
#
# Usage:
#   ./emerge-install.sh \
#       --portage-src ~/Git/portage \
#       --portage-tree ~/Repository/portage-git \
#       --portage-ng ~/Desktop/Prolog \
#       [--vdb ~/Repository/pkg] \
#       [--prefix ~/gentoo-prefix] \
#       [--profile default/linux/amd64/23.0/split-usr/no-multilib]

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────

PREFIX="$HOME/gentoo-prefix"
PORTAGE_SRC=""
PORTAGE_TREE=""
PORTAGE_NG=""
VDB=""
PROFILE="default/linux/amd64/23.0/split-usr/no-multilib"

# ── Argument parsing ─────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Usage: emerge-install.sh [options]

Required:
  --portage-src DIR     Path to portage source tree (contains bin/emerge)
  --portage-tree DIR    Path to Gentoo portage tree (contains profiles/)
  --portage-ng DIR      Path to portage-ng project (contains Source/Config/Gentoo/)

Optional:
  --vdb DIR             Path to VDB (installed package database); symlinked
                        into the prefix so emerge can see installed packages
  --prefix DIR          Prefix directory (default: ~/gentoo-prefix)
  --profile SUBPATH     Profile relative to profiles/ in the portage tree
                        (default: default/linux/amd64/23.0/split-usr/no-multilib)
  --help                Show this help message
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --portage-src)   PORTAGE_SRC="$2";  shift 2 ;;
        --portage-tree)  PORTAGE_TREE="$2"; shift 2 ;;
        --portage-ng)    PORTAGE_NG="$2";   shift 2 ;;
        --vdb)           VDB="$2";          shift 2 ;;
        --prefix)        PREFIX="$2";       shift 2 ;;
        --profile)       PROFILE="$2";      shift 2 ;;
        --help|-h)       usage 0 ;;
        *)               echo "error: unknown option: $1" >&2; usage 1 ;;
    esac
done

# ── Validation ───────────────────────────────────────────────────────────────

fail() { echo "error: $*" >&2; exit 1; }

[[ -n "$PORTAGE_SRC"  ]] || fail "--portage-src is required"
[[ -n "$PORTAGE_TREE" ]] || fail "--portage-tree is required"
[[ -n "$PORTAGE_NG"   ]] || fail "--portage-ng is required"

[[ -f "$PORTAGE_SRC/bin/emerge" ]]          || fail "$PORTAGE_SRC/bin/emerge not found"
[[ -d "$PORTAGE_TREE/profiles" ]]           || fail "$PORTAGE_TREE/profiles/ not found"
[[ -d "$PORTAGE_NG/Source/Config/Gentoo" ]] || fail "$PORTAGE_NG/Source/Config/Gentoo/ not found"

PROFILE_DIR="$PORTAGE_TREE/profiles/$PROFILE"
[[ -d "$PROFILE_DIR" ]] || fail "Profile not found: $PROFILE_DIR"

if [[ -n "$VDB" ]]; then
    [[ -d "$VDB" ]] || fail "VDB directory not found: $VDB"
fi

# Resolve to absolute paths
PORTAGE_SRC="$(cd "$PORTAGE_SRC" && pwd)"
PORTAGE_TREE="$(cd "$PORTAGE_TREE" && pwd)"
PORTAGE_NG="$(cd "$PORTAGE_NG" && pwd)"
PROFILE_DIR="$(cd "$PROFILE_DIR" && pwd)"
[[ -n "$VDB" ]] && VDB="$(cd "$VDB" && pwd)"

# ── Create directory structure ───────────────────────────────────────────────

echo "Creating prefix at $PREFIX ..."

mkdir -p "$PREFIX/etc/portage"
mkdir -p "$PREFIX/var/lib/portage"
mkdir -p "$PREFIX/var/cache/edb"
mkdir -p "$PREFIX/bin"
mkdir -p "/tmp/portage"

touch "$PREFIX/var/lib/portage/world"

# ── VDB symlink ──────────────────────────────────────────────────────────────

if [[ -n "$VDB" ]]; then
    mkdir -p "$PREFIX/var/db"
    if [[ -e "$PREFIX/var/db/pkg" ]]; then
        echo "  VDB link already exists: $(readlink "$PREFIX/var/db/pkg" 2>/dev/null || echo "$PREFIX/var/db/pkg")"
    else
        ln -s "$VDB" "$PREFIX/var/db/pkg"
        echo "  Linked VDB: $PREFIX/var/db/pkg -> $VDB"
    fi
fi

# ── Profile symlink ──────────────────────────────────────────────────────────

if [[ -L "$PREFIX/etc/portage/make.profile" ]]; then
    echo "  Profile link already exists: $(readlink "$PREFIX/etc/portage/make.profile")"
else
    ln -s "$PROFILE_DIR" "$PREFIX/etc/portage/make.profile"
    echo "  Linked profile: make.profile -> $PROFILE_DIR"
fi

# ── Config symlinks (from portage-ng) ────────────────────────────────────────

GENTOO_CONF="$PORTAGE_NG/Source/Config/Gentoo"

for f in package.use package.mask package.unmask package.accept_keywords package.license; do
    target="$GENTOO_CONF/$f"
    link="$PREFIX/etc/portage/$f"
    if [[ -e "$link" ]]; then
        echo "  $f already exists, skipping"
    elif [[ -e "$target" ]]; then
        ln -s "$target" "$link"
        echo "  Linked $f -> $target"
    else
        echo "  Warning: $target not found, skipping $f"
    fi
done

# ── make.conf (copy, not symlink — may need local overrides) ─────────────────

if [[ -f "$PREFIX/etc/portage/make.conf" ]]; then
    echo "  make.conf already exists, skipping"
else
    if [[ -f "$GENTOO_CONF/make.conf" ]]; then
        cp "$GENTOO_CONF/make.conf" "$PREFIX/etc/portage/make.conf"
        echo "  Copied make.conf from portage-ng config"
    else
        echo "  Warning: $GENTOO_CONF/make.conf not found"
    fi

    # Append FEATURES override for non-Gentoo hosts
    if ! grep -q "FEATURES=" "$PREFIX/etc/portage/make.conf" 2>/dev/null; then
        echo 'FEATURES="-sandbox -usersandbox -userpriv -ipc-sandbox -pid-sandbox -network-sandbox -mount-sandbox"' \
            >> "$PREFIX/etc/portage/make.conf"
    fi
fi

# ── repos.conf ───────────────────────────────────────────────────────────────

if [[ -f "$PREFIX/etc/portage/repos.conf" ]]; then
    echo "  repos.conf already exists, skipping"
else
    cat > "$PREFIX/etc/portage/repos.conf" <<REPOS
[DEFAULT]
main-repo = gentoo

[gentoo]
location = $PORTAGE_TREE
REPOS
    echo "  Created repos.conf (gentoo -> $PORTAGE_TREE)"
fi

# ── sets.conf (copy from portage source) ─────────────────────────────────────

if [[ -f "$PREFIX/etc/portage/sets.conf" ]]; then
    echo "  sets.conf already exists, skipping"
elif [[ -f "$PORTAGE_SRC/cnf/sets/portage.conf" ]]; then
    cp "$PORTAGE_SRC/cnf/sets/portage.conf" "$PREFIX/etc/portage/sets.conf"
    echo "  Copied sets.conf from portage source"
else
    echo "  Warning: $PORTAGE_SRC/cnf/sets/portage.conf not found (sets warning will appear)"
fi

# ── Wrapper scripts ──────────────────────────────────────────────────────────

cat > "$PREFIX/bin/emerge-vp" <<'WRAPPER'
#!/usr/bin/env bash
PREFIX="$(cd "$(dirname "$0")/.." && pwd)"
PORTAGE_DIR="${PORTAGE_DIR:-$(dirname "$(python3 -c "import portage; print(portage.__file__)" 2>/dev/null)")/../../bin}"
if [[ ! -f "$PREFIX/etc/portage/make.conf" ]]; then
    echo "error: $PREFIX missing etc/portage/make.conf" >&2; exit 1
fi
PORTAGE_LIB="$(dirname "$PORTAGE_DIR")/lib"
exec env EPREFIX="$PREFIX" PORTAGE_TMPDIR="${PORTAGE_TMPDIR:-/tmp/portage}" \
    PYTHONPATH="$PORTAGE_LIB${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -c "
import portage.const, os, sys
portage.const.EPREFIX = os.environ['EPREFIX']
from _emerge.main import emerge_main
sys.exit(emerge_main(['-vp'] + sys.argv[1:]) or 0)
" "$@"
WRAPPER

cat > "$PREFIX/bin/emerge-wrapper" <<'WRAPPER'
#!/usr/bin/env bash
PREFIX="$(cd "$(dirname "$0")/.." && pwd)"
PORTAGE_DIR="${PORTAGE_DIR:-$(dirname "$(python3 -c "import portage; print(portage.__file__)" 2>/dev/null)")/../../bin}"
if [[ ! -f "$PREFIX/etc/portage/make.conf" ]]; then
    echo "error: $PREFIX missing etc/portage/make.conf" >&2; exit 1
fi
PORTAGE_LIB="$(dirname "$PORTAGE_DIR")/lib"
exec env EPREFIX="$PREFIX" PORTAGE_TMPDIR="${PORTAGE_TMPDIR:-/tmp/portage}" \
    PYTHONPATH="$PORTAGE_LIB${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -c "
import portage.const, os, sys
portage.const.EPREFIX = os.environ['EPREFIX']
from _emerge.main import emerge_main
sys.exit(emerge_main(sys.argv[1:]) or 0)
" "$@"
WRAPPER

chmod +x "$PREFIX/bin/emerge-vp" "$PREFIX/bin/emerge-wrapper"
echo "  Created wrapper scripts in $PREFIX/bin/"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Setup complete!"
echo ""
echo "Usage:"
echo "  PORTAGE_DIR=$PORTAGE_SRC/bin $PREFIX/bin/emerge-vp <target>"
echo ""
echo "Or add to your shell profile:"
echo "  export PORTAGE_DIR=$PORTAGE_SRC/bin"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
echo ""
echo "Then simply:"
echo "  emerge-vp sys-apps/portage"

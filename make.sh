#/bin/sh

MAKE_DIR="$( dirname "${0}"; printf a )"; MAKE_DIR="${MAKE_DIR%?a}"
cd "${MAKE_DIR}" || exit "$?"

git show master:make.sh | sh -s "$@"

#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"
package_version="dev"
output_directory="${repository_root}/output/pdf/reports"
inputs=()

usage() {
  cat <<'EOF'
Usage: Scripts/run-visual-tests.sh [options] [pdf-or-directory ...]

Options:
  --package-version <version>  Version used in the report filename (default: dev)
  --output-directory <path>    Report archive directory (default: output/pdf/reports)
  --help                       Show this help

When no PDF input is supplied, the script uses .build/pdfmercury-visual-input.
EOF
}

while (($# > 0)); do
  case "$1" in
    --package-version)
      [[ $# -ge 2 ]] || { echo "error: --package-version requires a value" >&2; exit 2; }
      package_version="$2"
      shift 2
      ;;
    --output-directory)
      [[ $# -ge 2 ]] || { echo "error: --output-directory requires a path" >&2; exit 2; }
      output_directory="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --*)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      inputs+=("$1")
      shift
      ;;
  esac
done

if ((${#inputs[@]} == 0)); then
  inputs+=("${repository_root}/.build/pdfmercury-visual-input")
fi

echo "Running PDFMercury tests..."
swift test --package-path "${repository_root}"

echo "Generating visual report..."
swift run --package-path "${repository_root}" pdfmercury-visual-report \
  --package-version "${package_version}" \
  --output-directory "${output_directory}" \
  "${inputs[@]}"

#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"
package_version="dev"
output_directory="${repository_root}/output/pdf/reports"
open_report=true
inputs=()

usage() {
  cat <<'EOF'
Usage: Scripts/run-visual-tests.sh [options] [pdf-or-directory ...]

Options:
  --package-version <version>  Version used in the report filename (default: dev)
  --output-directory <path>    Report archive directory (default: output/pdf/reports)
  --no-open                    Generate the report without opening it
  --help                       Show this help

When no PDF input is supplied, the script creates a fresh input directory under .build.
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
    --no-open)
      open_report=false
      shift
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
  mkdir -p "${repository_root}/.build"
  visual_input_directory="$(mktemp -d "${repository_root}/.build/pdfmercury-visual-input.XXXXXX")"
  export PDFMERCURY_VISUAL_INPUT_DIRECTORY="${visual_input_directory}"
  inputs+=("${visual_input_directory}")
fi

echo "Running PDFMercury tests..."
swift test --package-path "${repository_root}"

echo "Generating visual report..."
report_log="$(swift run --package-path "${repository_root}" pdfmercury-visual-report \
  --package-version "${package_version}" \
  --output-directory "${output_directory}" \
  "${inputs[@]}")"
printf '%s\n' "${report_log}"

report_path="${report_log##*$'\n'}"
report_path="${report_path#Created }"

if [[ "${open_report}" == true ]]; then
  open "${report_path}"
fi

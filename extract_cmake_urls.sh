#!/usr/bin/env bash
# DepthAI artifact downloader (Nix/offline friendly)
# Extracts versions from CMake config files in the checked-out repo
# and downloads artifacts with checksum verification

#set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

OUTPUT_DIR="downloads"
CMAKE_DIR=""
TIMEOUT=300
RETRY_COUNT=5

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] <ACTION>

Actions:
  list-patterns     Show values extracted from Config.cmake files
  generate-links    Generate artifact URLs from extracted versions
  download          Download artifacts (with checksum verification)
  update            Download new artifacts and prune old versions

Options:
  -o, --output-dir DIR   Output directory (default: downloads)
  -c, --cmake-dir DIR    Path to DepthAI checkout (repo root or cmake/)
  -h, --help             Show this help
EOF
}

resolve_cmake_dir() {
  if [[ -z "$CMAKE_DIR" ]]; then
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
      CMAKE_DIR="$(git rev-parse --show-toplevel)"
    else
      CMAKE_DIR="."
    fi
  fi
  if [[ -d "$CMAKE_DIR/cmake" ]]; then
    CMAKE_DIR="$CMAKE_DIR/cmake"
  fi
  if [[ ! -d "$CMAKE_DIR" ]]; then
    echo -e "${RED}CMake dir not found: $CMAKE_DIR${NC}" >&2
    exit 1
  fi
}

create_output_dir() {
  [[ -d "$OUTPUT_DIR" ]] || { mkdir -p "$OUTPUT_DIR"; echo -e "${GREEN}Created: $OUTPUT_DIR${NC}"; }
}

extract_versions() {
  resolve_cmake_dir

  BOOTLOADER_VER=$(grep -E '^[[:space:]]*set\(DEPTHAI_BOOTLOADER_VERSION' \
    "$CMAKE_DIR/Depthai/DepthaiBootloaderConfig.cmake" | tail -n1 | sed -E 's/.*"([^"]+)".*/\1/')

  VISUALIZER_VER=$(grep -E '^[[:space:]]*set\(DEPTHAI_VISUALIZER_COMMIT' \
    "$CMAKE_DIR/Depthai/DepthaiVisualizerConfig.cmake" | tail -n1 | sed -E 's/.*"([^"]+)".*/\1/')

  DEVICE_COMMIT=$(grep -E '^[[:space:]]*set\(DEPTHAI_DEVICE_SIDE_COMMIT' \
    "$CMAKE_DIR/Depthai/DepthaiDeviceSideConfig.cmake" | tail -n1 | sed -E 's/.*"([^"]+)".*/\1/')

  DEVICE_KB_VER=$(grep -E '^[[:space:]]*set\(DEPTHAI_DEVICE_RVC3_VERSION' \
    "$CMAKE_DIR/Depthai/DepthaiDeviceKbConfig.cmake" | tail -n1 | sed -E 's/.*"([^"]+)".*/\1/')

  DEVICE_RVC4_VER=$(grep -E '^[[:space:]]*set\(DEPTHAI_DEVICE_RVC4_VERSION' \
    "$CMAKE_DIR/Depthai/DepthaiDeviceRVC4Config.cmake" | tail -n1 | sed -E 's/.*"([^"]+)".*/\1/')
}

list_patterns() {
  extract_versions
  echo -e "${YELLOW}Extracted versions:${NC}"
  echo "  Bootloader : $BOOTLOADER_VER"
  echo "  Visualizer : $VISUALIZER_VER"
  echo "  Device     : $DEVICE_COMMIT"
  echo "  Device-KB  : $DEVICE_KB_VER"
  echo "  Device-RVC4: $DEVICE_RVC4_VER"
}

generate_links() {
  extract_versions
  local base="https://artifacts.luxonis.com/artifactory"
  [[ -n "$VISUALIZER_VER" ]] && \
    echo "$base/luxonis-depthai-visualizer-local/$VISUALIZER_VER/depthai-visualizer-$VISUALIZER_VER.tar.xz"
  [[ -n "$BOOTLOADER_VER" ]] && \
    echo "$base/luxonis-myriad-release-local/depthai-bootloader/$BOOTLOADER_VER/depthai-bootloader-fwp-$BOOTLOADER_VER.tar.xz"
  [[ -n "$DEVICE_COMMIT" ]] && \
    echo "$base/luxonis-myriad-snapshot-local/depthai-device-side/$DEVICE_COMMIT/depthai-device-fwp-$DEVICE_COMMIT.tar.xz"
  [[ -n "$DEVICE_KB_VER" ]] && \
    echo "$base/luxonis-keembay-snapshot-local/depthai-device-kb/$DEVICE_KB_VER/depthai-device-kb-fwp-$DEVICE_KB_VER.tar.xz"
  [[ -n "$DEVICE_RVC4_VER" ]] && \
    echo "$base/luxonis-rvc4-snapshot-local/depthai-device-rvc4/$DEVICE_RVC4_VER/depthai-device-rvc4-fwp-$DEVICE_RVC4_VER.tar.xz"
}

download_file_with_checksum() {
  local file_url="$1"
  local output_path="$2"
  local checksum_url="${file_url}.sha256"

  echo -e "${BLUE}Downloading: $file_url${NC}"

  local expected=""
  local checksum_tmp="${output_path}.sha256.tmp"

  # Try fetching checksum, but don't exit if missing
  if curl -fsSL --max-time "$TIMEOUT" "$checksum_url" -o "$checksum_tmp"; then
    expected="$(tr -d '\r\n' < "$checksum_tmp")"
    rm -f "$checksum_tmp"
    echo "Expected checksum: $expected"
  else
    echo -e "${YELLOW}Warning: checksum not found at $checksum_url, skipping verification${NC}"
  fi

  local attempt=1
  while (( attempt <= RETRY_COUNT )); do
    echo "Attempt $attempt/$RETRY_COUNT"
    if curl -fL --max-time "$TIMEOUT" "$file_url" -o "$output_path"; then
      if [[ -n "$expected" ]]; then
        local computed
        if command -v sha256sum >/dev/null 2>&1; then
          computed="$(sha256sum "$output_path" | awk '{print $1}')"
        else
          computed="$(shasum -a 256 "$output_path" | awk '{print $1}')"
        fi
        echo "Computed checksum: $computed"
        if [[ "$computed" == "$expected" ]]; then
          echo -e "${GREEN}✓ Verified: $(basename "$output_path")${NC}"
          return 0
        else
          echo -e "${RED}✗ Checksum mismatch: $(basename "$output_path")${NC}"
          rm -f "$output_path"
        fi
      else
        echo -e "${GREEN}✓ Downloaded (no checksum available): $(basename "$output_path")${NC}"
        return 0
      fi
    fi
    ((attempt++)); sleep 2
  done
  return 1
}

download_urls() {
  echo -e "${BLUE}Download functionality:${NC}"
  echo "======================"
  echo ""

  create_output_dir
  local urls; mapfile -t urls < <(generate_links)

  echo "Found ${#urls[@]} files"
  echo ""

  local ok=0 fail=0
  for url in "${urls[@]}"; do
    [[ -z "$url" ]] && continue
    local out="$OUTPUT_DIR/$(basename "$url")"
    if download_file_with_checksum "$url" "$out"; then
      ((ok++))
    else
      ((fail++))
    fi
    echo ""
  done

  echo -e "${GREEN}Download summary:${NC} ok=$ok fail=$fail"
  return 0
}

update_files() {
  create_output_dir
  local urls; mapfile -t urls < <(generate_links)
  echo "Found ${#urls[@]} files"
  local ok=0 fail=0
  for url in "${urls[@]}"; do
    [[ -z "$url" ]] && continue
    local out="$OUTPUT_DIR/$(basename "$url")"
    if download_file_with_checksum "$url" "$out"; then ((ok++)); else ((fail++)); fi
  done
  echo -e "${GREEN}Update summary:${NC} ok=$ok fail=$fail"
}

# ---- CLI parsing ----
ACTION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output-dir) OUTPUT_DIR="$2"; shift 2;;
    -c|--cmake-dir)  CMAKE_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    list-patterns|generate-links|download|update)
      ACTION="$1"; shift;;
    *) echo -e "${RED}Unknown: $1${NC}"; usage; exit 1;;
  esac
done

case "${ACTION:-}" in
  list-patterns) list_patterns;;
  generate-links) generate_links;;
  download) download_urls;;
  update) update_files;;
  *) echo -e "${YELLOW}No action specified${NC}"; usage; exit 1;;
esac


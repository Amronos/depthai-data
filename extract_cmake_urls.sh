#!/usr/bin/env bash
# Shell script to extract download URLs from DepthAI CMake files
# and download them with checksum verification

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
OUTPUT_DIR="downloads"
CMAKE_DIR="."
TIMEOUT=300
RETRY_COUNT=5

usage() {
    echo "Usage: $0 [OPTIONS] [ACTION]"
    echo ""
    echo "Actions:"
    echo "  list-patterns     List URL patterns extracted from CMake files"
    echo "  extract-urls      Extract actual URLs from CMake files"
    echo "  generate-links    Generate links URLs based on patterns"
    echo "  download          Download files from generated links"
    echo "  update            Update files with new downloads and remove old versions"
    echo ""
    echo "Options:"
    echo "  -o, --output-dir DIR    Output directory (default: downloads)"
    echo "  -c, --cmake-dir DIR     Directory containing CMake files (default: current directory)"
    echo "  -h, --help             Show this help message"
}

create_output_dir() {
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
        echo -e "${GREEN}Created output directory: $OUTPUT_DIR${NC}"
    fi
}

extract_base_url() {
    local cmake_file="$1"
    if [[ -f "$cmake_file" ]]; then
        grep -o 'set([^"]*BASE_URL[^"]*"[^"]*"' "$cmake_file" | sed 's/.*"\([^"]*\)".*/\1/' | head -1
    fi
}

extract_repositories() {
    local cmake_file="$1"
    if [[ -f "$cmake_file" ]]; then
        grep -o 'set([^"]*REPO[^"]*"[^"]*"' "$cmake_file" | sed 's/.*"\([^"]*\)".*/\1/'
    fi
}

extract_prefixes() {
    local cmake_file="$1"
    if [[ -f "$cmake_file" ]]; then
        grep -o 'set([^"]*PREFIX[^"]*"[^"]*"' "$cmake_file" | sed 's/.*"\([^"]*\)".*/\1/'
    fi
}

extract_url_patterns() {
    local cmake_file="$1"
    if [[ -f "$cmake_file" ]]; then
        grep -o 'string(CONFIGURE[^"]*"[^"]*"' "$cmake_file" | sed 's/.*"\([^"]*\)".*/\1/'
    fi
}

list_patterns() {
    local cmake_files=(
        "DepthaiVisualizerDownloader.cmake"
        "DepthaiBootloaderDownloader.cmake"
        "DepthaiDownloader.cmake"
        "DepthaiDeviceKbDownloader.cmake"
        "DepthaiDeviceRVC4Downloader.cmake"
    )
    
    for cmake_file in "${cmake_files[@]}"; do
        local full_path="$CMAKE_DIR/$cmake_file"
        if [[ -f "$full_path" ]]; then
            echo ""
            echo -e "${YELLOW}$cmake_file:${NC}"
            
            local base_url=$(extract_base_url "$full_path")
            echo "  Base URL: $base_url"
            
            local repos=$(extract_repositories "$full_path")
            if [[ -n "$repos" ]]; then
                echo "  Repositories:"
                while IFS= read -r repo; do
                    echo "    - $repo"
                done <<< "$repos"
            fi
            
            local prefixes=$(extract_prefixes "$full_path")
            if [[ -n "$prefixes" ]]; then
                echo "  Prefixes:"
                while IFS= read -r prefix; do
                    echo "    - $prefix"
                done <<< "$prefixes"
            fi
            
            local patterns=$(extract_url_patterns "$full_path")
            if [[ -n "$patterns" ]]; then
                echo "  URL Patterns:"
                while IFS= read -r pattern; do
                    echo "    - $pattern"
                done <<< "$patterns"
            fi
        else
            echo -e "${RED}Warning: $cmake_file not found in $CMAKE_DIR${NC}"
        fi
    done
}

extract_urls() {
    local cmake_files=(
        "DepthaiVisualizerDownloader.cmake"
        "DepthaiBootloaderDownloader.cmake"
        "DepthaiDownloader.cmake"
        "DepthaiDeviceKbDownloader.cmake"
        "DepthaiDeviceRVC4Downloader.cmake"
    )
    
    local url_count=0
    
    for cmake_file in "${cmake_files[@]}"; do
        local full_path="$CMAKE_DIR/$cmake_file"
        if [[ -f "$full_path" ]]; then
            echo ""
            echo -e "${YELLOW}Parsing $cmake_file...${NC}"
            
            local base_url=$(extract_base_url "$full_path")
            echo "Found base URL: $base_url"
            
            # Look for DownloadAndChecksum calls
            local download_calls=$(grep -A 3 "DownloadAndChecksum" "$full_path" | grep -o '"[^"]*artifacts\.luxonis\.com[^"]*"' | sed 's/"//g')
            
            if [[ -n "$download_calls" ]]; then
                echo "Found download URLs:"
                while IFS= read -r url; do
                    if [[ -n "$url" ]]; then
                        ((url_count++))
                        echo "  $url_count. $url"
                    fi
                done <<< "$download_calls"
            fi
            
            # Also look for direct URL constructions
            local direct_urls=$(grep -o '"[^"]*artifacts\.luxonis\.com[^"]*"' "$full_path" | sed 's/"//g' | sort -u)
            
            if [[ -n "$direct_urls" ]]; then
                echo "Found direct URL references:"
                while IFS= read -r url; do
                    if [[ -n "$url" && ! "$download_calls" =~ "$url" ]]; then
                        ((url_count++))
                        echo "  $url_count. $url"
                    fi
                done <<< "$direct_urls"
            fi
        else
            echo -e "${RED}Warning: $cmake_file not found in $CMAKE_DIR${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}Total URLs found: $url_count${NC}"
}

get_download_links() {
    local base_url="https://artifacts.luxonis.com/artifactory"
    
    # Read actual values from configuration files
    local visualizer_version="0.12.33"
    local bootloader_version="0.0.26"
    local device_commit="295e327da22431d0def39685e137f8042b1cf627"
    local device_kb_version="0.0.1+462021e2f146d868dfe59cdf9230c3b733bef115"
    local device_rvc4_version="0.0.1+e7a85e047ccf6daa34304632c73aa2199aa6a3bf"
    
    # Return array of URLs (files only, not checksums)
    local urls=(
        "$base_url/luxonis-depthai-visualizer-local/${visualizer_version}/depthai-visualizer-${visualizer_version}.tar.xz"
        "$base_url/luxonis-myriad-release-local/depthai-bootloader/${bootloader_version}/depthai-bootloader-fwp-${bootloader_version}.tar.xz"
        "$base_url/luxonis-myriad-snapshot-local/depthai-device-side/${device_commit}/depthai-device-fwp-${device_commit}.tar.xz"
        "$base_url/luxonis-keembay-snapshot-local/depthai-device-kb/${device_kb_version}/depthai-device-kb-fwp-${device_kb_version}.tar.xz"
        "$base_url/luxonis-rvc4-snapshot-local/depthai-device-rvc4/${device_rvc4_version}/depthai-device-rvc4-fwp-${device_rvc4_version}.tar.xz"
    )
    
    printf '%s\n' "${urls[@]}"
}

generate_links() {
    local base_url="https://artifacts.luxonis.com/artifactory"
    
    # Read actual values from configuration files
    local visualizer_version="0.12.33"
    local bootloader_version="0.0.26"
    local device_commit="295e327da22431d0def39685e137f8042b1cf627"
    local device_kb_version="0.0.1+462021e2f146d868dfe59cdf9230c3b733bef115"
    local device_rvc4_version="0.0.1+e7a85e047ccf6daa34304632c73aa2199aa6a3bf"
    
    echo ""
    echo -e "${YELLOW}DepthaiVisualizerDownloader.cmake links:${NC}"
    echo "  1. $base_url/luxonis-depthai-visualizer-local/${visualizer_version}/depthai-visualizer-${visualizer_version}.tar.xz"
    echo "  2. $base_url/luxonis-depthai-visualizer-local/${visualizer_version}/depthai-visualizer-${visualizer_version}.tar.xz.sha256"
    
    echo ""
    echo -e "${YELLOW}DepthaiBootloaderDownloader.cmake links (release):${NC}"
    echo "  3. $base_url/luxonis-myriad-release-local/depthai-bootloader/${bootloader_version}/depthai-bootloader-fwp-${bootloader_version}.tar.xz"
    echo "  4. $base_url/luxonis-myriad-release-local/depthai-bootloader/${bootloader_version}/depthai-bootloader-fwp-${bootloader_version}.tar.xz.sha256"
    
    echo ""
    echo -e "${YELLOW}DepthaiDownloader.cmake links (snapshot):${NC}"
    echo "  5. $base_url/luxonis-myriad-snapshot-local/depthai-device-side/${device_commit}/depthai-device-fwp-${device_commit}.tar.xz"
    echo "  6. $base_url/luxonis-myriad-snapshot-local/depthai-device-side/${device_commit}/depthai-device-fwp-${device_commit}.tar.xz.sha256"
    
    echo ""
    echo -e "${YELLOW}DepthaiDeviceKbDownloader.cmake links (snapshot):${NC}"
    echo "  7. $base_url/luxonis-keembay-snapshot-local/depthai-device-kb/${device_kb_version}/depthai-device-kb-fwp-${device_kb_version}.tar.xz"
    echo "  8. $base_url/luxonis-keembay-snapshot-local/depthai-device-kb/${device_kb_version}/depthai-device-kb-fwp-${device_kb_version}.tar.xz.sha256"
    
    echo ""
    echo -e "${YELLOW}DepthaiDeviceRVC4Downloader.cmake links (snapshot):${NC}"
    echo "  9. $base_url/luxonis-rvc4-snapshot-local/depthai-device-rvc4/${device_rvc4_version}/depthai-device-rvc4-fwp-${device_rvc4_version}.tar.xz"
    echo "  10. $base_url/luxonis-rvc4-snapshot-local/depthai-device-rvc4/${device_rvc4_version}/depthai-device-rvc4-fwp-${device_rvc4_version}.tar.xz.sha256"
}

download_file_with_checksum() {
    local file_url="$1"
    local checksum_url="$2"
    local output_path="$3"
    
    echo -e "${BLUE}Downloading: $file_url${NC}"
    
    # Download checksum first
    local checksum_file="${output_path}.checksum"
    if ! curl -s --max-time "$TIMEOUT" "$checksum_url" -o "$checksum_file" 2>/dev/null; then
        echo -e "${RED}Failed to download checksum from $checksum_url${NC}"
        return 1
    fi
    
    local expected_checksum=$(cat "$checksum_file" | tr -d '\n\r')
    echo "Expected checksum: $expected_checksum"
    rm -f "$checksum_file"
    
    # Download the actual file with retries
    local attempt=1
    while [[ $attempt -le $RETRY_COUNT ]]; do
        echo "Attempt $attempt/$RETRY_COUNT"
        
        if curl -L --max-time "$TIMEOUT" --connect-timeout 60 "$file_url" -o "$output_path" 2>/dev/null; then
            # Compute checksum
            if command -v sha256sum >/dev/null 2>&1; then
                local computed_checksum=$(sha256sum "$output_path" | cut -d' ' -f1)
            elif command -v shasum >/dev/null 2>&1; then
                local computed_checksum=$(shasum -a 256 "$output_path" | cut -d' ' -f1)
            else
                echo -e "${RED}No SHA256 utility found${NC}"
                return 1
            fi
            
            echo "Computed checksum: $computed_checksum"
            
            # Verify checksum
            if [[ "$computed_checksum" == "$expected_checksum" ]]; then
                echo -e "${GREEN}✓ Checksum verified for $(basename "$output_path")${NC}"
                return 0
            else
                echo -e "${RED}✗ Checksum mismatch for $(basename "$output_path")${NC}"
                rm -f "$output_path"
            fi
        else
            echo -e "${YELLOW}Download attempt $attempt failed${NC}"
        fi
        
        ((attempt++))
        if [[ $attempt -le $RETRY_COUNT ]]; then
            sleep $((2 ** (attempt - 2)))  # Exponential backoff
        fi
    done
    
    return 1
}

is_depthai_file() {
    local filename="$1"
    
    # Check if file matches DepthAI patterns from CMake files
    if [[ "$filename" == depthai-visualizer-*.tar.* ]] || \
       [[ "$filename" == depthai-bootloader-*.tar.* ]] || \
       [[ "$filename" == depthai-bootloader-shared-commit-hash-*.txt ]] || \
       [[ "$filename" == depthai-device-fwp-*.tar.* ]] || \
       [[ "$filename" == depthai-device-kb-*.tar.* ]] || \
       [[ "$filename" == depthai-device-rvc4-*.tar.* ]] || \
       [[ "$filename" == depthai-shared-commit-hash-*.txt ]]; then
        return 0
    fi
    
    return 1
}

get_file_pattern() {
    local filename="$1"
    
    # Extract the base pattern without version/commit
    if [[ "$filename" == depthai-visualizer-*.tar.* ]]; then
        echo "depthai-visualizer"
    elif [[ "$filename" == depthai-bootloader-fwp-*.tar.* ]]; then
        echo "depthai-bootloader-fwp"
    elif [[ "$filename" == depthai-bootloader-shared-commit-hash-*.txt ]]; then
        echo "depthai-bootloader-shared-commit-hash"
    elif [[ "$filename" == depthai-device-fwp-*.tar.* ]]; then
        echo "depthai-device-fwp"
    elif [[ "$filename" == depthai-device-kb-fwp-*.tar.* ]]; then
        echo "depthai-device-kb-fwp"
    elif [[ "$filename" == depthai-device-rvc4-fwp-*.tar.* ]]; then
        echo "depthai-device-rvc4-fwp"
    elif [[ "$filename" == depthai-shared-commit-hash-*.txt ]]; then
        echo "depthai-shared-commit-hash"
    fi
}

download_urls() {
    echo -e "${BLUE}Download functionality:${NC}"
    echo "======================"
    echo ""
    echo -e "${YELLOW}Downloading files from generated links...${NC}"
    
    create_output_dir
    
    local download_count=0
    local failed_count=0
    
    # Get URLs from generate-links function
    local urls
    readarray -t urls < <(get_download_links)
    
    echo "Found ${#urls[@]} files to download"
    echo ""
    
    for url in "${urls[@]}"; do
        if [[ -n "$url" ]]; then
            local filename=$(basename "$url")
            local output_path="$OUTPUT_DIR/$filename"
            local checksum_url="${url}.sha256"
            
            echo -e "${GREEN}Downloading: $filename${NC}"
            
            if download_file_with_checksum "$url" "$checksum_url" "$output_path"; then
                ((download_count++))
            else
                ((failed_count++))
            fi
            echo ""
        fi
    done
    
    echo -e "${GREEN}Download summary:${NC}"
    echo "  Files downloaded: $download_count"
    echo "  Files failed: $failed_count"
    
    if [[ $download_count -gt 0 ]]; then
        echo -e "${GREEN}Download completed!${NC}"
    else
        echo -e "${YELLOW}No files were downloaded.${NC}"
    fi
}

update_files() {
    echo -e "${BLUE}Update functionality:${NC}"
    echo "===================="
    echo ""
    echo -e "${YELLOW}This action downloads new files and removes old versions${NC}"
    echo ""
    
    create_output_dir
    
    local download_count=0
    local removed_count=0
    local failed_count=0
    
    # Get URLs from generate-links function
    local urls
    readarray -t urls < <(get_download_links)
    
    echo "Found ${#urls[@]} files to update"
    echo ""
    
    for url in "${urls[@]}"; do
        if [[ -n "$url" ]]; then
            local new_filename=$(basename "$url")
            local output_path="$OUTPUT_DIR/$new_filename"
            local checksum_url="${url}.sha256"
            local pattern=$(get_file_pattern "$new_filename")
            
            echo -e "${GREEN}Processing: $new_filename${NC}"
            
            # Find and remove old files with the same pattern
            if [[ -n "$pattern" ]]; then
                echo "  Looking for old files matching pattern: $pattern"
                local old_files_found=false
                
                for existing_file in "$OUTPUT_DIR"/*; do
                    if [[ -f "$existing_file" ]]; then
                        local existing_filename=$(basename "$existing_file")
                        local existing_pattern=$(get_file_pattern "$existing_filename")
                        
                        # If same pattern but different filename (different version/commit)
                        if [[ "$existing_pattern" == "$pattern" && "$existing_filename" != "$new_filename" ]]; then
                            echo -e "${YELLOW}  Removing old file: $existing_filename${NC}"
                            rm -f "$existing_file"
                            ((removed_count++))
                            old_files_found=true
                        fi
                    fi
                done
                
                if [[ "$old_files_found" == false ]]; then
                    echo "  No old files found"
                fi
            fi
            
            # Download new file
            echo "  Downloading new version..."
            if download_file_with_checksum "$url" "$checksum_url" "$output_path"; then
                echo -e "${GREEN}  ✓ Successfully updated: $new_filename${NC}"
                ((download_count++))
            else
                echo -e "${RED}  ✗ Failed to update: $new_filename${NC}"
                ((failed_count++))
            fi
            echo ""
        fi
    done
    
    echo -e "${GREEN}Update summary:${NC}"
    echo "  Files downloaded: $download_count"
    echo "  Files failed: $failed_count"
    echo "  Old files removed: $removed_count"
    
    if [[ $download_count -gt 0 ]]; then
        echo -e "${GREEN}Update completed successfully!${NC}"
    else
        echo -e "${YELLOW}No files were updated.${NC}"
    fi
}

ACTION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -c|--cmake-dir)
            CMAKE_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        list-patterns)
            ACTION="list-patterns"
            shift
            ;;
        extract-urls)
            ACTION="extract-urls"
            shift
            ;;
        generate-links)
            ACTION="generate-links"
            shift
            ;;
        download)
            ACTION="download"
            shift
            ;;
        update)
            ACTION="update"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

case $ACTION in
    list-patterns)
        list_patterns
        ;;
    extract-urls)
        extract_urls
        ;;
    generate-links)
        generate_links
        ;;
    download)
        download_urls
        ;;
    update)
        update_files
        ;;
    "")
        echo -e "${YELLOW}No action specified${NC}"
        usage
        exit 1
        ;;
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        usage
        exit 1
        ;;
esac

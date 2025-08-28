#!/bin/bash

# Swift Module Dependency Analyzer
# A convenient wrapper for the Python dependency graph builder

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/build_dependency_graph.py"

# Default values
SUBMODULES_PATH="../SubModules"
OUTPUT_DOT="dependency_graph.dot"
OUTPUT_JSON="dependency_data.json"
NO_EXPORTS=false
GENERATE_IMAGE=false
IMAGE_FORMAT="png"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Swift Module Dependency Analyzer

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --path PATH          Path to SubModules directory (default: ../SubModules)
    -d, --dot FILE           Output DOT file (default: dependency_graph.dot)
    -j, --json FILE          Output JSON file (default: dependency_data.json)
    -n, --no-exports         Skip file exports, only show report
    -g, --generate-image     Generate visual graph image (requires graphviz)
    -f, --format FORMAT      Image format: png, svg, pdf (default: png)
    -h, --help               Show this help message

EXAMPLES:
    $0                                    # Basic analysis with default settings
    $0 -n                                 # Only show report, no file exports
    $0 -g                                 # Generate report + visual graph image
    $0 -p ./MyProject/Modules -g -f svg   # Custom path with SVG output
    $0 --no-exports --path ./SubModules   # Report only with custom path

REQUIREMENTS:
    - Python 3.6+
    - graphviz (optional, for image generation)

To install graphviz:
    macOS:   brew install graphviz
    Ubuntu:  sudo apt-get install graphviz
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--path)
            SUBMODULES_PATH="$2"
            shift 2
            ;;
        -d|--dot)
            OUTPUT_DOT="$2"
            shift 2
            ;;
        -j|--json)
            OUTPUT_JSON="$2"
            shift 2
            ;;
        -n|--no-exports)
            NO_EXPORTS=true
            shift
            ;;
        -g|--generate-image)
            GENERATE_IMAGE=true
            shift
            ;;
        -f|--format)
            IMAGE_FORMAT="$2"
            if [[ ! "$IMAGE_FORMAT" =~ ^(png|svg|pdf)$ ]]; then
                print_colored "$RED" "Error: Invalid image format '$IMAGE_FORMAT'. Use png, svg, or pdf."
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_colored "$RED" "Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
done

# Check if Python script exists
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    print_colored "$RED" "Error: Python script not found at $PYTHON_SCRIPT"
    exit 1
fi

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    print_colored "$RED" "Error: python3 is not installed or not in PATH"
    exit 1
fi

# Check if SubModules path exists
if [[ ! -d "$SUBMODULES_PATH" ]]; then
    print_colored "$RED" "Error: SubModules directory not found at '$SUBMODULES_PATH'"
    print_colored "$YELLOW" "Use -p/--path to specify the correct path"
    exit 1
fi

# Build Python command
PYTHON_CMD=(python3 "$PYTHON_SCRIPT" --submodules-path "$SUBMODULES_PATH")

if [[ "$NO_EXPORTS" == true ]]; then
    PYTHON_CMD+=(--no-exports)
else
    PYTHON_CMD+=(--output-dot "$OUTPUT_DOT" --output-json "$OUTPUT_JSON")
fi

# Run the analysis
print_colored "$BLUE" "🔍 Analyzing Swift module dependencies..."
print_colored "$YELLOW" "SubModules path: $SUBMODULES_PATH"

if "${PYTHON_CMD[@]}"; then
    print_colored "$GREEN" "✅ Analysis completed successfully!"
    
    # Generate visual graph if requested and files were exported
    if [[ "$GENERATE_IMAGE" == true && "$NO_EXPORTS" == false ]]; then
        if command -v dot &> /dev/null; then
            IMAGE_FILE="${OUTPUT_DOT%.*}.${IMAGE_FORMAT}"
            print_colored "$BLUE" "🎨 Generating visual graph: $IMAGE_FILE"
            
            if dot -T"$IMAGE_FORMAT" "$OUTPUT_DOT" -o "$IMAGE_FILE"; then
                print_colored "$GREEN" "✅ Visual graph generated: $IMAGE_FILE"
            else
                print_colored "$RED" "❌ Failed to generate visual graph"
                exit 1
            fi
        else
            print_colored "$RED" "❌ graphviz (dot) not found. Install with: brew install graphviz"
            exit 1
        fi
    fi
    
    # Show summary of generated files
    if [[ "$NO_EXPORTS" == false ]]; then
        echo
        print_colored "$BLUE" "📁 Generated files:"
        [[ -f "$OUTPUT_DOT" ]] && print_colored "$GREEN" "  • $OUTPUT_DOT (GraphViz DOT format)"
        [[ -f "$OUTPUT_JSON" ]] && print_colored "$GREEN" "  • $OUTPUT_JSON (JSON data)"
        if [[ "$GENERATE_IMAGE" == true ]]; then
            IMAGE_FILE="${OUTPUT_DOT%.*}.${IMAGE_FORMAT}"
            [[ -f "$IMAGE_FILE" ]] && print_colored "$GREEN" "  • $IMAGE_FILE (Visual graph)"
        fi
        
        echo
        print_colored "$YELLOW" "💡 Tips:"
        print_colored "$YELLOW" "  • View JSON data: cat $OUTPUT_JSON | jq ."
        print_colored "$YELLOW" "  • Generate PNG: dot -Tpng $OUTPUT_DOT -o graph.png"
        print_colored "$YELLOW" "  • Generate SVG: dot -Tsvg $OUTPUT_DOT -o graph.svg"
    fi
    
else
    print_colored "$RED" "❌ Analysis failed"
    exit 1
fi 
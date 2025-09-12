#!/bin/bash
# Convenience script to check common localizations against English base
# Place this script in the same directory as check_localization_completeness.py

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/check_localization_completeness.py"

# Base paths (adjust these if your project structure is different)
BASE_DIR="/Users/nikstar/Developer/mytonwallet-dev"
MAIN_I18N_DIR="$BASE_DIR/src/i18n"
AIR_I18N_DIR="$BASE_DIR/src/i18n/air"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔍 Localization Completeness Checker"
echo "====================================="
echo

check_localization() {
    local base_file="$1"
    local compare_file="$2"
    local description="$3"

    if [ ! -f "$base_file" ]; then
        echo -e "${RED}❌ Base file not found: $base_file${NC}"
        return 1
    fi

    if [ ! -f "$compare_file" ]; then
        echo -e "${RED}❌ Comparison file not found: $compare_file${NC}"
        return 1
    fi

    echo -e "${BLUE}📋 Checking $description${NC}"
    echo -e "${BLUE}   Base: $(basename "$base_file")${NC}"
    echo -e "${BLUE}   Compare: $(basename "$compare_file")${NC}"
    echo

    if python3 "$SCRIPT_PATH" --base "$base_file" --compare "$compare_file"; then
        echo -e "${GREEN}✅ $description check passed${NC}"
    else
        echo -e "${RED}❌ $description check failed${NC}"
    fi
    echo
}

# Check main localizations
if [ -d "$MAIN_I18N_DIR" ]; then
    echo "🌍 Checking main localizations..."
    echo

    # Check Russian
    if [ -f "$MAIN_I18N_DIR/ru.yaml" ]; then
        check_localization "$MAIN_I18N_DIR/en.yaml" "$MAIN_I18N_DIR/ru.yaml" "Russian (main)"
    fi

    # Add more languages here as they become available
    # check_localization "$MAIN_I18N_DIR/en.yaml" "$MAIN_I18N_DIR/de.yaml" "German (main)"
    # check_localization "$MAIN_I18N_DIR/en.yaml" "$MAIN_I18N_DIR/fr.yaml" "French (main)"
fi

# Check air localizations
if [ -d "$AIR_I18N_DIR" ]; then
    echo "✈️  Checking air localizations..."
    echo

    # Check Russian (air)
    if [ -f "$AIR_I18N_DIR/ru.yaml" ]; then
        check_localization "$AIR_I18N_DIR/en.yaml" "$AIR_I18N_DIR/ru.yaml" "Russian (air)"
    fi
fi

echo "🎯 All localization checks completed!"
echo

echo "📱 Checking Swift localization usage..."
echo
if python3 "$SCRIPT_DIR/find_unused_localization_keys.py" --ios-path "$BASE_DIR"; then
    echo -e "${GREEN}✅ Swift localization check passed${NC}"
else
    echo -e "${RED}❌ Swift localization check failed${NC}"
fi
echo

echo "🎯 All checks completed!"
echo
echo "💡 Tips:"
echo "   - Run localization checks with --verbose for detailed statistics"
echo "   - Run Swift key scan with --verbose to see file counts"
echo "   python3 $SCRIPT_PATH --base <base_file> --compare <compare_file> --verbose"
echo "   python3 $SCRIPT_DIR/find_unused_localization_keys.py --ios-path $BASE_DIR --verbose"

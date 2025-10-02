#!/bin/bash

# Build Script for Scan Organizer Swift

set -e

echo "Building Scan Organizer Swift..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed${NC}"
    exit 1
fi

# Check for Ollama (warning only)
if ! command -v ollama &> /dev/null; then
    echo -e "${YELLOW}Warning: Ollama is not installed. AI features will not work.${NC}"
    echo "Install with: curl -fsSL https://ollama.com/install.sh | sh"
fi

# Parse arguments
BUILD_TYPE="debug"
TARGET="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        --cli)
            TARGET="cli"
            shift
            ;;
        --app)
            TARGET="app"
            shift
            ;;
        --help)
            echo "Usage: ./build.sh [options]"
            echo "Options:"
            echo "  --release    Build in release mode"
            echo "  --cli        Build CLI tool only"
            echo "  --app        Build GUI app only"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Build configuration
if [ "$BUILD_TYPE" == "release" ]; then
    CONFIG="-c release"
    echo -e "${GREEN}Building in RELEASE mode${NC}"
else
    CONFIG=""
    echo -e "${GREEN}Building in DEBUG mode${NC}"
fi

# Clean previous builds
echo "Cleaning previous builds..."
swift package clean

# Build targets
if [ "$TARGET" == "cli" ] || [ "$TARGET" == "all" ]; then
    echo -e "\n${GREEN}Building CLI tool...${NC}"
    swift build $CONFIG --product scan-organizer

    if [ "$BUILD_TYPE" == "release" ]; then
        echo -e "${GREEN}CLI tool built at: .build/release/scan-organizer${NC}"
    else
        echo -e "${GREEN}CLI tool built at: .build/debug/scan-organizer${NC}"
    fi
fi

if [ "$TARGET" == "app" ] || [ "$TARGET" == "all" ]; then
    echo -e "\n${GREEN}Building GUI app...${NC}"

    # Check if we're on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Build the library first
        swift build $CONFIG --product ScanOrganizerCore

        echo -e "${YELLOW}Note: To build the full GUI app, open the project in Xcode${NC}"
        echo "Run: swift package generate-xcodeproj && open *.xcodeproj"
    else
        echo -e "${YELLOW}GUI app can only be built on macOS${NC}"
    fi
fi

# Run tests
echo -e "\n${GREEN}Running tests...${NC}"
swift test || echo -e "${YELLOW}Some tests failed${NC}"

# Check Ollama models
if command -v ollama &> /dev/null; then
    echo -e "\n${GREEN}Checking Ollama models...${NC}"

    # Check for vision models
    if ollama list | grep -q "llama3.2-vision\|llava"; then
        echo -e "${GREEN}✓ Vision model found${NC}"
    else
        echo -e "${YELLOW}No vision model found. Install with:${NC}"
        echo "  ollama pull llama3.2-vision:latest"
    fi

    # Check for text models
    if ollama list | grep -q "llama3.2:3b"; then
        echo -e "${GREEN}✓ Text model found${NC}"
    else
        echo -e "${YELLOW}No text model found. Install with:${NC}"
        echo "  ollama pull llama3.2:3b"
    fi
fi

echo -e "\n${GREEN}Build complete!${NC}"

# Show next steps
echo -e "\n${GREEN}Next steps:${NC}"
echo "1. Run CLI: swift run scan-organizer --help"
echo "2. Process a PDF: swift run scan-organizer process document.pdf"
echo "3. Open GUI: swift run ScanOrganizerApp (macOS only)"

# Create symlink for easier access (optional)
if [ "$BUILD_TYPE" == "release" ] && [ "$TARGET" != "app" ]; then
    echo -e "\n${YELLOW}To install CLI tool system-wide:${NC}"
    echo "  sudo cp .build/release/scan-organizer /usr/local/bin/"
fi
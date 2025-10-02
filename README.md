# Scan Organizer

Swift-based macOS application for intelligent PDF document processing with OCR, AI-powered classification, and automatic organization.

## Features

### Core Functionality
- **Intelligent OCR**: Compares Apple Vision OCR with existing PDF text, selects best quality
- **AI-Powered Classification**: Uses local Ollama models for document analysis
  - Vision AI (granite3.2-vision:2b) for image-based document type detection
  - Text AI (granite3.3:2b) for structured data extraction
- **Automatic Organization**: Files documents in structured directories with smart naming
- **Multi-Language Support**: Handles German and English documents
- **Real-time Processing**: Queue-based system with live progress updates

### Finder Integration
- **Quick Actions**: Right-click PDF in Finder → Services → "Process with Scan Organizer"
- **Drag & Drop**: Drop PDFs onto app window or dock icon
- **URL Scheme**: `scanorganizer://process?files=/path/to/file.pdf`
- **Queue File**: Monitor `~/Library/Application Support/ScanOrganizer/queue.txt`

### User Interface
- **Split View**: Queue list (1/3) + Processing details (2/3)
- **Live Logging**: Real-time display of OCR text, AI prompts and responses
- **Resource Monitor**: CPU, Memory, GPU, and Neural Engine usage
- **Expandable Log Entries**: Click to view full AI responses and extracted text
- **Reminders Integration**: Optional notification creation after processing

## Architecture

### Processing Pipeline

```
PDF Input
  ↓
1. OCR Extraction (Apple Vision + PDF embedded text comparison)
  ↓
2. Image Generation (First page as PNG, 2x scale)
  ↓
3. Vision AI Analysis (Document type, language detection)
  ↓
4. Text AI Processing (Structured data extraction: date, title, type)
  ↓
5. File Organization (Auto-rename and move to ~/Documents/ScanOrganizer/Year/Type/)
  ↓
Processing Complete
```

### Technology Stack
- **Language**: Swift 5.9+
- **Frameworks**: SwiftUI, PDFKit, Vision, AppKit
- **AI Models**: Ollama (granite3.2-vision:2b, granite3.3:2b)
- **Storage**: Core Data (via SQLite.swift)
- **Minimum macOS**: 14.0 (Sonoma)

## Installation

### Via Homebrew (Recommended)

```bash
# Add tap
brew tap jonaskern-dev/tap

# Install app
brew install --cask scan-organizer

# Install Ollama and models
brew install ollama
ollama pull granite3.2-vision:2b
ollama pull granite3.3:2b
```

The Homebrew cask will:
- Install app to `/Applications/Scan Organizer.app`
- Set up Finder Quick Action integration
- Configure URL scheme handler

### Manual Installation

#### Prerequisites
1. **Ollama**: Install and pull required models
```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull granite3.2-vision:2b
ollama pull granite3.3:2b
```

#### Install Steps
```bash
# Clone repository
git clone https://github.com/jonaskern-dev/scan-organizer.git
cd scan-organizer

# Run installation script
./install.sh
```

This will:
- Check Ollama installation and models
- Build CLI tool and install to `~/.local/bin`
- Create default directories
- Set up PATH if needed

#### GUI App Installation
```bash
# Build and install app bundle
./create-app-bundle.sh
```

## Usage

### GUI App
```bash
# Open app
open ~/Applications/Scan\ Organizer.app

# Or via command line
./scripts/run-gui.sh
```

#### Adding PDFs to Queue
1. **Drag & Drop**: Drop PDFs directly onto app window
2. **Finder Service**: Right-click PDF → Services → "Process with Scan Organizer"
3. **Command + O**: Use file picker to select PDFs
4. **URL Scheme**: `open "scanorganizer://process?files=/path/to/file.pdf"`

### CLI Tool
```bash
# Process single PDF
scan-organizer process document.pdf

# Process multiple files
scan-organizer process file1.pdf file2.pdf file3.pdf

# Watch directory for new PDFs
scan-organizer watch ~/Downloads/ScannerInbox

# Show help
scan-organizer --help
```

### Configuration

#### AI Prompts
Settings → Configure AI prompts for:
- Vision AI (image analysis)
- Text AI (data extraction)

Placeholders available:
- `{OCR_TEXT}` - Extracted text from document
- `{LANGUAGE}` - Detected language
- `{VISION_DESCRIPTION}` - Vision AI analysis result
- `{FILE_DATE}` - File modification date
- `{SCHEMA}` - JSON schema for response

#### Output Directory
Default: `~/Documents/ScanOrganizer/`

Structure:
```
ScanOrganizer/
├── 2025/
│   ├── Invoice/
│   │   └── 2025-01-15_Invoice_CompanyName.pdf
│   ├── Receipt/
│   │   └── 2025-01-20_Receipt_StoreName.pdf
│   └── Contract/
│       └── 2025-02-01_Contract_Description.pdf
```

## Development

### Project Structure
```
scan-organizer/
├── Sources/
│   ├── App/              # GUI application (SwiftUI)
│   ├── AppIntents/       # Finder Quick Action integration
│   ├── CLI/              # Command-line interface
│   └── Core/             # Shared business logic
│       ├── Models/       # Domain models
│       ├── Queue/        # Processing queue system
│       ├── Services/     # Core services (OCR, AI, File org)
│       └── Extensions/   # Swift extensions
├── Tests/                # Unit tests
├── Package.swift         # Swift Package Manager config
└── Scripts/              # Build and installation scripts
```

### Building

```bash
# Build debug
swift build

# Build release
swift build -c release

# Run tests
swift test

# Build app bundle
./create-app-bundle.sh
```

### Key Components

- **ProcessingQueue**: Queue management with auto-processing
- **PDFProcessor**: Main processing pipeline coordinator
- **OCRService**: Apple Vision Framework integration
- **OCRComparisonService**: Quality comparison between OCR sources
- **AIClassifier**: Ollama API integration (Vision + Text models)
- **FileOrganizer**: File system operations and organization
- **NotificationService**: macOS notification and Reminders integration

## Development

### Building from Source
```bash
# Clone repository
git clone https://github.com/jonaskern-dev/scan-organizer.git
cd scan-organizer

# Build
swift build -c release

# Run tests
swift test

# Create app bundle
./create-app-bundle.sh
```

### Configuration
- AI prompts: Configurable via Settings
- Output directory: `~/Documents/ScanOrganizer/`
- Queue file: `~/Library/Application Support/ScanOrganizer/queue.txt`

### Documentation
- [docs/SYSTEM_OVERVIEW.md](docs/SYSTEM_OVERVIEW.md) - Architecture and processing pipeline

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.9+
- Ollama with models:
  - granite3.2-vision:2b
  - granite3.3:2b

## License

See LICENSE file for details.

## Version

Current version: 1.1.0

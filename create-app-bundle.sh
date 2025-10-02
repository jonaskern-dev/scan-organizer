#!/bin/bash

set -e

echo "Creating Scan Organizer App Bundle..."

# Clean build
echo "Performing clean build..."
swift package clean

# Build release version
echo "Building release version..."
swift build -c release --product ScanOrganizerApp

# Create app bundle structure
APP_NAME="Scan Organizer.app"
APP_DIR="$HOME/Applications/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Remove old app if exists
if [ -d "$APP_DIR" ]; then
    echo "Removing old app..."
    rm -rf "$APP_DIR"
fi

# Create directories
echo "Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
echo "Copying executable..."
cp .build/release/ScanOrganizerApp "$MACOS_DIR/ScanOrganizer"

# Create Info.plist
echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ScanOrganizer</string>
    <key>CFBundleIdentifier</key>
    <string>com.jonaskern.scanorganizer.dev</string>
    <key>CFBundleName</key>
    <string>Scan Organizer (Dev)</string>
    <key>CFBundleDisplayName</key>
    <string>Scan Organizer (Dev)</string>
    <key>CFBundleVersion</key>
    <string>1.1.5</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.5</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>

    <!-- URL Scheme Registration for Finder Integration -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.scanorganizer.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>scanorganizer</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
        </dict>
    </array>

    <!-- Document Types for PDF handling -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>pdf</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>

    <!-- Services Menu Entry for Finder Context Menu -->
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Process with Scan Organizer</string>
            </dict>
            <key>NSMessage</key>
            <string>processFiles</string>
            <key>NSPortName</key>
            <string>Scan Organizer</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSFilenamesPboardType</string>
                <string>public.file-url</string>
            </array>
            <key>NSSendFileTypes</key>
            <array>
                <string>pdf</string>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>

    <!-- App Intents Support -->
    <key>NSSupportsAppIntents</key>
    <true/>

    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSRemindersUsageDescription</key>
    <string>Scan Organizer needs access to Reminders to create alerts when documents are processed.</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
EOF

# Create launcher script
echo "Creating launcher script..."
cat > "$MACOS_DIR/launcher.sh" << 'EOF'
#!/bin/bash

# Get the directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Queue file for dropped PDFs
QUEUE_DIR="$HOME/Library/Application Support/ScanOrganizer"
QUEUE_FILE="$QUEUE_DIR/queue.txt"
LOCK_FILE="$QUEUE_DIR/app.lock"

# Create queue directory if needed
mkdir -p "$QUEUE_DIR"

# Check if app is already running
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if ps -p $PID > /dev/null 2>&1; then
        # App is running, just add to queue
        for file in "$@"; do
            if [[ "$file" == *.pdf ]]; then
                echo "$file" >> "$QUEUE_FILE"
            fi
        done
        exit 0
    else
        # Stale lock file
        rm "$LOCK_FILE"
    fi
fi

# Create lock file with our PID
echo $$ > "$LOCK_FILE"

# Handle dropped files
for file in "$@"; do
    if [[ "$file" == *.pdf ]]; then
        echo "$file" >> "$QUEUE_FILE"
    fi
done

# Start the actual app
"$DIR/ScanOrganizer" "$QUEUE_FILE" &

# Clean up lock file on exit
trap "rm -f '$LOCK_FILE'" EXIT
EOF

chmod +x "$MACOS_DIR/launcher.sh"

# Copy icon from assets
echo "Copying icon..."
ICON_SOURCE="assets/ScanOrganizer.icns"
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
    echo "Icon copied successfully"
else
    echo "Warning: Icon not found at $ICON_SOURCE"
    exit 1
fi

echo "App bundle created at: $APP_DIR"

# Register app with Launch Services for URL scheme and Services
echo ""
echo "Registering app with macOS..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"

# Flush Services cache to make it immediately available
echo "Flushing Services cache..."
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

# Start app once to register Services provider
echo "Starting app to register Services..."
open "$APP_DIR"
sleep 2

echo ""
echo "Installation complete!"
echo ""
echo "The app accepts PDF drops and processes them in a queue."
echo "You can now:"
echo "  1. Drag PDFs onto the app icon in ~/Applications/"
echo "  2. Right-click PDF in Finder -> Services -> 'Process with Scan Organizer'"
echo "  3. Use URL scheme: open 'scanorganizer://process?files=/path/to/file.pdf'"
echo ""
echo "Note: Services menu may take a few seconds to appear. If not visible, restart Finder:"
echo "  killall Finder"
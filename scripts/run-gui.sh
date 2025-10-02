#!/bin/bash

# Run the GUI app directly with Swift

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Starting Scan Organizer GUI...${NC}"

# Check if we need to build first
if [ ! -f ".build/debug/ScanOrganizerCore" ]; then
    echo -e "${YELLOW}Building project...${NC}"
    swift build
fi

# Since we can't directly run a SwiftUI app from SPM, we need to create a simple launcher
echo -e "${YELLOW}Creating GUI launcher...${NC}"

# Create a temporary Swift file for the GUI
cat > .build/run-gui.swift << 'EOF'
import SwiftUI
import ScanOrganizerCore

@main
struct ScanOrganizerGUI: App {
    @StateObject private var queue = ProcessingQueue()

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Scan Organizer").font(.largeTitle).padding()

                VStack(alignment: .leading, spacing: 20) {
                    Text("Queue Status:")
                        .font(.headline)

                    Text("Items: \(queue.items.count)")
                    Text("Pending: \(queue.pendingItems.count)")
                    Text("Completed: \(queue.completedItems.count)")

                    HStack {
                        Button("Add Files...") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.pdf]
                            panel.allowsMultipleSelection = true
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false

                            if panel.runModal() == .OK {
                                queue.addFiles(panel.urls)
                            }
                        }

                        Button("Start Processing") {
                            queue.startProcessing()
                        }
                        .disabled(queue.isProcessing || queue.pendingItems.isEmpty)

                        Button("Stop") {
                            queue.stopProcessing()
                        }
                        .disabled(!queue.isProcessing)
                    }
                }
                .padding()

                // Simple queue list
                List {
                    ForEach(queue.items) { item in
                        HStack {
                            Text(item.fileName)
                            Spacer()
                            Text(statusText(for: item.status))
                                .foregroundColor(statusColor(for: item.status))
                        }
                    }
                }
                .frame(minHeight: 300)
            }
            .frame(minWidth: 600, minHeight: 400)
            .padding()
        }
    }

    func statusText(for status: QueueItemStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    func statusColor(for status: QueueItemStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}
EOF

# Try to compile and run the GUI
echo -e "${GREEN}Launching GUI...${NC}"
swift run --package-path . 2>&1 | grep -v "warning:" || {
    echo -e "${RED}GUI launch failed${NC}"
    echo -e "${YELLOW}Alternative: Opening project in Xcode...${NC}"

    # Open in Xcode as fallback
    open Package.swift

    echo ""
    echo -e "${YELLOW}In Xcode:${NC}"
    echo "1. Wait for packages to resolve"
    echo "2. Select 'My Mac' as run destination"
    echo "3. Click the Run button (▶) or press Cmd+R"
    echo ""
    echo -e "${GREEN}The GUI app will open in Xcode for you to run${NC}"
}
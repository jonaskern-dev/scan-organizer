import SwiftUI

struct CustomSplitView<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    @State private var splitPosition: CGFloat
    @State private var isDragging = false

    private let minLeftWidth: CGFloat = 250
    private let maxLeftWidth: CGFloat = 600
    private let dividerWidth: CGFloat = 1

    init(
        initialSplitRatio: CGFloat = 0.33,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.left = left()
        self.right = right()

        // Load saved position or use default
        let savedPosition = UserDefaults.standard.double(forKey: "QueueSplitPosition")
        self._splitPosition = State(initialValue: savedPosition > 0 ? CGFloat(savedPosition) : initialSplitRatio)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left panel
                left
                    .frame(width: leftWidth(in: geometry.size))

                // Divider
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: dividerWidth)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                let newPosition = (leftWidth(in: geometry.size) + value.translation.width) / geometry.size.width
                                splitPosition = min(max(newPosition, minLeftWidth / geometry.size.width), maxLeftWidth / geometry.size.width)
                            }
                            .onEnded { _ in
                                isDragging = false
                                // Save position
                                UserDefaults.standard.set(splitPosition, forKey: "QueueSplitPosition")
                            }
                    )

                // Right panel
                right
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func leftWidth(in size: CGSize) -> CGFloat {
        let width = size.width * splitPosition
        return min(max(width, minLeftWidth), maxLeftWidth)
    }
}
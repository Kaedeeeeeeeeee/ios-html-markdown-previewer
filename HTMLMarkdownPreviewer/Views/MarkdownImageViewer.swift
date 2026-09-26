import SwiftUI

/// A local-only image reader. Zooming never mutates the imported document.
struct MarkdownImageViewer: View {
    let image: UIImage
    let caption: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var viewport = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var translation = CGSize.zero

    private var fittedSize: CGSize {
        MarkdownImageZoomGeometry.fittedSize(image: image.size, viewport: viewport)
    }

    private var displayedScale: CGFloat {
        MarkdownImageZoomGeometry.normalizedScale(scale * magnification)
    }

    private var displayedOffset: CGSize {
        let proposed = CGSize(width: offset.width + translation.width, height: offset.height + translation.height)
        return MarkdownImageZoomGeometry.clampedOffset(
            proposed, fittedSize: fittedSize, viewport: viewport, scale: displayedScale
        )
    }

    private var percentage: String { "\(Int((displayedScale * 100).rounded()))%" }

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(displayedScale)
                .offset(displayedOffset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipped()
                .gesture(zoomGesture.simultaneously(with: dragGesture))
                .onTapGesture(count: 2) {
                    changeScale(to: scale > 1 ? 1 : 2.5)
                }
                .accessibilityLabel(caption.isEmpty ? AppStrings.Accessibility.markdownImage : caption)
                .accessibilityValue(percentage)
                .accessibilityHint(AppearanceStrings.imageZoomHint)
                .accessibilityIdentifier("markdown-image-viewer")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: changeScale(to: scale + 0.5)
                    case .decrement: changeScale(to: scale - 0.5)
                    @unknown default: break
                    }
                }
                .onChange(of: geometry.size, initial: true) { _, newSize in
                    viewport = newSize
                    offset = MarkdownImageZoomGeometry.clampedOffset(
                        offset, fittedSize: fittedSize, viewport: newSize, scale: scale
                    )
                }
        }
        .background(Color.black)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppearanceStrings.closeImage)
                .accessibilityIdentifier("markdown-image-close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.black)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 14) {
                if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityIdentifier("markdown-image-caption")
                }
                HStack(spacing: 4) {
                    zoomButton(symbol: "minus.magnifyingglass", label: AppearanceStrings.zoomOut,
                               identifier: "markdown-image-zoom-out", disabled: scale <= 1) {
                        changeScale(to: scale - 0.5)
                    }
                    Button { changeScale(to: 1) } label: {
                        Text(percentage)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 70, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppearanceStrings.resetImageZoom)
                    .accessibilityValue(percentage)
                    .accessibilityIdentifier("markdown-image-zoom-reset")
                    zoomButton(symbol: "plus.magnifyingglass", label: AppearanceStrings.zoomIn,
                               identifier: "markdown-image-zoom-in", disabled: scale >= 5) {
                        changeScale(to: scale + 0.5)
                    }
                }
                .padding(.horizontal, 8)
                .background(.regularMaterial, in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { value in
                scale = MarkdownImageZoomGeometry.normalizedScale(scale * value.magnification)
                offset = MarkdownImageZoomGeometry.clampedOffset(
                    offset, fittedSize: fittedSize, viewport: viewport, scale: scale
                )
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($translation) { value, state, _ in
                if scale > 1 { state = value.translation }
            }
            .onEnded { value in
                guard scale > 1 else { return }
                offset = MarkdownImageZoomGeometry.clampedOffset(
                    CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                    fittedSize: fittedSize, viewport: viewport, scale: scale
                )
            }
    }

    private func zoomButton(
        symbol: String, label: String, identifier: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func changeScale(to newScale: CGFloat) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            scale = MarkdownImageZoomGeometry.normalizedScale(newScale)
            offset = MarkdownImageZoomGeometry.clampedOffset(
                offset, fittedSize: fittedSize, viewport: viewport, scale: scale
            )
        }
    }
}

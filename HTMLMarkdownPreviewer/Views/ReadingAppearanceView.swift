import SwiftUI

struct ReadingAppearanceView: View {
    let isHTML: Bool
    @Binding var htmlZoom: Double
    @Binding var fontScale: Double
    @Binding var lineSpacing: Double
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title3) private var previewFontSize = 22.0

    var body: some View {
        NavigationStack {
            Form {
                if isHTML {
                    Section {
                        adjustment(title: AppearanceStrings.pageZoom,
                                   value: $htmlZoom, range: ReadingAppearance.htmlZoomRange,
                                   step: 0.25, defaultValue: ReadingAppearance.defaultHTMLZoom,
                                   identifier: "html-zoom",
                                   decreaseLabel: AppearanceStrings.decreasePageZoom,
                                   increaseLabel: AppearanceStrings.increasePageZoom)
                    }
                } else {
                    Section {
                        adjustment(title: AppearanceStrings.fontSize,
                                   value: $fontScale, range: ReadingAppearance.fontScaleRange,
                                   step: 0.1, defaultValue: ReadingAppearance.defaultFontScale,
                                   identifier: "markdown-font",
                                   decreaseLabel: AppearanceStrings.decreaseFontSize,
                                   increaseLabel: AppearanceStrings.increaseFontSize)
                        adjustment(title: AppearanceStrings.lineSpacing,
                                   value: $lineSpacing, range: ReadingAppearance.lineSpacingRange,
                                   step: 2, defaultValue: ReadingAppearance.defaultLineSpacing,
                                   identifier: "markdown-spacing",
                                   decreaseLabel: AppearanceStrings.decreaseLineSpacing,
                                   increaseLabel: AppearanceStrings.increaseLineSpacing,
                                   isPercentage: false)
                    }
                    Section(AppearanceStrings.preview) {
                        Text("Aa · 文 · あ\n123 — Abc")
                            .font(.system(size: previewFontSize * ReadingAppearance.normalizedFontScale(fontScale)))
                            .lineSpacing(ReadingAppearance.normalizedLineSpacing(lineSpacing))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .accessibilityHidden(true)
                    }
                }
                Section {
                    Button(AppearanceStrings.reset) {
                        if isHTML {
                            htmlZoom = ReadingAppearance.defaultHTMLZoom
                        } else {
                            fontScale = ReadingAppearance.defaultFontScale
                            lineSpacing = ReadingAppearance.defaultLineSpacing
                        }
                    }
                    .accessibilityIdentifier("reading-appearance-reset")
                } footer: {
                    Text(AppearanceStrings.savedDefaults)
                }
            }
            .navigationTitle(AppearanceStrings.appearance)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppearanceStrings.done) { dismiss() }
                        .accessibilityIdentifier("reading-appearance-done")
                }
            }
        }
        .presentationDetents(isHTML ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }

    private func adjustment(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                            step: Double, defaultValue: Double, identifier: String,
                            decreaseLabel: String, increaseLabel: String,
                            isPercentage: Bool = true) -> some View {
        let current = value.wrappedValue.isFinite
            ? min(range.upperBound, max(range.lowerBound, value.wrappedValue)) : defaultValue
        let label = isPercentage ? "\(Int((current * 100).rounded()))%" : "\(Int(current.rounded()))"
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                adjustmentButton(label: decreaseLabel, image: "minus", identifier: "\(identifier)-out",
                                 disabled: current <= range.lowerBound + 0.001) {
                    value.wrappedValue = max(range.lowerBound, (current - step).rounded(toPlaces: 2))
                }
                Spacer(minLength: 16)
                Text(label)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .accessibilityLabel(title)
                    .accessibilityValue(label)
                    .accessibilityIdentifier("\(identifier)-value")
                Spacer(minLength: 16)
                adjustmentButton(label: increaseLabel, image: "plus", identifier: "\(identifier)-in",
                                 disabled: current >= range.upperBound - 0.001) {
                    value.wrappedValue = min(range.upperBound, (current + step).rounded(toPlaces: 2))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func adjustmentButton(label: String, image: String, identifier: String,
                                  disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: image)
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 52, height: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}

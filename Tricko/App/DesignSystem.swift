import SwiftUI
import UIKit

// Tricko — "the close-up table". Velvet-dark stage, candle-gold accent, ivory card
// surfaces. Native code supplies layout, text, fills and touch handling; every
// pictorial mark (glyphs, illustrations and plates) is an original raster
// asset in Assets.xcassets.
enum TrickoStyle {
    static let background = Color(red: 0.071, green: 0.059, blue: 0.110)    // #120F1C velvet black
    static let surface = Color(red: 0.114, green: 0.094, blue: 0.188)       // #1D1830
    static let raised = Color(red: 0.165, green: 0.137, blue: 0.259)        // #2A2342
    static let accent = Color(red: 0.910, green: 0.765, blue: 0.455)        // #E8C374 candle gold
    static let ink = Color(red: 0.102, green: 0.078, blue: 0.141)           // #1A1424 text on gold/ivory
    static let secondary = Color(red: 0.655, green: 0.624, blue: 0.722)     // #A79FB8
    static let paper = Color(red: 0.957, green: 0.929, blue: 0.878)         // #F4EDE0 card ivory
    static let paperSecondary = Color(red: 0.357, green: 0.314, blue: 0.408) // #5B5068 on ivory
    static let cardRed = Color(red: 0.761, green: 0.255, blue: 0.294)       // #C2414B pips, emphasis
    static let line = Color.white.opacity(0.10)
    static let danger = Color(red: 1, green: 0.612, blue: 0.561)            // #FF9C8F
    static let radius: CGFloat = 16
}

// MARK: - Original raster illustrations

struct StagePhoto: View {
    let asset: String

    var body: some View {
        TrickoStyle.surface.overlay {
            Image(asset).resizable().interpolation(.high).scaledToFill()
        }.clipped()
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct StagePage<Header: View, Content: View>: View {
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.dynamicTypeSize) private var typeSize
    private let asset: String
    private let minHeight: CGFloat
    private let maxHeight: CGFloat
    private let topAligned: Bool
    private let header: (CGFloat) -> Header
    private let content: Content

    init(asset: String, minHeight: CGFloat, maxHeight: CGFloat = 372, topAligned: Bool = false,
         @ViewBuilder header: @escaping (CGFloat) -> Header, @ViewBuilder content: () -> Content) {
        self.asset = asset
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.topAligned = topAligned
        self.header = header
        self.content = content()
    }

    var body: some View {
        GeometryReader { viewport in
            let availableHeight = viewport.size.height
            let portraitHeight = max(minHeight, min(availableHeight * 0.46, maxHeight))
            let height = min(heightClass == .compact ? minHeight : portraitHeight,
                             availableHeight * (typeSize.isAccessibilitySize ? 0.45 : 0.68))
            ScrollView {
                VStack(spacing: 0) {
                    header(height).trickoPage().foregroundStyle(TrickoStyle.paper)
                        .frame(minHeight: height, alignment: topAligned ? .top : .bottom)
                    content.trickoPage().foregroundStyle(TrickoStyle.paper)
                        .background { TrickoStyle.background }
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
            .clipped()
            .background(alignment: .top) {
                backdrop
                    .frame(height: height + viewport.safeAreaInsets.top)
                    .padding(.top, -viewport.safeAreaInsets.top)
                    .ignoresSafeArea(.container, edges: .horizontal)
            }
        }.trickoScreenBackground()
    }

    private var backdrop: some View {
        StagePhoto(asset: asset)
            .overlay {
                LinearGradient(stops: [
                    .init(color: TrickoStyle.background.opacity(0.74), location: 0),
                    .init(color: .clear, location: 0.32),
                    .init(color: .clear, location: 0.50),
                    .init(color: TrickoStyle.background.opacity(0.86), location: 0.88),
                    .init(color: TrickoStyle.background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct StageSheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LocalizedText(title).font(.stage(.largeTitle, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button(action: close) {
                Glyph(symbol: .close, size: 16, tint: TrickoStyle.paper)
                    .frame(width: 44, height: 44)
                    .trickoGlass(in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey("Close"))
        }
    }
}

/// Editorial plates for the guide and tools (square, full-bleed).
struct ScenePlate: View {
    enum Subject: String {
        case handling = "PlateHandling"
        case misdirection = "PlateMisdirection"
        case patter = "PlatePatter"
        case practice = "PlatePractice"
        case ethics = "PlateEthics"
        case review = "PlateReview"
        case speed = "PlateSpeed"
        case frame = "PlateFrame"
        case audio = "PlateAudio"

        var asset: String { rawValue }
    }
    let subject: Subject
    var body: some View {
        StagePhoto(asset: subject.asset)
    }
}

// MARK: - Glyphs (original single-colour PNGs rendered as templates)

enum TrickoGlyph: String, CaseIterable {
    case home, feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, mute, folder, settings
    case saved, more, exit
    var asset: String { "Glyph" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
struct Glyph: View {
    @Environment(\.layoutDirection) private var direction
    let symbol: TrickoGlyph
    var size: CGFloat = 25
    var tint: Color = .white
    var body: some View {
        Image(symbol.asset).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .scaleEffect(x: symbol == .back && direction == .rightToLeft ? -1 : 1, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct IconButton: View {
    let symbol: TrickoGlyph
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Glyph(symbol: symbol, size: 20).frame(width: 44, height: 44)
                .background {
                    if selected { StageSurface(tone: .velvet) }
                }
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey(label))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Surfaces and buttons

/// Native fills. Tones: gold (primary), velvet (dark control), ivory (card),
/// smoke (quiet panel), ink (dark control on ivory), mist (muted control on ivory).
struct StageSurface: View {
    enum Tone { case gold, velvet, ivory, smoke, ink, mist }
    let tone: Tone
    var radius: CGFloat = TrickoStyle.radius
    var border: Color? = nil
    private var fill: Color {
        switch tone {
        case .gold: TrickoStyle.accent
        case .velvet: TrickoStyle.raised
        case .ivory: TrickoStyle.paper
        case .smoke: TrickoStyle.surface
        case .ink: TrickoStyle.ink
        case .mist: TrickoStyle.ink.opacity(0.10)
        }
    }
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            .overlay {
                if let stroke = border ?? (tone == .velvet || tone == .smoke ? TrickoStyle.line : nil) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PressStyle: ButtonStyle {
    var disabledOpacity: Double = 0.55
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(!isEnabled ? disabledOpacity : (configuration.isPressed ? 0.7 : 1))
    }
}
// Compact controls retain their full localized label; enclosing layouts can scroll
// or use ViewThatFits instead of splitting words into multiple lines.
struct CompactActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.stage(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(TrickoStyle.paper)
            .background { StageSurface(tone: .velvet, radius: 22) }
            .contentShape(.interaction, Rectangle())
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
    }
}
struct ActionButton: View {
    let title: String
    var primary = true
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            LocalizedText(busy ? "Please wait…" : title).font(.stage(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(primary ? TrickoStyle.ink : TrickoStyle.paper)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background { StageSurface(tone: primary ? .gold : .velvet, radius: 12) }
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).disabled(busy)
    }
}
struct MessagePanel: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText(title).font(.stage(.headline)).foregroundStyle(TrickoStyle.paper)
            LocalizedText(message).font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { ActionButton(title: actionTitle, primary: false, action: action) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background { StageSurface(tone: .smoke, radius: 22) }
    }
}
struct ErrorNote: View {
    @Environment(\.locale) private var locale
    let message: String
    var onPaper = false
    var body: some View {
        LocalizedText(message).font(.stage(.subheadline))
            .foregroundStyle(onPaper ? TrickoStyle.paperSecondary : TrickoStyle.danger)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityLabel(Text(verbatim: L10n.display("Error: \(message)", language: AppLanguage.from(locale))))
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.stage(.subheadline)).foregroundStyle(TrickoStyle.paper).padding(14)
            .background(TrickoStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .tint(TrickoStyle.accent)
    }
}

// MARK: - Keyboard

// Measure in the owning screen, so scrolling, keyboard avoidance and resizing
// keep the input exclusion region aligned. No global window or focus broadcast.
private struct KeyboardInputBounds: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $0.union($1) })
    }
}
private struct OutsideInputTap: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let scope: String
    @State private var inputBounds: CGRect?
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle()) // Hit area only, no visible artwork.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(scope)).onEnded { tap in
                guard focus.wrappedValue, let inputBounds, !inputBounds.contains(tap.location) else { return }
                focus.wrappedValue = false
            })
            .onPreferenceChange(KeyboardInputBounds.self) { inputBounds = $0[scope] }
            .coordinateSpace(name: scope)
    }
}

extension View {
    func keyboardInputRegion(_ scope: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: KeyboardInputBounds.self,
                                       value: [scope: geometry.frame(in: .named(scope))])
            }.allowsHitTesting(false)
        }
    }
    func dismissKeyboardOnOutsideTap(_ focus: FocusState<Bool>.Binding, scope: String) -> some View {
        modifier(OutsideInputTap(focus: focus, scope: scope))
    }
    func trickoField() -> some View { modifier(FieldStyle()) }

    @ViewBuilder
    func trickoGlass(in shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(TrickoStyle.line).allowsHitTesting(false).accessibilityHidden(true) }
        }
    }

    // Only the backdrop extends past the container insets. Foreground controls
    // retain the camera, bar and keyboard layout supplied by their host.
    func trickoScreenBackground(_ color: Color = TrickoStyle.background) -> some View {
        background { color.ignoresSafeArea(.container) }
            .trickoImmersiveChrome()
    }

    @ViewBuilder
    func trickoImmersiveChrome() -> some View {
        if #available(iOS 27.0, *) {
            toolbarVisibility(.hidden, for: .statusBar).persistentSystemOverlays(.hidden)
        } else {
            statusBarHidden(true).persistentSystemOverlays(.hidden)
        }
    }

    // A readable column follows the available container (outer or inner display,
    // split view) without resetting page state.
    func trickoPage() -> some View {
        pageHorizontalMargins().padding(.top, 12).padding(.bottom, 20)
            .frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .top)
    }
    @ViewBuilder
    func pageHorizontalMargins() -> some View {
        if #available(iOS 27.1, *) {
            contentMargins(for: .container, edges: .horizontal)
        } else {
            padding(.horizontal, 20)
        }
    }
}

// MARK: - Shared building blocks

struct MediaCover: View {
    let url: URL?
    var folder = false
    var body: some View {
        TrickoStyle.raised.overlay {
            GeometryReader { geometry in
                Group {
                    if folder { Glyph(symbol: .folder, size: 28, tint: TrickoStyle.secondary) }
                    else if let url {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Glyph(symbol: .feed, size: 28, tint: TrickoStyle.secondary) }
                        }
                    } else { Glyph(symbol: .feed, size: 28, tint: TrickoStyle.secondary) }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }.clipped()
    }
}
struct SheetHeading: View {
    let title: String
    var close: () -> Void
    var body: some View {
        HStack {
            LocalizedText(title).font(.stage(.title3, display: true)).lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            IconButton(symbol: .close, label: "Close", action: close)
        }.pageHorizontalMargins().padding(.top, 8)
    }
}

struct SectionLabel: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText(title).font(.stage(.title3, display: true))
                Spacer(minLength: 12)
                if let detail { LocalizedText(detail).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(title).font(.stage(.title3, display: true))
                if let detail { LocalizedText(detail).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityAddTraits(.isHeader)
    }
}

// Original raster artwork. Its layout never participates in navigation hit testing.
struct TrickoIllustration: View {
    let name: String
    var height: CGFloat = 180
    var body: some View {
        Image(name)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FeatureRow: View {
    let symbol: TrickoGlyph
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 16) {
            Glyph(symbol: symbol, size: 22, tint: TrickoStyle.accent)
                .frame(width: 48, height: 48)
                .background(TrickoStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(title).font(.stage(.subheadline, weight: .semibold)).foregroundStyle(TrickoStyle.paper)
                LocalizedText(detail).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct QuietActionStyle: ButtonStyle {
    var onPaper = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.stage(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(onPaper ? TrickoStyle.ink : TrickoStyle.paper)
            .background { StageSurface(tone: onPaper ? .mist : .velvet, radius: 22) }
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.75 : 1))
    }
}

/// Horizontal segmented chips. Selection is shown by fill and by the selected trait.
struct StageFilter: View {
    let values: [String]
    let selected: String
    let select: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { select(value) } label: {
                        LocalizedText(value).font(.stage(.footnote, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected == value ? TrickoStyle.ink : TrickoStyle.paper)
                            .background { StageSurface(tone: selected == value ? .gold : .velvet, radius: 22) }
                            .contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                        .accessibilityAddTraits(selected == value ? .isSelected : [])
                }
            }
        }
    }
}

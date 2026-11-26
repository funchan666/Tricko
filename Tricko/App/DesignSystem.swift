import SwiftUI
import UIKit

enum TrickoStyle {
    static let background = Color(red: 0.051, green: 0.081, blue: 0.091)
    static let surface = Color(red: 0.086, green: 0.129, blue: 0.141)
    static let raised = Color(red: 0.125, green: 0.194, blue: 0.204)
    static let accent = Color(red: 0.969, green: 0.795, blue: 0.575)
    static let coolAccent = Color(red: 0.620, green: 0.820, blue: 0.800)
    static let ink = Color(red: 0.065, green: 0.105, blue: 0.106)
    static let secondary = Color(red: 0.647, green: 0.724, blue: 0.728)
    static let paper = Color(red: 0.975, green: 0.947, blue: 0.892)
    static let paperSecondary = Color(red: 0.293, green: 0.348, blue: 0.348)
    static let cardRed = Color(red: 0.761, green: 0.255, blue: 0.294)
    static let line = Color.white.opacity(0.10)
    static let danger = Color(red: 1, green: 0.612, blue: 0.561)
    static let radius: CGFloat = 16
}


struct StagePhoto: View {
    let asset: String
    var alignment: Alignment = .center

    var body: some View {
        TrickoStyle.surface.overlay(alignment: alignment) {
            Image(asset).resizable().interpolation(.high).scaledToFill()
        }.clipped()
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct StageSheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LocalizedText(title).font(.stage(.title2, weight: .bold))
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

struct StageFloatingPanel<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StageSheetHeader(title: title, close: close)
                    content
                }
                .padding(22)
                .frame(maxWidth: 460, alignment: .leading)
                .trickoGlass(in: .rect(cornerRadius: 28), tint: TrickoStyle.ink.opacity(0.68),
                             fallback: TrickoStyle.surface, interactive: false)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { Color.black.opacity(0.56).ignoresSafeArea() }
        .foregroundStyle(TrickoStyle.paper)
        .accessibilityAction(.escape, close)
        .trickoImmersiveChrome()
    }
}

enum TrickoGlyph: String, CaseIterable {
    case feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, folder, settings
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
    @Environment(\.locale) private var locale
    let symbol: TrickoGlyph
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Glyph(symbol: symbol, size: 18, tint: selected ? TrickoStyle.accent : TrickoStyle.paper)
                .frame(width: 44, height: 44)
                .trickoGlass(in: Circle(), tint: selected ? TrickoStyle.accent.opacity(0.20) : nil)
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel(Text(verbatim: L10n.text(label, language: AppLanguage.from(locale))))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}


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
struct CompactActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.stage(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(TrickoStyle.paper)
            .trickoGlass(in: Capsule())
            .contentShape(.interaction, Rectangle())
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
    }
}
struct ActionButton: View {
    let title: String
    var primary = true
    var busy = false
    var busyTitle = "Please wait…"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { StageActivityMark(size: 18) }
                LocalizedText(busy ? busyTitle : title)
            }
                .font(.stage(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(primary ? TrickoStyle.accent : TrickoStyle.paper)
                .frame(maxWidth: .infinity, minHeight: 50)
                .trickoGlass(in: .rect(cornerRadius: 16),
                             tint: primary ? TrickoStyle.accent.opacity(0.24) : nil,
                             fallback: primary ? TrickoStyle.raised : TrickoStyle.surface)
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle(disabledOpacity: busy ? 1 : 0.55)).disabled(busy)
    }
}

struct StageActivityMark: View {
    var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
            let stroke = StrokeStyle(lineWidth: max(2, size * 0.10), lineCap: .round)
            ZStack {
                Circle().stroke(TrickoStyle.coolAccent.opacity(0.22), style: stroke)
                Circle().trim(from: 0, to: 0.68)
                    .stroke(AngularGradient(colors: [TrickoStyle.coolAccent.opacity(0.30), TrickoStyle.coolAccent, TrickoStyle.accent],
                                            center: .center, startAngle: .zero, endAngle: .degrees(245)), style: stroke)
                    .rotationEffect(.degrees(reduceMotion ? -90 : cycle * 360))
            }
            .padding(stroke.lineWidth / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct StageLoadingIndicator: View {
    let title: String
    var compact = false

    var body: some View {
        let layout = compact ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            StageActivityMark(size: compact ? 18 : 32)
            LocalizedText(title)
                .font(.stage(compact ? .footnote : .subheadline, weight: .semibold))
                .foregroundStyle(TrickoStyle.paper)
                .multilineTextAlignment(compact ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, compact ? 14 : 22)
        .padding(.vertical, compact ? 9 : 18)
        .trickoGlass(in: .rect(cornerRadius: compact ? 18 : 24), tint: TrickoStyle.ink.opacity(0.58),
                     fallback: TrickoStyle.surface, interactive: false)
        .accessibilityElement(children: .combine)
    }
}

// The accompanying localized percentage supplies the accessible progress value.
struct StageProgressTrack: View {
    let value: Double

    var body: some View {
        let fraction = value.isFinite ? min(max(value, 0), 1) : 0
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(TrickoStyle.paper.opacity(0.16))
                Capsule().fill(LinearGradient(colors: [TrickoStyle.coolAccent, TrickoStyle.accent],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * CGFloat(fraction))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct StageStateSymbol: View {
    let symbol: TrickoGlyph
    var size: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
        Glyph(symbol: symbol, size: size * 0.49, tint: TrickoStyle.coolAccent)
            .frame(width: size, height: size)
            .background {
                shape.fill(LinearGradient(colors: [TrickoStyle.coolAccent.opacity(0.22), TrickoStyle.ink.opacity(0.55)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { shape.strokeBorder(TrickoStyle.coolAccent.opacity(0.23)) }
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct EmptyStatePanel<Content: View>: View {
    let symbol: TrickoGlyph
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StageStateSymbol(symbol: symbol)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trickoGlass(in: .rect(cornerRadius: 24), tint: TrickoStyle.surface.opacity(0.48),
                     fallback: TrickoStyle.surface, interactive: false)
    }
}

struct EmptyStateCopy: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(title).font(.stage(.title3, weight: .semibold))
                .foregroundStyle(TrickoStyle.paper)
                .accessibilityAddTraits(.isHeader)
            LocalizedText(message).font(.stage(.subheadline))
                .foregroundStyle(TrickoStyle.secondary).lineSpacing(3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateActionStyle: ButtonStyle {
    var primary = true
    var symbol: TrickoGlyph? = nil
    var minHeight: CGFloat = 48
    var horizontalPadding: CGFloat = 16
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let foreground = primary ? TrickoStyle.accent : TrickoStyle.paper
        let label = HStack(spacing: 8) {
            if let symbol { Glyph(symbol: symbol, size: 17, tint: foreground) }
            configuration.label
                .font(.stage(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, horizontalPadding).padding(.vertical, 10)
        .frame(minWidth: 44, minHeight: minHeight)
        .foregroundStyle(foreground)

        return label.trickoGlass(in: Capsule(), tint: primary ? TrickoStyle.accent.opacity(0.24) : nil)
        .contentShape(Capsule())
        .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.72 : 1))
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
            .trickoGlass(in: .rect(cornerRadius: 22), tint: TrickoStyle.ink.opacity(0.54),
                         fallback: TrickoStyle.surface, interactive: false)
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
            .contentShape(Rectangle())
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

    func trickoGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, fallback: Color = TrickoStyle.raised,
                                       interactive: Bool = true) -> some View {
        modifier(TrickoGlass(shape: shape, tint: tint, fallback: fallback, interactive: interactive))
    }

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

private struct TrickoGlass<Surface: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    let shape: Surface
    let tint: Color?
    let fallback: Color
    let interactive: Bool

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
                content.glassEffect(.regular.tint(tint).interactive(interactive && isEnabled && !reduceMotion), in: shape)
            } else {
                content.background {
                    if reduceTransparency || contrast == .increased {
                        shape.fill(fallback)
                    } else {
                        shape.fill(.regularMaterial).overlay { shape.fill(tint ?? .clear) }
                    }
                }
                .overlay {
                    shape.strokeBorder(TrickoStyle.paper.opacity(contrast == .increased ? 0.55 : 0.14))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }
}

struct TrickoGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

struct StageCoverPlaceholder: View {
    let symbol: TrickoGlyph?

    var body: some View {
        LinearGradient(colors: [TrickoStyle.raised, TrickoStyle.surface, TrickoStyle.background],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                if let symbol { Glyph(symbol: symbol, size: 23, tint: TrickoStyle.coolAccent) }
            }
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct MediaCover: View {
    let url: URL?
    var folder = false
    var body: some View {
        StageCoverPlaceholder(symbol: folder ? .folder : .feed).overlay {
            GeometryReader { geometry in
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    }
                }
            }
        }.clipped()
    }
}
struct SheetHeading: View {
    let title: String?
    var close: () -> Void
    var body: some View {
        HStack {
            if let title {
                LocalizedText(title).font(.stage(.title3, display: true)).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
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

struct CountBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.stage(.caption2, weight: .semibold).monospacedDigit())
            .foregroundStyle(TrickoStyle.accent)
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 24)
            .background(TrickoStyle.accent.opacity(0.16), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct StageFilter: View {
    @Environment(\.locale) private var locale
    let values: [String]
    let selected: String
    var counts: [String: Int] = [:]
    let select: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            TrickoGlassGroup {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        let count = counts[value, default: 0]
                        let countText = count > 0 ? count.formatted(.number.locale(locale)) : nil
                        Button { select(value) } label: {
                            HStack(spacing: 6) {
                                LocalizedText(value).font(.stage(.footnote, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                if let countText {
                                    CountBadge(text: countText)
                                        .accessibilityHidden(true)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected == value ? TrickoStyle.accent : TrickoStyle.paper)
                            .trickoGlass(in: Capsule(), tint: selected == value ? TrickoStyle.accent.opacity(0.20) : nil)
                            .contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                            .accessibilityAddTraits(selected == value ? .isSelected : [])
                            .accessibilityValue(Text(verbatim: countText ?? ""))
                    }
                }
            }
        }
    }
}

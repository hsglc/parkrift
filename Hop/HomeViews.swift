import SwiftUI

/// The home screen, in the garage's clean style: on the left the brand, the stars and the car;
/// on the right the modes as rounded picture tiles (key art made with Meshy AI,
/// Textures/menu_*.jpg) with the career tile large and one gold "continue" pill.
struct HomeScreen: View {
    @EnvironmentObject var model: AppModel
    let openLevels: () -> Void
    let openCity: () -> Void
    let openOnline: () -> Void
    @State private var shown = false

    private var totalStars: Int { (0..<Levels.all.count).reduce(0) { $0 + model.stars(for: $1) } }
    private var maxStars: Int { Levels.all.count * 3 }

    var body: some View {
        GeometryReader { proxy in
            // Narrow screens (iPhone Duo's outer display, small iPhones): the modes only
            let compact = proxy.size.width < 700
            content(compact: compact)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { shown = true } }
    }

    private func content(compact: Bool) -> some View {
        HStack(spacing: 14) {
            if !compact {
                profileColumn
                    .frame(width: 214)
                    .opacity(shown ? 1 : 0)
                    .offset(x: shown ? 0 : -24)
            }
            careerTile
                .rise(shown, delay: 0.05)
            VStack(spacing: 12) {
                ModeArtTile(image: "menu_city.jpg", title: Strings.modeCityTitle, detail: Strings.modeCitySub,
                            accent: Neo.magenta, live: false, action: openCity)
                    .rise(shown, delay: 0.12)
                ModeArtTile(image: "menu_duo.jpg", title: Strings.modeOnlineTitle, detail: Strings.modeOnlineSub,
                            accent: Neo.cyan, live: true, action: openOnline)
                    .rise(shown, delay: 0.18)
            }
            .frame(maxWidth: 250)
        }
    }

    // MARK: Left: brand, stars, car

    private var profileColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 40)
            Text(Strings.splashTagline)
                .font(.ui(13, .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(Strings.homeProgress)
                        .font(.ui(13, .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 6)
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.gold)
                        .padding(.trailing, 4)
                    Text("\(totalStars)")
                        .font(.race(20))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(" / \(maxStars)")
                        .font(.ui(12, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
                ProgressCapsule(value: Double(totalStars) / Double(max(1, maxStars)), color: Palette.gold)
                    .frame(height: 5)
            }
            .padding(.bottom, 14)
            carCard
        }
        .padding(.vertical, 4)
    }

    /// The car, a tap away from the garage.
    private var carCard: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.6)
            model.openGarage(.menu)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.homeYourCar)
                        .font(.ui(12, .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(model.carChoice.spec.name.localUpper)
                        .font(.race(22))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Circle().fill(Color(model.carChoice.color)).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        Text(model.carChoice.spec.maker)
                            .font(.ui(12, .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Text(Strings.carClassTitle + " " + model.carChoice.spec.className)
                            .font(.ui(11, .heavy))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Capsule().fill(Palette.gold))
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
                RoundChevron(size: 34)
            }
            .padding(14)
            .background(NeoPanel(radius: 20))
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: Career tile

    private var careerTile: some View {
        let index = min(model.selectedLevel, Levels.all.count - 1)
        return Button {
            AudioManager.shared.play("click", volume: 0.6)
            openLevels()
        } label: {
            ZStack(alignment: .bottomLeading) {
                ArtBackground(image: "menu_park.jpg", accent: Palette.gold)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(Strings.homeCareerKicker)
                            .font(.ui(13, .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        if Progression.isWeekendEvent {
                            Text("2×")
                                .font(.ui(12, .heavy))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(Neo.magenta))
                        }
                    }
                    Text(Strings.modeSoloTitle.localUpper)
                        .font(.race(40))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                    HStack(spacing: 8) {
                        Text(Strings.level(index + 1, of: Levels.all.count))
                            .font(.ui(13, .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .fixedSize()
                        TierChip(index: index)
                        StarsRow(filled: model.stars(for: index), size: 12, spacing: 2)
                    }
                    .padding(.top, 2)
                    Button {
                        AudioManager.shared.play("click", volume: 0.6)
                        model.playSolo()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .black))
                            Text(Strings.homeContinue.localUpper)
                        }
                    }
                    .buttonStyle(GaragePillStyle(fill: Palette.gold, fontSize: 20))
                    .frame(maxWidth: 230)
                    .padding(.top, 14)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Picture tile for a mode: art, a soft fade, the title, a short line and a round arrow.
private struct ModeArtTile: View {
    let image: String
    let title: String
    let detail: String
    let accent: Color
    let live: Bool
    let action: () -> Void

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.6)
            action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                ArtBackground(image: image, accent: accent)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.localUpper)
                            .font(.race(26))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(detail)
                            .font(.ui(12, .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    RoundChevron(size: 34)
                }
                .padding(14)
            }
            .overlay(alignment: .topLeading) {
                if live {
                    HStack(spacing: 5) {
                        Circle().fill(Color(red: 0.3, green: 1, blue: 0.5)).frame(width: 6, height: 6)
                        Text(Strings.liveTag).font(.ui(11, .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Key art filling a tile, darkened toward the bottom where the text sits.
struct ArtBackground: View {
    let image: String
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [accent.opacity(0.35), Neo.ink], startPoint: .topTrailing, endPoint: .bottomLeading)
                if let art = UIImage(named: image) {
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                LinearGradient(colors: [.clear, Neo.ink.opacity(0.5), Neo.ink.opacity(0.9)],
                               startPoint: UnitPoint(x: 0.5, y: 0.25), endPoint: .bottom)
            }
        }
        // A fill-scaled image is still touchable outside its clipped frame: without this the art of
        // one tile sat over the button of the tile beside it and swallowed taps.
        .allowsHitTesting(false)
    }
}

/// A round glass arrow at the end of a tile or a card.
struct RoundChevron: View {
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.14)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
    }
}

/// A level's difficulty as a small capsule in its tier colour.
struct TierChip: View {
    let index: Int

    var body: some View {
        Text(Strings.tierNames[min(4, max(0, index) / 10)].capitalized)
            .font(.ui(11, .heavy))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(TierColor.of(level: index)))
    }
}

/// The game's wordmark: PARK in white, RIFT in neon, the racing face.
struct Wordmark: View {
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            Text("PARK").foregroundStyle(.white)
            Text("RIFT").foregroundStyle(LinearGradient(colors: [Neo.cyan, Neo.magenta], startPoint: .leading, endPoint: .trailing))
        }
        .font(.race(size))
        .shadow(color: Neo.cyan.opacity(0.3), radius: 12)
    }
}

/// A thin rounded progress bar.
struct ProgressCapsule: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, proxy.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
    }
}

/// Dark glass card with a hairline border (profile blocks, the level list).
struct NeoPanel: View {
    var radius: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.black.opacity(0.4))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// Round glass icon button of the top bars.
struct NeoIconButton: View {
    let systemImage: String
    var badge = false
    let action: () -> Void

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.5)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Neo.magenta).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Neo.ink, lineWidth: 2))
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Neon-on-carbon palette of the home screen (matches the splash).
enum Neo {
    static let ink = Color(red: 0.03, green: 0.035, blue: 0.06)
    static let panel = Color(red: 0.08, green: 0.09, blue: 0.13)
    static let cyan = Color(red: 0.25, green: 0.92, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.3, blue: 0.72)
}

extension View {
    /// Rises into place after `delay` once `shown` turns on.
    func rise(_ shown: Bool, delay: Double) -> some View {
        self.opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.86).delay(delay), value: shown)
    }
}

/// A mode option as a big picture tile: art, a round icon, a short label, the title, a line
/// about it and a pill in the tile's accent (city and online pages).
struct ArtActionTile: View {
    let image: String
    let kicker: String
    let title: String
    let detail: String
    let accent: Color
    let icon: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtBackground(image: image, accent: accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(title.localUpper)
                    .font(.race(30))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.4), radius: 8)
                Text(detail)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    AudioManager.shared.play("click", volume: 0.6)
                    action()
                } label: {
                    Text(buttonTitle.localUpper)
                }
                .buttonStyle(GaragePillStyle(fill: accent, fontSize: 19))
                .padding(.top, 10)
            }
            .padding(18)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .padding(14)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
    }
}

/// Top bar title of a menu page, like the garage's: a round back button, the page name and a
/// short line under it.
struct NeoPageTitle: View {
    let subtitle: String
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundIconButton(systemImage: "chevron.left") {
                AudioManager.shared.play("click", volume: 0.6)
                back()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.race(28))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }
}

/// Garage shortcut in the page top bar: the car's colour and name in a glass capsule.
struct NeoGarageChip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.6)
            model.openGarage(.menu)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(model.carChoice.color)).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                Text(model.carChoice.spec.name)
                    .font(.race(16))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(height: 40)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Strings.garage)
    }
}

/// Colour of a parking level's difficulty tier (easy ... master).
enum TierColor {
    static let all: [Color] = [Color(red: 0.35, green: 0.9, blue: 0.55), Color(red: 1, green: 0.84, blue: 0.3),
                               Color(red: 1, green: 0.55, blue: 0.25), Color(red: 1, green: 0.32, blue: 0.35),
                               Color(red: 0.78, green: 0.45, blue: 1)]
    static func of(level index: Int) -> Color { all[min(4, max(0, index) / 10)] }
}

/// The selected parking level: art, number, name, difficulty, its rules, stars, best time, play.
struct LevelDetailPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let index = min(model.selectedLevel, Levels.all.count - 1)
        let level = Levels.all[index]
        let challenge = ParkChallenge.forMenu(index: index)
        let tier = TierColor.of(level: index)
        return ZStack(alignment: .bottomLeading) {
            ArtBackground(image: "menu_park.jpg", accent: tier)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(Strings.level(index + 1, of: Levels.all.count))
                        .font(.ui(13, .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    TierChip(index: index)
                }
                Text(level.name.localUpper)
                    .font(.race(34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.4), radius: 8)
                    .id(index)
                    .transition(.opacity)
                HStack(spacing: 12) {
                    StarsRow(filled: model.stars(for: index), size: 16, spacing: 3)
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch.fill").foregroundStyle(Palette.gold)
                        Text(model.bestTime(for: index).map { String(format: "%.1f s", $0) } ?? "–")
                            .monospacedDigit()
                    }
                    .font(.ui(14, .bold))
                    .foregroundStyle(.white.opacity(0.85))
                }
                // The level's rules (Challenge.swift)
                let rules = challenge.rules
                if !rules.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                            HStack(spacing: 6) {
                                Image(systemName: rule.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tier)
                                    .frame(width: 14)
                                Text(rule.text).font(.ui(12, .semibold)).foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Spacer(minLength: 0)
                Button {
                    AudioManager.shared.play("click", volume: 0.6)
                    model.playSolo()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 14, weight: .black))
                        Text(Strings.play.localUpper)
                    }
                }
                .buttonStyle(GaragePillStyle(fill: Palette.gold, fontSize: 22))
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
        .animation(.easeOut(duration: 0.2), value: model.selectedLevel)
    }
}

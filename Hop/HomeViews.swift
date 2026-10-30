import SwiftUI

/// The home screen: a racing-game front page. On the left the brand, the player's progress and
/// car; on the right the three modes as slanted picture tiles (key art made with Meshy AI,
/// Textures/menu_*.jpg) with the career tile large and a direct "continue" button.
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
        HStack(spacing: 16) {
            if !compact {
                profileColumn
                    .frame(width: 210)
                    .opacity(shown ? 1 : 0)
                    .offset(x: shown ? 0 : -24)
            }
            HStack(spacing: 12) {
                careerTile
                    .rise(shown, delay: 0.05)
                VStack(spacing: 12) {
                    ModeArtTile(image: "menu_city.jpg", kicker: Strings.homeCityKicker, title: Strings.modeCityTitle,
                                detail: Strings.carRace + "  ·  " + Strings.parkRace, accent: Neo.magenta,
                                badge: nil, action: openCity)
                        .rise(shown, delay: 0.12)
                    ModeArtTile(image: "menu_duo.jpg", kicker: Strings.homeOnlineKicker, title: Strings.modeOnlineTitle,
                                detail: Strings.quickMatch + "  ·  " + Strings.createRoom, accent: Neo.cyan,
                                badge: "LIVE", action: openOnline)
                        .rise(shown, delay: 0.18)
                }
                .frame(maxWidth: 250)
            }
        }
    }

    // MARK: Left: brand, progress, car

    private var profileColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 40)
            Text("PARK  ·  DRIFT  ·  ONLINE")
                .font(.kicker(9))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 2)
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.homeProgress).font(.kicker(9)).tracking(1.2).foregroundStyle(Neo.cyan)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "star.fill").font(.system(size: 15, weight: .black)).foregroundStyle(Palette.gold)
                    Text("\(totalStars)").font(.race(28)).foregroundStyle(.white).monospacedDigit()
                    Text("/ \(maxStars)").font(.race(15, weight: .heavy)).foregroundStyle(.white.opacity(0.45))
                }
                SlantedBar(value: Double(totalStars) / Double(max(1, maxStars)), color: Palette.gold)
                    .frame(height: 6)
            }
            .padding(.bottom, 14)
            Button {
                AudioManager.shared.play("click", volume: 0.6)
                model.openGarage(.menu)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Strings.homeYourCar).font(.kicker(9)).tracking(1.2).foregroundStyle(Neo.cyan)
                        Spacer()
                        Text(model.carChoice.spec.className)
                            .font(.race(12))
                            .foregroundStyle(Neo.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(SlantedShape(skew: 5).fill(Neo.cyan))
                    }
                    Text(model.carChoice.spec.name.uppercased())
                        .font(.race(24))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Circle().fill(Color(model.carChoice.color)).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        Text(model.carChoice.spec.maker).font(.kicker(9)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        HStack(spacing: 4) {
                            Text(Strings.garage.uppercased())
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .black))
                        }
                        .font(.race(13))
                        .foregroundStyle(Neo.cyan)
                    }
                }
                .padding(12)
                .background(NeoPanel())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.vertical, 4)
    }

    // MARK: Career tile

    private var careerTile: some View {
        let index = min(model.selectedLevel, Levels.all.count - 1)
        let tier = Strings.tierNames[min(4, index / 10)]
        return Button {
            AudioManager.shared.play("click", volume: 0.6)
            openLevels()
        } label: {
            ZStack(alignment: .bottomLeading) {
                ArtBackground(image: "menu_park.jpg", accent: Palette.gold)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(Strings.homeCareerKicker).font(.kicker(10)).tracking(1.2).foregroundStyle(Palette.gold)
                        if Progression.isWeekendEvent {
                            Text("2×").font(.race(12)).foregroundStyle(Neo.ink)
                                .padding(.horizontal, 7).background(SlantedShape(skew: 5).fill(Neo.magenta))
                        }
                    }
                    Text(Strings.modeSoloTitle.uppercased())
                        .font(.race(36))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.5), radius: 8)
                    HStack(spacing: 8) {
                        Text(Strings.level(index + 1, of: Levels.all.count))
                            .font(.race(14, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .fixedSize()
                        Text(tier)
                            .lineLimit(1)
                            .fixedSize()
                            .font(.race(11))
                            .foregroundStyle(Neo.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(SlantedShape(skew: 5).fill(Palette.gold))
                        StarsRow(filled: model.stars(for: index), size: 12, spacing: 2)
                    }
                    Button {
                        AudioManager.shared.play("click", volume: 0.6)
                        model.playSolo()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 13, weight: .black))
                            Text(Strings.homeContinue.uppercased())
                        }
                    }
                    .buttonStyle(RaceButtonStyle(color: Palette.gold, textColor: Neo.ink, height: 46, fontSize: 19))
                    .padding(.top, 4)
                }
                .padding(.leading, 26)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
            .clipShape(SlantedShape(skew: 22))
            .contentShape(SlantedShape(skew: 22))
            .overlay(SlantedShape(skew: 22).strokeBorderCompat(Color.white.opacity(0.14), lineWidth: 1))
            .overlay(alignment: .topLeading) { AccentStripe(color: Palette.gold).offset(x: 34, y: 0) }
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Picture tile for a mode: art, a dark fade, kicker, big italic title, a detail line.
private struct ModeArtTile: View {
    let image: String
    let kicker: String
    let title: String
    let detail: String
    let accent: Color
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.6)
            action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                ArtBackground(image: image, accent: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kicker).font(.kicker(9)).tracking(1.2).foregroundStyle(accent)
                    HStack(alignment: .center) {
                        Text(title.uppercased())
                            .font(.race(24))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Neo.ink)
                            .frame(width: 30, height: 24)
                            .background(SlantedShape(skew: 7).fill(accent))
                    }
                    Text(detail)
                        .font(.ui(11, .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, 22)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
            .overlay(alignment: .topTrailing) {
                if let badge = badge {
                    HStack(spacing: 4) {
                        Circle().fill(Color(red: 0.3, green: 1, blue: 0.5)).frame(width: 6, height: 6)
                        Text(badge).font(.kicker(8))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .padding(10)
                }
            }
            .clipShape(SlantedShape(skew: 16))
            .contentShape(SlantedShape(skew: 16))
            .overlay(SlantedShape(skew: 16).strokeBorderCompat(Color.white.opacity(0.14), lineWidth: 1))
            .overlay(alignment: .topLeading) { AccentStripe(color: accent).offset(x: 24, y: 0) }
            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Key art filling a tile, darkened toward the bottom-left where the text sits.
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
                LinearGradient(colors: [.clear, Neo.ink.opacity(0.55), Neo.ink.opacity(0.92)],
                               startPoint: UnitPoint(x: 0.5, y: 0.2), endPoint: .bottom)
                LinearGradient(colors: [Neo.ink.opacity(0.5), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5))
            }
        }
        // A fill-scaled image is still touchable outside its clipped frame: without this the art of
        // one tile sat over the button of the tile beside it and swallowed taps.
        .allowsHitTesting(false)
    }
}

/// A short bright bar along the top edge of a tile.
struct AccentStripe: View {
    let color: Color
    var body: some View {
        SlantedShape(skew: 4)
            .fill(color)
            .frame(width: 44, height: 4)
            .shadow(color: color.opacity(0.8), radius: 6)
    }
}

/// The game's wordmark: PARK in white, RIFT in neon, italic and condensed, a slash of light.
struct Wordmark: View {
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            Text("PARK").foregroundStyle(.white)
            Text("RIFT").foregroundStyle(LinearGradient(colors: [Neo.cyan, Neo.magenta], startPoint: .leading, endPoint: .trailing))
        }
        .font(.race(size))
        .shadow(color: Neo.cyan.opacity(0.35), radius: 12)
        .overlay(alignment: .bottomLeading) {
            SlantedShape(skew: 4)
                .fill(LinearGradient(colors: [Neo.cyan, Neo.magenta.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 3, height: 3)
                .offset(x: 4, y: 6)
        }
    }
}

/// A thin slanted progress bar.
struct SlantedBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                SlantedShape(skew: 4).fill(Color.white.opacity(0.12))
                SlantedShape(skew: 4)
                    .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, proxy.size.width * min(1, max(0, value))))
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
    }
}

/// Dark panel with a hairline border (profile blocks).
struct NeoPanel: View {
    var body: some View {
        SlantedShape(skew: 10)
            .fill(LinearGradient(colors: [Neo.panel.opacity(0.92), Neo.ink.opacity(0.94)], startPoint: .top, endPoint: .bottom))
            .overlay(SlantedShape(skew: 10).strokeBorderCompat(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Square glass icon button of the home top bar.
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, height: 34)
                .background(SlantedShape(skew: 6).fill(Neo.ink.opacity(0.7)))
                .overlay(SlantedShape(skew: 6).strokeBorderCompat(Color.white.opacity(0.14), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Neo.magenta).frame(width: 9, height: 9)
                            .shadow(color: Neo.magenta, radius: 4)
                            .offset(x: 2, y: -2)
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

/// A mode option as a big picture tile: art, kicker, title, a short line and a slanted
/// call-to-action in the tile's accent (city and online pages).
struct ArtActionTile: View {
    let image: String
    let kicker: String
    let title: String
    let detail: String
    let accent: Color
    let icon: String
    let buttonTitle: String
    var skew: CGFloat = 20
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtBackground(image: image, accent: accent)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11, weight: .black))
                    Text(kicker).font(.kicker(9)).tracking(1.2)
                }
                .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.race(30))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                Text(detail)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    AudioManager.shared.play("click", volume: 0.6)
                    action()
                } label: {
                    HStack(spacing: 8) {
                        Text(buttonTitle.uppercased())
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .black))
                    }
                }
                .buttonStyle(RaceButtonStyle(color: accent, textColor: Neo.ink, height: 44, fontSize: 18))
                .padding(.top, 4)
            }
            .padding(.leading, skew + 8)
            .padding(.trailing, 18)
            .padding(.bottom, 16)
        }
        .clipShape(SlantedShape(skew: skew))
        .contentShape(SlantedShape(skew: skew))
        .overlay(SlantedShape(skew: skew).strokeBorderCompat(Color.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false))
        .overlay(alignment: .topLeading) { AccentStripe(color: accent).offset(x: skew + 12, y: 0).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
    }
}

/// Top bar title of a menu page: slanted back button, kicker and the page name.
struct NeoPageTitle: View {
    let kicker: String
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NeoIconButton(systemImage: "chevron.left", action: back)
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker.uppercased()).font(.kicker(9)).tracking(1.5).foregroundStyle(Neo.cyan)
                Text(title.uppercased()).font(.race(28)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

/// Garage shortcut in the page top bar: the car's colour, name and class.
struct NeoGarageChip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.6)
            model.openGarage(.menu)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "car.side.fill")
                    .foregroundStyle(Color(model.carChoice.color.lighter(by: 0.25)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(Strings.garage.uppercased()).font(.kicker(8)).foregroundStyle(.white.opacity(0.5))
                    Text(model.carChoice.spec.name.uppercased()).font(.race(14)).foregroundStyle(.white)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(height: 38)
            .background(SlantedShape(skew: 8).fill(Neo.ink.opacity(0.75)))
            .overlay(SlantedShape(skew: 8).strokeBorderCompat(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
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
                    Text(Strings.level(index + 1, of: Levels.all.count).uppercased())
                        .font(.kicker(10)).tracking(1.2).foregroundStyle(.white.opacity(0.75))
                    Text(Strings.tierNames[min(4, index / 10)])
                        .font(.race(11)).foregroundStyle(Neo.ink)
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(SlantedShape(skew: 5).fill(tier))
                }
                Text(level.name.uppercased())
                    .font(.race(34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .id(index)
                    .transition(.opacity)
                HStack(spacing: 12) {
                    StarsRow(filled: model.stars(for: index), size: 16, spacing: 3)
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch.fill").foregroundStyle(Palette.gold)
                        Text(model.bestTime(for: index).map { String(format: "%.1f s", $0) } ?? "–")
                            .monospacedDigit()
                    }
                    .font(.race(14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
                }
                // The level's rules (Challenge.swift)
                let rules = challenge.rules
                if !rules.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 5) {
                        ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                            HStack(spacing: 6) {
                                Image(systemName: rule.icon).font(.system(size: 10, weight: .black)).foregroundStyle(tier)
                                    .frame(width: 14)
                                Text(rule.text).font(.ui(11, .bold)).foregroundStyle(.white.opacity(0.85))
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
                        Text(Strings.play.uppercased())
                    }
                }
                .buttonStyle(RaceButtonStyle(color: Palette.gold, textColor: Neo.ink, height: 50, fontSize: 22))
            }
            .padding(.leading, 30)
            .padding(.trailing, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipShape(SlantedShape(skew: 22))
        .overlay(SlantedShape(skew: 22).strokeBorderCompat(Color.white.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .topLeading) { AccentStripe(color: tier).offset(x: 34, y: 0) }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
        .animation(.easeOut(duration: 0.2), value: model.selectedLevel)
    }
}

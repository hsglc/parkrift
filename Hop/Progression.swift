import Foundation

/// What happened in one round, as the game reports it at the end.
struct RunStats {
    /// Which game mode the round was.
    enum Mode { case park, city, race, online }
    var mode: Mode = .park
    var finished: Bool
    var stars: Int
    /// nil outside a head-to-head round.
    var won: Bool?
    var race: Bool
    var solo: Bool
    var hits: Int
    var driftPoints: Int
    var nearMisses: Int
    var escapes: Int
    var topSpeed: Int
    /// Parking precision 0...100 (solo parking levels).
    var precision: Int? = nil
    /// Taxi rounds: the fare and the tip.
    var fare = 0
    var tip = 0
}

/// Coins earned in a round, line by line, and the daily tasks it completed.
struct RunReward {
    var lines: [(label: String, coins: Int)]
    /// Daily tasks this round completed: their coins wait to be collected on the daily screen.
    var tasksDone: [(name: String, coins: Int)]
    var total: Int { lines.reduce(0) { $0 + $1.coins } }
}

/// The meta game kept on the device: coins, the cars bought with them, daily tasks for every mode and a
/// seven-day login streak. Rewards follow the genre's usual loop: every round pays a little,
/// a daily task pays more than a round, and the daily gift grows over a week of visits.
enum Progression {
    private static let defaults = UserDefaults.standard

    // MARK: Coins

    static var coins: Int {
        get {
            if defaults.object(forKey: "pp.coins") == nil { return 250 }
            return defaults.integer(forKey: "pp.coins")
        }
        set { defaults.set(max(0, newValue), forKey: "pp.coins") }
    }

    // MARK: Cars

    /// Two cars are free; the rest cost coins (about 4–15 rounds each).
    static func price(_ id: CarModelID) -> Int {
        switch id {
        case .italia, .strada: return 0
        case .arrow: return 800
        case .bison: return 1200
        case .classico: return 1500
        case .toro: return 2500
        }
    }

    private static var owned: Set<Int> {
        get {
            if let list = defaults.array(forKey: "pp.owned") as? [Int] { return Set(list) }
            // First run of this version: the free cars and whatever the player already drives
            let start: Set<Int> = [CarModelID.italia.rawValue, CarModelID.strada.rawValue, CarChoice.saved.model.rawValue]
            defaults.set(Array(start), forKey: "pp.owned")
            return start
        }
        set { defaults.set(Array(newValue), forKey: "pp.owned") }
    }

    static func owns(_ id: CarModelID) -> Bool { price(id) == 0 || owned.contains(id.rawValue) }

    /// Spends the coins and adds the car; false when there are not enough coins.
    @discardableResult
    static func buy(_ id: CarModelID) -> Bool {
        guard !owns(id), coins >= price(id) else { return false }
        coins -= price(id)
        owned.insert(id.rawValue)
        return true
    }

    // MARK: Upgrades

    /// Engine, grip and nitro levels (0...3) of one car.
    struct Upgrades: Equatable {
        var engine = 0
        var grip = 0
        var nitro = 0
    }

    enum UpgradeKind: Int, CaseIterable { case engine, grip, nitro }

    static let maxUpgrade = 3

    /// Price of the next level (level 0 -> 1 costs the first).
    static func upgradePrice(_ level: Int) -> Int { [200, 400, 700][max(0, min(2, level))] }

    static func upgrades(for id: CarModelID) -> Upgrades {
        let all = defaults.dictionary(forKey: "pp.upgrades") as? [String: [Int]] ?? [:]
        let levels = all[String(id.rawValue)] ?? [0, 0, 0]
        return Upgrades(engine: levels[0], grip: levels[1], nitro: levels[2])
    }

    /// Buys the next level of one upgrade; false at the top or without the coins.
    @discardableResult
    static func buyUpgrade(_ kind: UpgradeKind, for id: CarModelID) -> Bool {
        var current = upgrades(for: id)
        let level = [current.engine, current.grip, current.nitro][kind.rawValue]
        guard level < maxUpgrade, coins >= upgradePrice(level) else { return false }
        coins -= upgradePrice(level)
        switch kind {
        case .engine: current.engine += 1
        case .grip: current.grip += 1
        case .nitro: current.nitro += 1
        }
        var all = defaults.dictionary(forKey: "pp.upgrades") as? [String: [Int]] ?? [:]
        all[String(id.rawValue)] = [current.engine, current.grip, current.nitro]
        defaults.set(all, forKey: "pp.upgrades")
        return true
    }

    // MARK: Round rewards

    /// Pays a finished round, counts it toward today's tasks and pays any task it completes.
    static func reward(for run: RunStats) -> RunReward {
        var lines: [(label: String, coins: Int)] = []
        if run.finished {
            lines.append((Strings.rewardFinish, run.won == true ? 80 : 30))
            if run.solo && run.stars > 0 { lines.append((Strings.rewardStars, run.stars * 15)) }
            if run.hits == 0 { lines.append((Strings.rewardClean, 25)) }
        }
        if run.finished && run.fare > 0 { lines.append((Strings.rewardFare, run.fare)) }
        if run.finished && run.tip > 0 { lines.append((Strings.rewardTip, run.tip)) }
        if run.driftPoints > 0 { lines.append((Strings.rewardDrift, min(150, run.driftPoints / 25))) }
        if run.nearMisses > 0 { lines.append((Strings.rewardNearMiss, run.nearMisses * 10)) }
        if run.escapes > 0 { lines.append((Strings.rewardEscape, run.escapes * 75)) }
        if let precision = run.precision {
            let grade = ParkPrecision.grade(for: precision)
            let coins = grade == .s ? 60 : (grade == .a ? 30 : (grade == .b ? 10 : 0))
            if coins > 0 { lines.append((Strings.rewardPrecision(grade.rawValue), coins)) }
        }
        lines = lines.filter { $0.coins > 0 }
        // Weekend event: every round pays double
        if isWeekendEvent {
            let base = lines.reduce(0) { $0 + $1.coins }
            if base > 0 { lines.append((Strings.weekendBonus, base)) }
        }
        let done = advanceTasks(with: run)
        let reward = RunReward(lines: lines, tasksDone: done)
        coins += reward.total
        return reward
    }

    // MARK: Weekend event

    /// Friday to Sunday every round pays double coins.
    static var isWeekendEvent: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())   // 1 = Sunday
        return weekday == 1 || weekday == 6 || weekday == 7
    }

    // MARK: Daily tasks

    /// Every mode has its own tasks each day: two for parking, two for the city, two for racing
    /// and one for playing with a friend, drawn from a larger pool (the same for everyone on a date).
    enum TaskMode: Int, CaseIterable {
        case park, city, race, online

        var title: String {
            switch self {
            case .park: return Strings.modeSoloTitle
            case .city: return Strings.modeCityTitle
            case .race: return Strings.carRace
            case .online: return Strings.modeOnlineTitle
            }
        }

        /// Short name for a tab.
        var short: String {
            switch self {
            case .park: return Strings.tabPark
            case .city: return Strings.tabCity
            case .race: return Strings.tabRace
            case .online: return Strings.tabOnline
            }
        }

        var icon: String {
            switch self {
            case .park: return "parkingsign"
            case .city: return "building.2.fill"
            case .race: return "flag.checkered"
            case .online: return "person.2.fill"
            }
        }

        /// How many of its tasks show each day.
        var daily: Int { self == .online ? 1 : 2 }
    }

    enum TaskKind: Int, CaseIterable {
        // Parking
        case parkRounds, threeStars, parkClean, parkFlawless, parkStars
        // City
        case cityRounds, nearMiss, escape, drift, cityClean
        // Race
        case raceRounds, raceClean, topSpeed, raceDrift, raceNearMiss
        // Online
        case onlineRounds, onlineWin
        // Parking (added later: kept last so the others keep their numbers)
        case perfectPark

        var mode: TaskMode {
            switch self {
            case .parkRounds, .threeStars, .parkClean, .parkFlawless, .parkStars, .perfectPark: return .park
            case .cityRounds, .nearMiss, .escape, .drift, .cityClean: return .city
            case .raceRounds, .raceClean, .topSpeed, .raceDrift, .raceNearMiss: return .race
            case .onlineRounds, .onlineWin: return .online
            }
        }

        var target: Int {
            switch self {
            case .parkRounds: return 4
            case .threeStars: return 2
            case .parkClean: return 3
            case .parkFlawless: return 1
            case .parkStars: return 8
            case .cityRounds: return 3
            case .nearMiss: return 6
            case .escape: return 1
            case .drift: return 1500
            case .cityClean: return 1
            case .raceRounds: return 2
            case .raceClean: return 1
            case .topSpeed: return 95
            case .raceDrift: return 800
            case .raceNearMiss: return 4
            case .onlineRounds: return 2
            case .onlineWin: return 1
            case .perfectPark: return 1
            }
        }

        var reward: Int {
            switch self {
            case .parkRounds, .cityRounds, .raceRounds, .topSpeed: return 100
            case .threeStars, .parkClean, .drift, .raceDrift, .nearMiss, .raceNearMiss: return 140
            case .parkStars, .cityClean, .raceClean: return 160
            case .parkFlawless, .escape, .onlineRounds: return 200
            case .onlineWin: return 250
            case .perfectPark: return 180
            }
        }

        var title: String { Strings.taskTitle(self) }

        var icon: String {
            switch self {
            case .parkRounds: return "parkingsign"
            case .threeStars, .parkStars: return "star.fill"
            case .parkClean, .cityClean, .raceClean: return "checkmark.shield.fill"
            case .parkFlawless: return "sparkles"
            case .cityRounds: return "building.2.fill"
            case .nearMiss, .raceNearMiss: return "arrow.left.and.right"
            case .escape: return "light.beacon.max.fill"
            case .drift, .raceDrift: return "tornado"
            case .raceRounds: return "flag.checkered"
            case .topSpeed: return "speedometer"
            case .onlineRounds: return "person.2.fill"
            case .onlineWin: return "trophy.fill"
            case .perfectPark: return "scope"
            }
        }
    }

    struct DailyTask: Identifiable {
        let index: Int
        let kind: TaskKind
        let progress: Int
        /// Its coins were collected.
        let claimed: Bool
        var id: Int { index }
        var done: Bool { progress >= kind.target }
        /// Done, coins waiting to be collected.
        var claimable: Bool { done && !claimed }
    }

    static var todayKey: String { dayKey(Date()) }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Today's tasks, mode by mode: the same for everyone on the same date.
    private static func todaysKinds() -> [TaskKind] {
        let days = Int(Date().timeIntervalSince1970 / 86_400)
        var rng = SplitMix64(seed: UInt64(days) &* 2_654_435_761)
        var result: [TaskKind] = []
        for mode in TaskMode.allCases {
            var pool = TaskKind.allCases.filter { $0.mode == mode }
            pool.shuffle(using: &rng)
            result += pool.prefix(mode.daily)
        }
        return result
    }

    private static func todaysProgress() -> [Int] {
        let count = todaysKinds().count
        guard let saved = defaults.dictionary(forKey: "pp.daily"), saved["day"] as? String == todayKey,
              let progress = saved["p"] as? [Int], progress.count == count else { return Array(repeating: 0, count: count) }
        return progress
    }

    /// Which of today's tasks had their coins collected. A save from before collecting existed
    /// paid a task's coins as it was done, so there a done task counts as collected.
    private static func todaysClaimed(progress: [Int]) -> [Bool] {
        let kinds = todaysKinds()
        if let saved = defaults.dictionary(forKey: "pp.daily"), saved["day"] as? String == todayKey,
           let claimed = saved["c"] as? [Bool], claimed.count == kinds.count {
            return claimed
        }
        return kinds.indices.map { progress[$0] >= kinds[$0].target }
    }

    private static func saveDaily(progress: [Int], claimed: [Bool]) {
        defaults.set(["day": todayKey, "p": progress, "c": claimed], forKey: "pp.daily")
    }

    static var tasks: [DailyTask] {
        let progress = todaysProgress()
        let claimed = todaysClaimed(progress: progress)
        return todaysKinds().enumerated().map {
            DailyTask(index: $0.offset, kind: $0.element, progress: progress[$0.offset], claimed: claimed[$0.offset])
        }
    }

    /// Tasks done whose coins wait to be collected.
    static var claimableTasks: [DailyTask] { tasks.filter(\.claimable) }

    /// Collects a done task's coins; returns them (0 if not done or already collected).
    @discardableResult
    static func claim(_ index: Int) -> Int {
        let progress = todaysProgress()
        var claimed = todaysClaimed(progress: progress)
        let kinds = todaysKinds()
        guard kinds.indices.contains(index), progress[index] >= kinds[index].target, !claimed[index] else { return 0 }
        claimed[index] = true
        saveDaily(progress: progress, claimed: claimed)
        coins += kinds[index].reward
        return kinds[index].reward
    }

    /// Today's tasks still open (for the badge on the gift button).
    static var openTasks: Int { tasks.filter { !$0.done }.count }

    /// Adds the round to today's tasks; returns the tasks it just completed (their coins wait on
    /// the daily screen to be collected).
    private static func advanceTasks(with run: RunStats) -> [(name: String, coins: Int)] {
        var progress = todaysProgress()
        let claimed = todaysClaimed(progress: progress)
        var completed: [(name: String, coins: Int)] = []
        for (index, kind) in todaysKinds().enumerated() {
            let before = progress[index]
            guard before < kind.target else { continue }
            var value = before
            let park = run.mode == .park, city = run.mode == .city, race = run.mode == .race
            switch kind {
            case .parkRounds: if park && run.finished { value += 1 }
            case .threeStars: if park && run.finished && run.stars == 3 { value += 1 }
            case .parkClean: if park && run.finished && run.hits == 0 { value += 1 }
            case .parkFlawless: if park && run.finished && run.stars == 3 && run.hits == 0 { value += 1 }
            case .parkStars: if park && run.finished { value += run.stars }
            case .cityRounds: if city && run.finished { value += 1 }
            case .nearMiss: if city { value += run.nearMisses }
            case .escape: if city || race { value += run.escapes }
            case .drift: if city { value += run.driftPoints }
            case .cityClean: if city && run.finished && run.hits == 0 { value += 1 }
            case .raceRounds: if race && run.finished { value += 1 }
            case .raceClean: if race && run.finished && run.hits == 0 { value += 1 }
            case .topSpeed: if race { value = max(value, run.topSpeed) }
            case .raceDrift: if race { value += run.driftPoints }
            case .raceNearMiss: if race { value += run.nearMisses }
            case .onlineRounds: if run.mode == .online && run.finished { value += 1 }
            case .onlineWin: if run.mode == .online && run.won == true { value += 1 }
            case .perfectPark: if park && run.finished && (run.precision ?? 0) >= 95 { value += 1 }
            }
            progress[index] = min(kind.target, value)
            if progress[index] >= kind.target { completed.append((kind.title, kind.reward)) }
        }
        saveDaily(progress: progress, claimed: claimed)
        return completed
    }

    // MARK: Daily gift (login streak)

    static let streakRewards = [100, 150, 200, 250, 300, 400, 600]

    /// Day of the streak (1...7) that today's gift belongs to, or nil once it is collected.
    static var pendingGiftDay: Int? {
        let last = defaults.string(forKey: "pp.giftDay")
        if last == todayKey { return nil }
        let yesterday = dayKey(Date().addingTimeInterval(-86_400))
        let streak = last == yesterday ? defaults.integer(forKey: "pp.streak") : 0
        return streak % 7 + 1
    }

    /// Collects today's gift; returns its coins.
    @discardableResult
    static func collectGift() -> Int {
        guard let day = pendingGiftDay else { return 0 }
        let amount = streakRewards[day - 1]
        defaults.set(day, forKey: "pp.streak")
        defaults.set(todayKey, forKey: "pp.giftDay")
        coins += amount
        return amount
    }

    /// Days of the current streak already collected (for the 7-day strip).
    static var streakCollected: Int {
        let last = defaults.string(forKey: "pp.giftDay")
        let yesterday = dayKey(Date().addingTimeInterval(-86_400))
        guard last == todayKey || last == yesterday else { return 0 }
        let streak = defaults.integer(forKey: "pp.streak")
        // A finished week starts again
        return last == yesterday && streak >= 7 ? 0 : streak
    }
}

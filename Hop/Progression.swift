import Foundation

/// What happened in one round, as the game reports it at the end.
struct RunStats {
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
}

/// Coins earned in a round, line by line, and the daily tasks it completed.
struct RunReward {
    var lines: [(label: String, coins: Int)]
    var tasksDone: [(name: String, coins: Int)]
    var total: Int { lines.reduce(0) { $0 + $1.coins } + tasksDone.reduce(0) { $0 + $1.coins } }
}

/// The meta game kept on the device: coins, the cars bought with them, three daily tasks and a
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
        case .toro: return 600
        case .arrow: return 800
        case .retro: return 1000
        case .bison: return 1200
        case .classico: return 1500
        case .concept: return 2500
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

    // MARK: Round rewards

    /// Pays a finished round, counts it toward today's tasks and pays any task it completes.
    static func reward(for run: RunStats) -> RunReward {
        var lines: [(label: String, coins: Int)] = []
        if run.finished {
            lines.append((Strings.rewardFinish, run.won == true ? 80 : 30))
            if run.solo && run.stars > 0 { lines.append((Strings.rewardStars, run.stars * 15)) }
            if run.hits == 0 { lines.append((Strings.rewardClean, 25)) }
        }
        if run.driftPoints > 0 { lines.append((Strings.rewardDrift, min(150, run.driftPoints / 25))) }
        if run.nearMisses > 0 { lines.append((Strings.rewardNearMiss, run.nearMisses * 10)) }
        if run.escapes > 0 { lines.append((Strings.rewardEscape, run.escapes * 75)) }
        lines = lines.filter { $0.coins > 0 }
        let done = advanceTasks(with: run)
        let reward = RunReward(lines: lines, tasksDone: done)
        coins += reward.total
        return reward
    }

    // MARK: Daily tasks

    enum TaskKind: Int, CaseIterable {
        case drift, nearMiss, threeStars, escape, rounds, topSpeed, clean

        var target: Int {
            switch self {
            case .drift: return 1500
            case .nearMiss: return 5
            case .threeStars: return 3
            case .escape: return 1
            case .rounds: return 5
            case .topSpeed: return 85
            case .clean: return 2
            }
        }

        var reward: Int {
            switch self {
            case .drift, .threeStars, .clean: return 150
            case .nearMiss: return 120
            case .escape: return 200
            case .rounds, .topSpeed: return 100
            }
        }

        var title: String { Strings.taskTitle(self) }

        var icon: String {
            switch self {
            case .drift: return "tornado"
            case .nearMiss: return "arrow.left.and.right"
            case .threeStars: return "star.fill"
            case .escape: return "light.beacon.max.fill"
            case .rounds: return "flag.checkered"
            case .topSpeed: return "speedometer"
            case .clean: return "checkmark.shield.fill"
            }
        }
    }

    struct DailyTask: Identifiable {
        let index: Int
        let kind: TaskKind
        let progress: Int
        var id: Int { index }
        var done: Bool { progress >= kind.target }
    }

    static var todayKey: String { dayKey(Date()) }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Today's three tasks: the same for everyone on the same date.
    private static func todaysKinds() -> [TaskKind] {
        let days = Int(Date().timeIntervalSince1970 / 86_400)
        var rng = SplitMix64(seed: UInt64(days) &* 2_654_435_761)
        var kinds = TaskKind.allCases
        kinds.shuffle(using: &rng)
        return Array(kinds.prefix(3))
    }

    private static func todaysProgress() -> [Int] {
        guard let saved = defaults.dictionary(forKey: "pp.daily"), saved["day"] as? String == todayKey,
              let progress = saved["p"] as? [Int], progress.count == 3 else { return [0, 0, 0] }
        return progress
    }

    static var tasks: [DailyTask] {
        let progress = todaysProgress()
        return todaysKinds().enumerated().map { DailyTask(index: $0.offset, kind: $0.element, progress: progress[$0.offset]) }
    }

    /// Adds the round to today's tasks; returns the tasks it just completed (their coins are paid).
    private static func advanceTasks(with run: RunStats) -> [(name: String, coins: Int)] {
        var progress = todaysProgress()
        var completed: [(name: String, coins: Int)] = []
        for (index, kind) in todaysKinds().enumerated() {
            let before = progress[index]
            guard before < kind.target else { continue }
            var value = before
            switch kind {
            case .drift: value += run.driftPoints
            case .nearMiss: value += run.nearMisses
            case .threeStars: if run.solo && run.finished && run.stars == 3 { value += 1 }
            case .escape: value += run.escapes
            case .rounds: if run.finished { value += 1 }
            case .topSpeed: value = max(value, run.topSpeed)
            case .clean: if run.finished && run.hits == 0 { value += 1 }
            }
            progress[index] = min(kind.target, value)
            if progress[index] >= kind.target { completed.append((kind.title, kind.reward)) }
        }
        defaults.set(["day": todayKey, "p": progress], forKey: "pp.daily")
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

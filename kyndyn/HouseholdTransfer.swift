import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum HouseholdTransferError: LocalizedError, Equatable {
    case unsupportedVersion
    case malformed(String)
    case householdNotEmpty
    case alreadyImported

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This file was made by a newer or unsupported version of kyndyn."
        case .malformed(let reason):
            return "This file can’t be imported safely. \(reason)"
        case .householdNotEmpty:
            return "For safety, imports can only create an empty, new kyndyn household."
        case .alreadyImported:
            return "This exact transfer has already been imported."
        }
    }
}

struct HouseholdBackup: Codable, Equatable, Sendable {
    static let format = "kyndyn-household-backup"
    static let version = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var household: HouseholdValue
    var people: [PersonValue]
    var quests: [QuestValue]
    var completions: [CompletionValue]
    var rewardGoals: [RewardValue]
    var settings: SettingsValue

    struct HouseholdValue: Codable, Equatable, Sendable {
        var id: UUID
        var schemaVersion: Int
        var name: String
        var timeZoneIdentifier: String
        var createdAt: Date
        var deletedAt: Date?
        var rewardTitle: String
        var rewardGoalXP: Int
    }
    struct PersonValue: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var role: ProfileRole
        var colorHex: String
        var companionID: String
        var createdAt: Date
        var deletedAt: Date?
    }
    struct QuestValue: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var detail: String
        var xp: Int
        var completionMode: QuestCompletionMode
        var participantIDs: [UUID]
        var scheduleKind: ScheduleKind
        var weekdays: [Int]
        var repeatIntervalWeeks: Int? = nil
        var startDate: Date
        var dueAt: Date?
        var createdAt: Date
        var deletedAt: Date?
    }
    struct CompletionValue: Codable, Equatable, Sendable {
        var id: UUID
        var questID: UUID
        var personID: UUID
        var occurrenceDay: String
        var completedAt: Date
        var awardedXP: Int
        var reversedAt: Date?
    }
    struct RewardValue: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var targetXP: Int
        var createdAt: Date
        var deletedAt: Date?
    }
    struct SettingsValue: Codable, Equatable, Sendable {
        var parentProtectionEnabled: Bool
    }
}

struct TransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw HouseholdTransferError.malformed("The selected document is empty.")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct TransferReport: Equatable, Sendable {
    enum Source: String, Sendable { case kyndynBackup, rowanPWA }
    var source: Source
    var accepted: Int
    var normalized: Int
    var skipped: Int
    var unsupported: Int
    var invalid: Int
    var notes: [String]
    var canImport: Bool {
        accepted > 0 && (source == .rowanPWA || invalid == 0)
    }
}

enum HouseholdTransferCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @MainActor
    static func export(household: Household, people: [Person], quests: [Quest],
                       completions: [QuestCompletion], goals: [RewardGoal],
                       settings: HouseholdSettings?) throws -> Data {
        let backup = HouseholdBackup(
            format: HouseholdBackup.format, version: HouseholdBackup.version,
            exportedAt: .now,
            household: .init(
                id: household.id, schemaVersion: household.schemaVersion,
                name: household.name,
                timeZoneIdentifier: household.timeZoneIdentifier,
                createdAt: household.createdAt, deletedAt: household.deletedAt,
                rewardTitle: household.rewardTitle,
                rewardGoalXP: household.rewardGoalXP),
            people: people.map {
                .init(id: $0.id, name: $0.name, role: $0.role,
                      colorHex: $0.colorHex, companionID: $0.companionID,
                      createdAt: $0.createdAt, deletedAt: $0.deletedAt)
            },
            quests: quests.map {
                .init(id: $0.id, title: $0.title, detail: $0.detail, xp: $0.xp,
                      completionMode: $0.completionMode,
                      participantIDs: $0.participantIDs,
                      scheduleKind: $0.scheduleKind, weekdays: $0.weekdays,
                      repeatIntervalWeeks: $0.repeatIntervalWeeks,
                      startDate: $0.startDate, dueAt: $0.dueAt,
                      createdAt: $0.createdAt, deletedAt: $0.deletedAt)
            },
            completions: completions.map {
                .init(id: $0.id, questID: $0.questID, personID: $0.personID,
                      occurrenceDay: $0.occurrenceDay,
                      completedAt: $0.completedAt, awardedXP: $0.awardedXP,
                      reversedAt: $0.reversedAt)
            },
            rewardGoals: goals.map {
                .init(id: $0.id, title: $0.title, targetXP: $0.targetXP,
                      createdAt: $0.createdAt, deletedAt: $0.deletedAt)
            },
            settings: .init(
                parentProtectionEnabled:
                    settings?.parentProtectionEnabled ?? true))
        return try encoder().encode(backup)
    }

    static func validateBackup(_ data: Data) throws -> (HouseholdBackup, TransferReport) {
        guard data.count <= 25_000_000 else {
            throw HouseholdTransferError.malformed("The document is larger than 25 MB.")
        }
        let backup: HouseholdBackup
        do { backup = try decoder().decode(HouseholdBackup.self, from: data) }
        catch { throw HouseholdTransferError.malformed("Its structure or dates are invalid.") }
        guard backup.format == HouseholdBackup.format,
              backup.version == HouseholdBackup.version else {
            throw HouseholdTransferError.unsupportedVersion
        }
        try validate(
            household: backup.household, people: backup.people,
            quests: backup.quests, completions: backup.completions)
        let accepted = 1 + backup.people.count + backup.quests.count
            + backup.completions.count + backup.rewardGoals.count + 1
        return (backup, TransferReport(
            source: .kyndynBackup, accepted: accepted, normalized: 0,
            skipped: 0, unsupported: 0, invalid: 0,
            notes: ["Creates a new household; it does not merge or replace existing data."]))
    }

    private static func validate(
        household: HouseholdBackup.HouseholdValue,
        people: [HouseholdBackup.PersonValue],
        quests: [HouseholdBackup.QuestValue],
        completions: [HouseholdBackup.CompletionValue]
    ) throws {
        guard !household.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              household.name.count <= 80 else {
            throw HouseholdTransferError.malformed("The household name is invalid.")
        }
        guard TimeZone(identifier: household.timeZoneIdentifier) != nil else {
            throw HouseholdTransferError.malformed("The household time zone is invalid.")
        }
        guard people.count <= 100, quests.count <= 10_000,
              completions.count <= 250_000 else {
            throw HouseholdTransferError.malformed("The document contains too many records.")
        }
        let personIDs = Set(people.map(\.id))
        let questIDs = Set(quests.map(\.id))
        guard personIDs.count == people.count, questIDs.count == quests.count,
              Set(completions.map(\.id)).count == completions.count else {
            throw HouseholdTransferError.malformed("It contains duplicate stable identifiers.")
        }
        guard people.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.count <= 40 && $0.colorHex.count <= 16
                && $0.companionID.count <= 40
        }) else {
            throw HouseholdTransferError.malformed("A profile is invalid.")
        }
        guard people.contains(where: {
            $0.role == .parent && $0.deletedAt == nil
        }) else {
            throw HouseholdTransferError.malformed(
                "At least one active parent profile is required.")
        }
        guard quests.allSatisfy({
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.title.count <= 80 && $0.detail.count <= 300
                && (1...500).contains($0.xp)
                && !$0.participantIDs.isEmpty
                && Set($0.participantIDs).isSubset(of: personIDs)
                && Set($0.weekdays).isSubset(of: Set(1...7))
                && (1...2).contains($0.repeatIntervalWeeks ?? 1)
        }) else {
            throw HouseholdTransferError.malformed("A quest or assignment is invalid.")
        }
        guard completions.allSatisfy({
            questIDs.contains($0.questID) && personIDs.contains($0.personID)
                && (-500...500).contains($0.awardedXP)
                && $0.occurrenceDay.count <= 32
        }) else {
            throw HouseholdTransferError.malformed("A completion event is invalid.")
        }
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
enum HouseholdRestoreService {
    static func restore(
        _ data: Data, context: ModelContext,
        receiptFingerprint: String? = nil,
        sourceKind: TransferReport.Source = .kyndynBackup,
        sourceVersion: Int? = nil
    ) throws -> Household {
        guard try context.fetch(FetchDescriptor<Household>()).isEmpty else {
            throw HouseholdTransferError.householdNotEmpty
        }
        let fingerprint = receiptFingerprint
            ?? HouseholdTransferCodec.fingerprint(data)
        guard try context.fetch(FetchDescriptor<HouseholdImportReceipt>())
            .contains(where: { $0.fingerprint == fingerprint }) == false else {
            throw HouseholdTransferError.alreadyImported
        }
        let (backup, _) = try HouseholdTransferCodec.validateBackup(data)
        let household = Household(
            id: backup.household.id, name: backup.household.name,
            timeZoneIdentifier: backup.household.timeZoneIdentifier,
            rewardTitle: backup.household.rewardTitle,
            rewardGoalXP: backup.household.rewardGoalXP)
        household.schemaVersion = KyndynSchema.version
        household.createdAt = backup.household.createdAt
        household.deletedAt = backup.household.deletedAt
        context.insert(household)
        var insertedPeople: [Person] = []
        for value in backup.people {
            let person = Person(
                id: value.id, householdID: household.id, name: value.name,
                role: value.role, colorHex: value.colorHex,
                companionID: value.companionID)
            person.createdAt = value.createdAt
            person.deletedAt = value.deletedAt
            context.insert(person); insertedPeople.append(person)
        }
        var insertedQuests: [Quest] = []
        for value in backup.quests {
            let quest = Quest(
                id: value.id, householdID: household.id, title: value.title,
                detail: value.detail, xp: value.xp,
                participantIDs: value.participantIDs,
                completionMode: value.completionMode,
                scheduleKind: value.scheduleKind, weekdays: value.weekdays,
                repeatIntervalWeeks: value.repeatIntervalWeeks ?? 1,
                startDate: value.startDate, dueAt: value.dueAt)
            quest.createdAt = value.createdAt
            quest.deletedAt = value.deletedAt
            context.insert(quest); insertedQuests.append(quest)
        }
        var insertedCompletions: [QuestCompletion] = []
        for value in backup.completions {
            let completion = QuestCompletion(
                id: value.id, householdID: household.id,
                questID: value.questID, personID: value.personID,
                occurrenceDay: value.occurrenceDay,
                completedAt: value.completedAt, awardedXP: value.awardedXP)
            completion.reversedAt = value.reversedAt
            context.insert(completion); insertedCompletions.append(completion)
        }
        var insertedGoals: [RewardGoal] = []
        for value in backup.rewardGoals {
            let goal = RewardGoal(
                householdID: household.id, title: value.title,
                targetXP: value.targetXP)
            goal.id = value.id; goal.createdAt = value.createdAt
            goal.deletedAt = value.deletedAt
            context.insert(goal); insertedGoals.append(goal)
        }
        let settings = HouseholdSettings(householdID: household.id)
        settings.parentProtectionEnabled =
            backup.settings.parentProtectionEnabled
        context.insert(settings)
        context.insert(LocalDeviceSettings())
        context.insert(HouseholdImportReceipt(
            fingerprint: fingerprint, householdID: household.id,
            sourceKind: sourceKind.rawValue,
            sourceVersion: sourceVersion ?? backup.version))
        do {
            try context.transaction {
                try context.save()
                try enqueue(
                    household: household, people: insertedPeople,
                    quests: insertedQuests, completions: insertedCompletions,
                    goals: insertedGoals, settings: settings, context: context)
            }
            return household
        } catch {
            context.rollback()
            throw error
        }
    }

    static func enqueue(household: Household, people: [Person], quests: [Quest],
                        completions: [QuestCompletion], goals: [RewardGoal],
                        settings: HouseholdSettings, context: ModelContext) throws {
        try SyncQueue.enqueue(
            SyncSnapshot.household(household), operation: .createOrUpdate,
            context: context)
        for person in people {
            try SyncQueue.enqueue(
                SyncSnapshot.person(person),
                operation: person.deletedAt == nil ? .createOrUpdate : .archive,
                context: context)
        }
        for quest in quests {
            for record in SyncSnapshot.quest(quest) {
                try SyncQueue.enqueue(
                    record,
                    operation: quest.deletedAt == nil ? .createOrUpdate : .archive,
                    context: context)
            }
        }
        for completion in completions {
            try SyncQueue.enqueue(
                SyncSnapshot.completion(completion),
                operation: .createOrUpdate, context: context)
        }
        for goal in goals {
            try SyncQueue.enqueue(
                SyncSnapshot.reward(goal),
                operation: goal.deletedAt == nil ? .createOrUpdate : .archive,
                context: context)
        }
        try SyncQueue.enqueue(
            SyncSnapshot.settings(settings), operation: .createOrUpdate,
            context: context)
    }
}

// MARK: - Rowan PWA transfer conversion

enum LegacyID: Codable, Hashable {
    case string(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let integer = try? value.decode(Int.self) {
            self = .string(String(integer))
        } else {
            throw DecodingError.dataCorruptedError(
                in: value, debugDescription: "Expected a string or numeric ID")
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self { case .string(let raw): try value.encode(raw) }
    }
    var raw: String {
        switch self { case .string(let value): return value }
    }
}

struct RowanTransferPackage: Codable {
    static let format = "rowan-pwa-transfer"
    var format: String
    var version: Int
    var family: Family
    var people: [Person]
    var quests: [Quest]
    var completionHistory: [Completion]
    var settings: Settings?

    enum CodingKeys: String, CodingKey {
        case format, version, family, people, quests, settings
        case completionHistory = "completion_history"
    }
    struct Family: Codable {
        var name: String?
        var timezone: String?
        var rewardName: String?
        var goalXP: Int?
        enum CodingKeys: String, CodingKey {
            case name, timezone
            case rewardName = "current_reward"
            case goalXP = "goal_xp"
        }
    }
    struct Person: Codable {
        var id: LegacyID
        var name: String
        var role: String?
        var color: String?
        var companion: String?
        var active: Bool?
    }
    struct Quest: Codable {
        var id: LegacyID
        var title: String
        var description: String?
        var xp: Int?
        var assignees: [LegacyID]?
        var assignedTo: LegacyID?
        var completionMode: String?
        var frequency: String?
        var scheduledDay: Int?
        var scheduledDays: [Int]?
        var startDate: String?
        var dueDate: String?
        var dueAt: String?
        var active: Bool?
        enum CodingKeys: String, CodingKey {
            case id, title, description, xp, assignees, frequency, active
            case assignedTo = "assigned_to"
            case completionMode = "completion_mode"
            case scheduledDay = "scheduled_day"
            case scheduledDays = "scheduled_days"
            case startDate = "start_date"
            case dueDate = "due_date"
            case dueAt = "due_at"
        }
    }
    struct Completion: Codable {
        var id: LegacyID
        var questID: LegacyID
        var personID: LegacyID
        var completedAt: String
        var awardedXP: Int
        var active: Bool?
        var undoneAt: String?
        enum CodingKeys: String, CodingKey {
            case id, active
            case questID = "quest_id"
            case personID = "person_id"
            case completedAt = "completed_at"
            case awardedXP = "awarded_xp"
            case undoneAt = "undone_at"
        }
    }
    struct Settings: Codable {
        // These are the only approved settings fields. Unknown and secret fields
        // are ignored by Codable and can never enter the native model.
        var householdName: String?
        var timezone: String?
        enum CodingKeys: String, CodingKey {
            case householdName = "household_name"
            case timezone
        }
    }
}

enum RowanTransferConverter {
    private static let namespace = "com.kyndynfamily.rowan-import.v1"
    private static let supportedCompanions =
        Set(["spark", "orbit", "pixel", "comet", "bop"])

    static func dryRun(_ data: Data) throws
        -> (backup: HouseholdBackup, report: TransferReport) {
        guard data.count <= 25_000_000 else {
            throw HouseholdTransferError.malformed("The transfer is larger than 25 MB.")
        }
        let source: RowanTransferPackage
        do { source = try JSONDecoder().decode(RowanTransferPackage.self, from: data) }
        catch { throw HouseholdTransferError.malformed("The Rowan transfer structure is invalid.") }
        guard source.format == RowanTransferPackage.format,
              source.version == 1 else {
            throw HouseholdTransferError.unsupportedVersion
        }
        let householdName = clean(
            source.family.name ?? source.settings?.householdName ?? "Imported family",
            maximum: 80) ?? "Imported family"
        let timezone = source.family.timezone ?? source.settings?.timezone
            ?? TimeZone.current.identifier
        guard TimeZone(identifier: timezone) != nil else {
            throw HouseholdTransferError.malformed("The Rowan household time zone is invalid.")
        }
        let householdID = stableUUID(kind: "household", sourceID: "root")
        var notes = [
            "PINs, sessions, push data, calendars, weather, assistant history, credentials, device data, logs, and backups are excluded.",
            "Badges, broadcasts, extended cosmetics, accessories, weather, calendars, and assistant history are preserved in the original export but not imported."
        ]
        var normalized = 0
        var invalid = 0
        var skipped = 0
        var unsupported = 0

        var seenPeople = Set<LegacyID>()
        var people: [HouseholdBackup.PersonValue] = []
        var personMap: [LegacyID: UUID] = [:]
        for sourcePerson in source.people {
            guard seenPeople.insert(sourcePerson.id).inserted else {
                skipped += 1; continue
            }
            guard let name = clean(sourcePerson.name, maximum: 40) else {
                invalid += 1; continue
            }
            let id = stableUUID(kind: "person", sourceID: sourcePerson.id.raw)
            personMap[sourcePerson.id] = id
            let role: ProfileRole =
                sourcePerson.role?.lowercased() == "parent" ? .parent : .child
            let color = validColor(sourcePerson.color) ?? "#6F2DBD"
            let companion = supportedCompanions.contains(
                sourcePerson.companion?.lowercased() ?? "")
                ? sourcePerson.companion!.lowercased() : "spark"
            if color != sourcePerson.color || companion != sourcePerson.companion {
                normalized += 1
            }
            people.append(.init(
                id: id, name: name, role: role, colorHex: color,
                companionID: companion, createdAt: .now,
                deletedAt: sourcePerson.active == false ? .now : nil))
        }
        guard people.contains(where: { $0.role == .parent && $0.deletedAt == nil })
        else {
            throw HouseholdTransferError.malformed("At least one active parent profile is required.")
        }

        var seenQuests = Set<LegacyID>()
        var questMap: [LegacyID: UUID] = [:]
        var quests: [HouseholdBackup.QuestValue] = []
        for sourceQuest in source.quests {
            guard seenQuests.insert(sourceQuest.id).inserted else {
                skipped += 1; continue
            }
            guard let title = clean(sourceQuest.title, maximum: 80),
                  !title.isEmpty,
                  let detail = clean(sourceQuest.description ?? "", maximum: 300),
                  (1...500).contains(sourceQuest.xp ?? 10) else {
                invalid += 1; continue
            }
            let legacyAssignments = sourceQuest.assignees
                ?? sourceQuest.assignedTo.map { [$0] } ?? []
            let assignments = legacyAssignments.compactMap { personMap[$0] }
            guard !assignments.isEmpty else { invalid += 1; continue }
            let recurrence = recurrence(
                frequency: sourceQuest.frequency,
                scheduledDay: sourceQuest.scheduledDay,
                scheduledDays: sourceQuest.scheduledDays)
            guard let recurrence else {
                unsupported += 1; continue
            }
            let start = parseDate(sourceQuest.startDate) ?? .now
            let due = parseDate(sourceQuest.dueAt ?? sourceQuest.dueDate)
            if sourceQuest.startDate != nil && parseDate(sourceQuest.startDate) == nil {
                normalized += 1
            }
            let id = stableUUID(kind: "quest", sourceID: sourceQuest.id.raw)
            questMap[sourceQuest.id] = id
            let requestedMode = sourceQuest.completionMode?.lowercased()
            let mode: QuestCompletionMode =
                assignments.count > 1 && ["shared", "shared_all", "all"]
                    .contains(requestedMode ?? "") ? .sharedAll : .individual
            if requestedMode == "claim_once" {
                unsupported += 1
                notes.append("Claim-once quest “\(title)” was not imported because kyndyn has no equivalent completion rule.")
                questMap[sourceQuest.id] = nil
                continue
            }
            quests.append(.init(
                id: id, title: title, detail: detail, xp: sourceQuest.xp ?? 10,
                completionMode: mode, participantIDs: assignments,
                scheduleKind: recurrence.kind, weekdays: recurrence.weekdays,
                repeatIntervalWeeks: 1,
                startDate: start, dueAt: due, createdAt: start,
                deletedAt: sourceQuest.active == false ? .now : nil))
        }

        var seenEvents = Set<LegacyID>()
        var completions: [HouseholdBackup.CompletionValue] = []
        for event in source.completionHistory {
            guard seenEvents.insert(event.id).inserted else {
                skipped += 1; continue
            }
            guard let questID = questMap[event.questID],
                  let personID = personMap[event.personID],
                  let completedAt = parseDate(event.completedAt),
                  (-500...500).contains(event.awardedXP) else {
                invalid += 1; continue
            }
            let reversedAt: Date?
            if event.active == false {
                reversedAt = parseDate(event.undoneAt) ?? completedAt
                if event.undoneAt == nil { normalized += 1 }
            } else {
                reversedAt = parseDate(event.undoneAt)
            }
            completions.append(.init(
                id: stableUUID(kind: "completion", sourceID: event.id.raw),
                questID: questID, personID: personID,
                occurrenceDay: ProgressionEngine.dayKey(
                    completedAt, timeZoneIdentifier: timezone),
                completedAt: completedAt, awardedXP: event.awardedXP,
                reversedAt: reversedAt))
        }
        let rewardTitle = clean(
            source.family.rewardName ?? "Family Adventure", maximum: 80)
            ?? "Family Adventure"
        let goalXP = min(max(source.family.goalXP ?? 300, 1), 1_000_000)
        if goalXP != source.family.goalXP { normalized += 1 }
        let backup = HouseholdBackup(
            format: HouseholdBackup.format, version: HouseholdBackup.version,
            exportedAt: .now,
            household: .init(
                id: householdID, schemaVersion: KyndynSchema.version,
                name: householdName, timeZoneIdentifier: timezone,
                createdAt: .now, deletedAt: nil, rewardTitle: rewardTitle,
                rewardGoalXP: goalXP),
            people: people, quests: quests, completions: completions,
            rewardGoals: [], settings: .init(parentProtectionEnabled: true))
        let accepted = 1 + people.count + quests.count + completions.count + 1
        return (backup, TransferReport(
            source: .rowanPWA, accepted: accepted, normalized: normalized,
            skipped: skipped, unsupported: unsupported, invalid: invalid,
            notes: Array(Set(notes)).sorted()))
    }

    @MainActor
    static func apply(_ data: Data, context: ModelContext) throws -> Household {
        let fingerprint = HouseholdTransferCodec.fingerprint(data)
        guard try context.fetch(FetchDescriptor<Household>()).isEmpty else {
            throw HouseholdTransferError.householdNotEmpty
        }
        guard try context.fetch(FetchDescriptor<HouseholdImportReceipt>())
            .contains(where: { $0.fingerprint == fingerprint }) == false else {
            throw HouseholdTransferError.alreadyImported
        }
        let conversion = try dryRun(data)
        guard conversion.report.canImport else {
            throw HouseholdTransferError.malformed("No valid core records were found.")
        }
        let converted = try HouseholdTransferCodec.encoder()
            .encode(conversion.backup)
        return try HouseholdRestoreService.restore(
            converted, context: context,
            receiptFingerprint: fingerprint, sourceKind: .rowanPWA,
            sourceVersion: 1)
    }

    private static func clean(_ value: String, maximum: Int) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count <= maximum else { return nil }
        return cleaned
    }

    private static func validColor(_ value: String?) -> String? {
        guard let value else { return nil }
        let upper = value.uppercased()
        guard upper.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil
        else { return nil }
        return upper
    }

    private static func recurrence(frequency: String?, scheduledDay: Int?,
                                   scheduledDays: [Int]?)
        -> (kind: ScheduleKind, weekdays: [Int])? {
        switch frequency?.lowercased() ?? "one_time" {
        case "once", "one_time", "one-time": return (.oneTime, [])
        case "daily": return (.daily, [])
        case "weekday", "weekdays":
            return (.weekly, [2, 3, 4, 5, 6])
        case "weekly", "scheduled":
            let days = (scheduledDays ?? scheduledDay.map { [$0] } ?? [])
                .filter { (1...7).contains($0) }
            return days.isEmpty ? nil : (.weekly, Array(Set(days)).sorted())
        default: return nil
        }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, raw.count <= 64 else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    static func stableUUID(kind: String, sourceID: String) -> UUID {
        let digest = Array(SHA256.hash(
            data: Data("\(namespace):\(kind):\(sourceID)".utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

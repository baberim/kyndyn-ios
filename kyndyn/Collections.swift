import Foundation
import SwiftUI

struct BadgeAward: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

struct BackgroundDefinition: Identifiable, Equatable {
    enum Requirement: Equatable {
        case starter
        case completions(Int)
        case streak(Int)
        case level(Int)
        case badges(Int)
        case familyReward
        case parentGrant
    }

    let id: String
    let name: String
    let assetName: String
    let requirement: Requirement

    var unlockHint: String {
        switch requirement {
        case .starter: return "Included"
        case .completions(let count): return "Complete \(count) quests"
        case .streak(let days): return "Reach a \(days)-day streak"
        case .level(let level): return "Reach level \(level)"
        case .badges(let count): return "Earn \(count) badges"
        case .familyReward: return "Reach a family reward"
        case .parentGrant: return "A parent can unlock this"
        }
    }
}

struct CompanionDefinition: Identifiable, Equatable {
    enum Requirement: Equatable {
        case starter
        case completions(Int)
        case streak(Int)
        case level(Int)
        case badges(Int)
        case familyReward
        case parentGrant
    }

    let id: String
    let name: String
    let requirement: Requirement

    var unlockHint: String {
        switch requirement {
        case .starter: return "Included"
        case .completions(let count): return "Complete \(count) quests"
        case .streak(let days): return "Reach a \(days)-day streak"
        case .level(let level): return "Reach level \(level)"
        case .badges(let count): return "Earn \(count) badges"
        case .familyReward: return "Reach a family reward"
        case .parentGrant: return "A parent can unlock this"
        }
    }
}

enum CollectionCatalog {
    static let companions = [
        CompanionDefinition(id: "spark", name: "Spark", requirement: .starter),
        CompanionDefinition(id: "orbit", name: "Orbit", requirement: .starter),
        CompanionDefinition(id: "pixel", name: "Pixel", requirement: .starter),
        CompanionDefinition(id: "comet", name: "Comet", requirement: .starter),
        CompanionDefinition(id: "bop", name: "Bop", requirement: .starter),
        CompanionDefinition(id: "penguin", name: "Penguin", requirement: .completions(1)),
        CompanionDefinition(id: "bee", name: "Bee", requirement: .completions(10)),
        CompanionDefinition(id: "cactus", name: "Cactus", requirement: .streak(3)),
        CompanionDefinition(id: "cloud", name: "Cloud", requirement: .badges(3)),
        CompanionDefinition(id: "dino", name: "Dino", requirement: .completions(25)),
        CompanionDefinition(id: "jellyfish", name: "Jellyfish", requirement: .familyReward),
        CompanionDefinition(id: "astronaut", name: "Astronaut", requirement: .level(5)),
        CompanionDefinition(id: "deer", name: "Deer", requirement: .badges(5)),
        CompanionDefinition(id: "ninja", name: "Ninja", requirement: .streak(7)),
        CompanionDefinition(id: "star", name: "Star", requirement: .level(3)),
        CompanionDefinition(id: "petey", name: "Petey", requirement: .completions(50)),
        CompanionDefinition(id: "kaleido", name: "Kaleido", requirement: .completions(100)),
        CompanionDefinition(id: "selene", name: "Selene", requirement: .level(10))
    ]
    static let starterCompanionIDs = companions.compactMap {
        $0.requirement == .starter ? $0.id : nil
    }
    static let companionIDs = companions.map(\.id)
    static let defaultBackgroundID = "meadow"
    static let backgrounds = [
        BackgroundDefinition(id: "meadow", name: "Meadow", assetName: "meadow", requirement: .starter),
        BackgroundDefinition(id: "bedroom", name: "Bedroom", assetName: "bedroom", requirement: .starter),
        BackgroundDefinition(id: "cloud", name: "Cloud", assetName: "background-cloud", requirement: .completions(10)),
        BackgroundDefinition(id: "aquarium", name: "Aquarium", assetName: "aquarium", requirement: .badges(3)),
        BackgroundDefinition(id: "arcade", name: "Arcade", assetName: "arcade", requirement: .completions(25)),
        BackgroundDefinition(id: "rainbow-summit", name: "Rainbow Summit", assetName: "rainbow-summit", requirement: .level(3)),
        BackgroundDefinition(id: "crystal-dream-cave", name: "Crystal Dream Cave", assetName: "crystal-dream-cave", requirement: .streak(7)),
        BackgroundDefinition(id: "moon-garden", name: "Moon Garden", assetName: "moon-garden", requirement: .badges(5)),
        BackgroundDefinition(id: "starry-campout", name: "Starry Campout", assetName: "starry-campout", requirement: .completions(50)),
        BackgroundDefinition(id: "space-station-window", name: "Space Station", assetName: "space-station-window", requirement: .level(10))
    ]
    static let starterBackgroundIDs = backgrounds.compactMap {
        $0.requirement == .starter ? $0.id : nil
    }

    static func normalizedCompanions(_ ids: [String]) -> [String] {
        let valid = Set(companionIDs)
        return Array(Set(ids).intersection(valid).union(starterCompanionIDs)).sorted()
    }

    static func normalizedBackgrounds(_ ids: [String]) -> [String] {
        let valid = Set(backgrounds.map(\.id))
        let values = Set(ids).intersection(valid).union(starterBackgroundIDs)
        return values.sorted()
    }

    static func companion(named id: String) -> CompanionDefinition {
        companions.first { $0.id == id } ?? companions[0]
    }
}

enum RecognitionEngine {
    static func badges(progress: PersonProgress) -> [BadgeAward] {
        var values = [BadgeAward]()
        if progress.completedCount >= 1 { values.append(.init(id: "first-step", title: "First Step", detail: "Completed a first quest", systemImage: "shoeprints.fill")) }
        if progress.completedCount >= 10 { values.append(.init(id: "quest-ten", title: "Quest Keeper", detail: "Completed 10 quests", systemImage: "checkmark.seal.fill")) }
        if progress.currentStreak >= 3 { values.append(.init(id: "streak-three", title: "On a Roll", detail: "Reached a 3-day streak", systemImage: "flame.fill")) }
        if progress.currentStreak >= 7 { values.append(.init(id: "streak-seven", title: "Steady Star", detail: "Reached a 7-day streak", systemImage: "star.fill")) }
        if progress.level >= 2 { values.append(.init(id: "level-two", title: "Leveling Up", detail: "Reached level 2", systemImage: "arrow.up.circle.fill")) }
        return values
    }

    static func earnedBackgroundIDs(
        progress: PersonProgress, familyRewardReached: Bool
    ) -> [String] {
        CollectionCatalog.backgrounds.compactMap { background in
            switch background.requirement {
            case .starter: return background.id
            case .completions(let count): return progress.completedCount >= count ? background.id : nil
            case .streak(let days): return progress.currentStreak >= days ? background.id : nil
            case .level(let level): return progress.level >= level ? background.id : nil
            case .badges(let count): return badges(progress: progress).count >= count ? background.id : nil
            case .familyReward: return familyRewardReached ? background.id : nil
            case .parentGrant: return nil
            }
        }
    }

    static func earnedCompanionIDs(
        progress: PersonProgress, familyRewardReached: Bool = false
    ) -> [String] {
        CollectionCatalog.companions.compactMap { companion in
            switch companion.requirement {
            case .starter: return companion.id
            case .completions(let count):
                return progress.completedCount >= count ? companion.id : nil
            case .streak(let days):
                return progress.currentStreak >= days ? companion.id : nil
            case .level(let level):
                return progress.level >= level ? companion.id : nil
            case .badges(let count):
                return badges(progress: progress).count >= count ? companion.id : nil
            case .familyReward:
                return familyRewardReached ? companion.id : nil
            case .parentGrant: return nil
            }
        }
    }
}

struct ProfileScene: View {
    let backgroundID: String
    let companionID: String
    let accent: Color

    var body: some View {
        let definition = CollectionCatalog.backgrounds.first { $0.id == backgroundID }
            ?? CollectionCatalog.backgrounds[0]
        GeometryReader { proxy in
            ZStack {
                if let path = Bundle.main.path(
                    forResource: definition.assetName, ofType: "png"),
                   let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [accent.opacity(0.35), .purple.opacity(0.25)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: min(proxy.size.height * 0.68, 156),
                           height: min(proxy.size.height * 0.68, 156))
                CompanionArt(id: companionID)
                    .frame(width: min(proxy.size.height * 0.78, 180),
                           height: min(proxy.size.height * 0.78, 180))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(accent.opacity(0.45)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(definition.name) background with \(CollectionCatalog.companion(named: companionID).name)")
    }
}

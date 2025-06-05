import Foundation
import Testing
@testable import SlackowWall

@Suite("Profile System Tests")
struct ProfileSystemTests {
    private static let fileManager = FileManager.default
    private static let profilesDir: URL = {
        let root = fileManager.temporaryDirectory.appendingPathComponent("ProfileSystemTests_\(UUID().uuidString)")
        let profiles = root
            .appendingPathComponent("Library/Application Support/SlackowWall", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
        try? fileManager.createDirectory(at: profiles, withIntermediateDirectories: true)
        setenv("SW_PROFILE_BASE_DIR", profiles.path, 1)
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return profiles
    }()

    private static var settings: Settings = {
        return Settings.shared
    }()

    private var baseURL: URL {
        Self.profilesDir
    }

    private func resetEnvironment() {
        if Self.fileManager.fileExists(atPath: baseURL.path) {
            try? Self.fileManager.removeItem(at: baseURL)
        }
        try? Self.fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        Self.settings.preferences = Preferences()
        Self.settings.currentProfile = UUID()
    }

    @Test("Create, switch and delete profiles")
    func profileLifecycle() throws {
        resetEnvironment()
        let settings = Self.settings

        #expect(settings.availableProfiles.isEmpty)
        settings.createProfile()
        let firstID = settings.currentProfile
        #expect(settings.availableProfiles.count == 1)

        settings.createProfile()
        let secondID = settings.currentProfile
        #expect(settings.availableProfiles.count == 2)
        #expect(secondID != firstID)

        try settings.switchProfile(to: firstID)
        #expect(settings.currentProfile == firstID)

        try settings.switchProfile(to: secondID)
        settings.deleteCurrentProfile()

        #expect(!settings.availableProfiles.map(\.id).contains(secondID))
        #expect(settings.availableProfiles.count == 1)
        #expect(settings.currentProfile == firstID)
    }

    @Test("Profile name uniqueness and limit")
    func profileNamesAndLimit() throws {
        resetEnvironment()
        let settings = Self.settings

        for _ in 0..<10 {
            settings.createProfile()
        }

        #expect(settings.availableProfiles.count == 10)
        let names = settings.availableProfiles.map(\.name)
        #expect(Set(names).count == names.count)

        settings.createProfile()
        #expect(settings.availableProfiles.count == 10)
    }

    @Test("Switching to invalid profile throws")
    func switchInvalidProfile() throws {
        resetEnvironment()
        let settings = Self.settings
        settings.createProfile()
        let invalid = UUID()
        do {
            try settings.switchProfile(to: invalid)
            #expect(false)
        } catch Settings.ProfileError.notFound {
            #expect(true)
        }
    }

    @Test("Deleting only profile keeps file")
    func deleteOnlyProfile() throws {
        resetEnvironment()
        let settings = Self.settings
        settings.createProfile()
        let id = settings.currentProfile
        settings.deleteCurrentProfile()
        #expect(settings.availableProfiles.count == 1)
        #expect(settings.currentProfile == id)
    }
}

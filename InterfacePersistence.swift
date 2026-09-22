import Foundation

@MainActor
protocol InterfacePersisting {
    func getInterfaces() -> [Interface]
    func saveInterfaces(_ interfaces: [Interface])
}

@MainActor
final class UserDefaultsInterfacePersistence: InterfacePersisting {
    private let key = "wakefox.interfaces"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: "io.github.tyoubin.wakefox") ?? .standard) {
        self.defaults = defaults
    }

    func getInterfaces() -> [Interface] {
        guard let data = defaults.data(forKey: key),
              let interfaces = try? JSONDecoder().decode([Interface].self, from: data) else {
            return []
        }
        return interfaces
    }

    func saveInterfaces(_ interfaces: [Interface]) {
        guard let data = try? JSONEncoder().encode(interfaces) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    private let persistence: InterfacePersisting

    init(persistence: InterfacePersisting = UserDefaultsInterfacePersistence()) {
        self.persistence = persistence
    }

    func getInterfaces() -> [Interface] {
        persistence.getInterfaces()
    }

    func saveInterfaces(_ interfaces: [Interface]) {
        persistence.saveInterfaces(interfaces)
    }
}

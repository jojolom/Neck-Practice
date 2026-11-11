//
//  NeckPracticeViewsSavedSettings.swift
//  Guitar Man
//
//  Settings that stick. A game's settings are saved as soon as they change: under its own key
//  when you opened it from the home screen, or into the plan's step (`onStepChange`) when you're
//  in Daily Practice, so the two stay separate. `SavedSetting` does the same for a single
//  value on a screen with no settings sheet, like a reference screen's key.
//

import SwiftUI

/// A game's saved settings, as the same struct a Daily Practice step keeps them in.
enum GameSettings {
    private static func storageKey(_ game: String) -> String { "settings.\(game)" }

    static func load<Settings: Decodable>(_ game: String) -> Settings? {
        UserDefaults.standard.data(forKey: storageKey(game))
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
    }

    static func save<Settings: Encodable>(_ settings: Settings, _ game: String) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: storageKey(game))
        }
    }
}

extension View {
    /// Saves a game's settings the moment they change, then runs `changed` so the game can show
    /// the change straight away (the settings sheet stays open over it).
    func savesSettings<Settings: Codable & Equatable>(
        _ settings: Settings,
        game: String,
        step onStepChange: ((Settings) -> Void)?,
        changed: @escaping () -> Void = {}
    ) -> some View {
        onChange(of: settings) { _, updated in
            if let onStepChange {
                onStepChange(updated)
            } else {
                GameSettings.save(updated, game)
            }
            changed()
        }
    }
}

/// Like `@State`, but kept between launches. For any Codable value, optionals included.
@propertyWrapper
struct SavedSetting<Value: Codable>: DynamicProperty {
    @AppStorage private var data: Data?
    private let initial: Value

    init(wrappedValue: Value, _ key: String) {
        initial = wrappedValue
        _data = AppStorage(key)
    }

    var wrappedValue: Value {
        get { data.flatMap { try? JSONDecoder().decode(Value.self, from: $0) } ?? initial }
        nonmutating set { data = try? JSONEncoder().encode(newValue) }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

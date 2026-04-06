//
//  KeychainStoreTests.swift
//  TimeTrackingTests
//

import Testing
@testable import TimeTracking

struct KeychainStoreTests {

    // Clean up a key before and after each test so tests don't bleed into each other.
    private func clean(_ key: KeychainStore.Key) {
        KeychainStore.delete(key)
    }

    // MARK: - get

    @Test func getMissingKeyReturnsNil() {
        clean(.mqttUsername)
        #expect(KeychainStore.get(.mqttUsername) == nil)
    }

    @Test func getReturnsStoredString() {
        defer { clean(.mqttUsername) }
        KeychainStore.set("alice", for: .mqttUsername)
        #expect(KeychainStore.get(.mqttUsername) == "alice")
    }

    @Test func getPreservesSpecialCharacters() {
        defer { clean(.mqttPassword) }
        KeychainStore.set("p@$$w0rd!#€", for: .mqttPassword)
        #expect(KeychainStore.get(.mqttPassword) == "p@$$w0rd!#€")
    }

    // MARK: - set

    @Test func setStoresValue() {
        defer { clean(.mqttPassword) }
        KeychainStore.set("secret", for: .mqttPassword)
        #expect(KeychainStore.get(.mqttPassword) == "secret")
    }

    @Test func setOverwritesExistingValue() {
        defer { clean(.mqttUsername) }
        KeychainStore.set("first", for: .mqttUsername)
        KeychainStore.set("second", for: .mqttUsername)
        #expect(KeychainStore.get(.mqttUsername) == "second")
    }

    @Test func setEmptyStringStoresEmpty() {
        defer { clean(.mqttUsername) }
        KeychainStore.set("", for: .mqttUsername)
        #expect(KeychainStore.get(.mqttUsername) == "")
    }

    // MARK: - delete

    @Test func deleteRemovesStoredItem() {
        KeychainStore.set("toDelete", for: .mqttPassword)
        KeychainStore.delete(.mqttPassword)
        #expect(KeychainStore.get(.mqttPassword) == nil)
    }

    @Test func deleteOnMissingKeyDoesNotCrash() {
        clean(.mqttUsername)
        KeychainStore.delete(.mqttUsername) // should not throw or crash
    }

    @Test func deleteIsIdempotent() {
        KeychainStore.set("x", for: .mqttUsername)
        KeychainStore.delete(.mqttUsername)
        KeychainStore.delete(.mqttUsername) // second delete must not crash
        #expect(KeychainStore.get(.mqttUsername) == nil)
    }

    // MARK: - Key isolation

    @Test func usernameAndPasswordAreStoredIndependently() {
        defer { clean(.mqttUsername); clean(.mqttPassword) }
        KeychainStore.set("user", for: .mqttUsername)
        KeychainStore.set("pass", for: .mqttPassword)
        #expect(KeychainStore.get(.mqttUsername) == "user")
        #expect(KeychainStore.get(.mqttPassword) == "pass")
    }

    @Test func deletingUsernameDoesNotAffectPassword() {
        defer { clean(.mqttUsername); clean(.mqttPassword) }
        KeychainStore.set("user", for: .mqttUsername)
        KeychainStore.set("pass", for: .mqttPassword)
        KeychainStore.delete(.mqttUsername)
        #expect(KeychainStore.get(.mqttUsername) == nil)
        #expect(KeychainStore.get(.mqttPassword) == "pass")
    }
}

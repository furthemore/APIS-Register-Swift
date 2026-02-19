//
//  ConfigLoader.swift
//  Register
//

import ComposableArchitecture
import Dependencies
import Foundation
import os

struct Config: Equatable, Codable {
  var terminalName: String
  var endpoint: URL
  var token: String
  var webViewUrl: URL
  var themeColor: String

  var mqttHost: String
  var mqttPort: Int
  var mqttUsername: String
  var mqttPassword: String
  var mqttPrefix: String

  var squareApplicationId: String
  var squareLocationId: String

  static let mock = Self(
    terminalName: "mockterminal",
    endpoint: URL(string: "http://example.com")!,
    token: "MOCK-TOKEN",
    webViewUrl: URL(string: "http://example.com")!,
    themeColor: "#000000",
    mqttHost: "http://example.com",
    mqttPort: 443,
    mqttUsername: "MOCK-USERNAME",
    mqttPassword: "MOCK-PASSWORD",
    mqttPrefix: "MOCK-TOPIC",
    squareApplicationId: "MOCK-SQUARE-APPLICATION-ID",
    squareLocationId: "MOCK-SQUARE-LOCATION-ID"
  )
}

enum ConfigError: LocalizedError {
  case missingDocumentDirectory
  case missingConfig

  var errorDescription: String? {
    switch self {
    case .missingDocumentDirectory:
      return "Application documents directory was missing."
    case .missingConfig:
      return "No configuration file was found."
    }
  }
}

@DependencyClient
struct ConfigClient {
  var load: () async throws -> Config?
  var save: (Config) async throws -> Void
  var clear: () async throws -> Void
}

extension ConfigClient: TestDependencyKey {
  static var previewValue = Self(
    load: { .mock },
    save: { _ in },
    clear: {}
  )

  static var testValue = Self()
}

extension ConfigClient: DependencyKey {
  private static let logger = Logger(subsystem: Register.bundle, category: "ConfigLoader")
  private static let fileManager = FileManager.default

  private static func configFilePath() throws -> URL {
    guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).last else {
      throw ConfigError.missingDocumentDirectory
    }

    let path = url.appending(path: "config.json")
    logger.debug("Got config path: \(path, privacy: .public)")
    return path
  }

  static var liveValue = Self(
    load: {
      logger.debug("Attempting to read config")
      let configPath = try configFilePath()
      if !fileManager.fileExists(atPath: configPath.path(percentEncoded: false)) {
        logger.info("Existing config did not exist")
        return nil
      }

      let configData = try Data(contentsOf: configPath)

      let decoder = JSONDecoder()
      let config = try decoder.decode(Config.self, from: configData)
      logger.info("Read existing configuration")
      return config
    },
    save: { config in
      logger.debug("Attempting to save config")
      let configPath = try configFilePath()

      let encoder = JSONEncoder()
      let configData = try encoder.encode(config)

      UserDefaults.standard.set(config.squareApplicationId, forKey: "squareApplicationId")

      try configData.write(to: configPath, options: .completeFileProtection)
      logger.info("Successfully saved config")
    },
    clear: {
      logger.debug("Attempting to clear config")
      let configPath = try configFilePath()
      try fileManager.removeItem(at: configPath)
      UserDefaults.standard.removeObject(forKey: "squareApplicationId")
      logger.info("Successfully cleared config")
    }
  )
}

extension DependencyValues {
  var config: ConfigClient {
    get { self[ConfigClient.self] }
    set { self[ConfigClient.self] = newValue }
  }
}

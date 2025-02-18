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
  var host: String
  var token: String
  var key: String
  var locationId: String?
  var webViewURL: URL?
  var themeColor: String?

  var mqttHost: String
  var mqttPort: Int
  var mqttUserName: String
  var mqttPassword: String
  var mqttTopic: String

  var squareAccessToken: String?
  var squareRefreshToken: String?

  var urlOrFallback: URL {
    webViewURL ?? Register.fallbackURL
  }

  static let empty = Self(
    terminalName: "",
    host: "",
    token: "",
    key: "",
    locationId: nil,
    webViewURL: nil,
    themeColor: nil,
    mqttHost: "",
    mqttPort: -1,
    mqttUserName: "",
    mqttPassword: "",
    mqttTopic: "",
    squareAccessToken: nil,
    squareRefreshToken: nil
  )

  static let mock = Self(
    terminalName: "mockterminal",
    host: "http://example.com",
    token: "MOCK-TOKEN",
    key: "MOCK-KEY",
    locationId: "MOCK-LOCATION",
    webViewURL: URL(string: "http://example.com"),
    themeColor: nil,
    mqttHost: "http://example.com",
    mqttPort: 443,
    mqttUserName: "MOCK-USERNAME",
    mqttPassword: "MOCK-PASSWORD",
    mqttTopic: "MOCK-TOPIC",
    squareAccessToken: "MOCK-SQUARE-ACCESS",
    squareRefreshToken: "MOCK-SQUARE-REFRESH"
  )

  func withSquareTokens(accessToken: String, refreshToken: String) -> Self {
    var config = self
    config.squareAccessToken = accessToken
    config.squareRefreshToken = refreshToken
    return config
  }
}

enum ConfigError: LocalizedError {
  case missingDocumentDirectory

  var errorDescription: String? {
    switch self {
    case .missingDocumentDirectory:
      return "Application documents directory was missing."
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

      try configData.write(to: configPath, options: .completeFileProtection)
      logger.info("Successfully saved config")
    },
    clear: {
      logger.debug("Attempting to clear config")
      let configPath = try configFilePath()
      try fileManager.removeItem(at: configPath)
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

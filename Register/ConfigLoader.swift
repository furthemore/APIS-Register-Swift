//
//  ConfigLoader.swift
//  Register
//

import Foundation
import os

struct Config: Equatable, Codable {
  var terminalName: String
  var host: String
  var token: String
  var key: String
  var webViewURL: URL?

  var urlOrFallback: URL {
    webViewURL ?? Register.fallbackURL
  }

  static let empty = Self(terminalName: "", host: "", token: "", key: "", webViewURL: nil)
}

struct ConfigLoader {
  private static let logger = Logger(subsystem: "net.syfaro.Register", category: "ConfigLoader")

  enum ConfigError: Error {
    case missingDocumentDirectory
  }

  private static let fileManager = FileManager.default

  private static func configFilePath() throws -> URL {
    guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).last else {
      throw ConfigError.missingDocumentDirectory
    }

    let path = url.appending(path: "config.json")
    Self.logger.debug("Got config path: \(path, privacy: .public)")
    return path
  }

  static func loadConfig() async throws -> Config? {
    Self.logger.debug("Attempting to read config")

    let configPath = try configFilePath()
    if !fileManager.fileExists(atPath: configPath.path(percentEncoded: false)) {
      Self.logger.info("Existing config did not exist")
      return nil
    }

    let configData = try Data(contentsOf: configPath)

    let decoder = JSONDecoder()
    let config = try decoder.decode(Config.self, from: configData)
    Self.logger.info("Read existing configuration")

    return config
  }

  static func saveConfig(_ config: Config) async throws {
    Self.logger.debug("Attempting to save config")

    let configPath = try configFilePath()

    let encoder = JSONEncoder()
    let configData = try encoder.encode(config)

    try configData.write(to: configPath, options: .completeFileProtection)

    Self.logger.info("Successfully saved config")
  }
}

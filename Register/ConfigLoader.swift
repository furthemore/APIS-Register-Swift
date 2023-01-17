//
//  ConfigLoader.swift
//  Register
//

import Foundation

struct Config: Equatable, Codable {
  var terminalName: String
  var host: String
  var token: String
  var key: String
  
  static let empty = Self(terminalName: "", host: "", token: "", key: "")
}

struct ConfigLoader {
  enum ConfigError: Error {
    case missingDocumentDirectory
  }
  
  private static let fileManager = FileManager.default
  
  private static func configFilePath() throws -> URL {
    guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).last else {
      throw ConfigError.missingDocumentDirectory
    }
    
    return url.appending(path: "config.json")
  }
  
  static func loadConfig() async throws -> Config? {
    let configPath = try configFilePath()
    if !fileManager.fileExists(atPath: configPath.path(percentEncoded: false)) {
      return nil
    }

    let configData = try Data(contentsOf: configPath)
    
    let decoder = JSONDecoder()
    let config = try decoder.decode(Config.self, from: configData)
    
    return config
  }
  
  static func saveConfig(_ config: Config) async throws {
    let configPath = try configFilePath()
    
    let encoder = JSONEncoder()
    let configData = try encoder.encode(config)
    
    try configData.write(to: configPath, options: .completeFileProtection)
  }
}

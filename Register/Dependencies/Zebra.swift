//
//  Zebra.swift
//  Register
//

import Combine
import ComposableArchitecture
import os

enum ZebraError: Error {
  case noPrinters
  case unknownPrinter
}

enum ZebraEvent: Equatable {
  case connected(String)
  case disconnected(String)
  case error(ZebraPrintError)
}

@DependencyClient
struct ZebraClient {
  var connectedPrinters: () async -> [String] = { [] }
  var status: (String) async throws -> ZebraPrintStatus
  var print: (Data, String?) async throws -> Void
  var events: () -> AsyncStream<ZebraEvent> = { AsyncStream.never }
}

extension ZebraClient: DependencyKey {
  static var liveValue: ZebraClient {
    let events = PassthroughSubject<ZebraEvent, Never>()
    let connections = ZebraConnections(events: events)

    return Self(
      connectedPrinters: {
        return await connections.connectedAccessories
      },
      status: { serialNumber in
        return try await connections.status(serialNumber: serialNumber)
      },
      print: { data, serialNumber in
        try await connections.print(data: data, serialNumber: serialNumber)
      },
      events: {
        return AsyncStream { continuation in
          let subscription = events.sink { value in
            continuation.yield(value)
          }

          continuation.onTermination = { _ in subscription.cancel() }
        }
      })
  }
}

private actor ZebraConnections {
  internal static let logger = Logger(subsystem: Register.bundle, category: "Zebra")

  private let events: PassthroughSubject<ZebraEvent, Never>
  private var connections: [String: ZebraConnectedPrinter] = [:]

  var connectedAccessories: [String] { Array(connections.keys) }

  init(events: PassthroughSubject<ZebraEvent, Never>) {
    Self.logger.debug("Creating Zebra connections manager")

    self.events = events

    NotificationCenter.default
      .addObserver(
        self,
        selector: #selector(self.deviceConnected),
        name: .EAAccessoryDidConnect,
        object: nil
      )

    NotificationCenter.default
      .addObserver(
        self,
        selector: #selector(self.deviceDisconnected),
        name: .EAAccessoryDidDisconnect,
        object: nil
      )

    Task.detached {
      for accessory in ZebraConnectedPrinter.connectedAccessories {
        Self.logger.debug("Connecting to existing accessory \(accessory.serialNumber)")
        try await self.connect(serialNumber: accessory.serialNumber)
      }
    }
  }

  func status(serialNumber: String) async throws -> ZebraPrintStatus {
    if let connection = connections[serialNumber] {
      return try await connection.status()
    } else {
      throw ZebraError.unknownPrinter
    }
  }

  func print(data: Data, serialNumber: String? = nil) async throws {
    let connection = try getConnection(serialNumber: serialNumber)
    Self.logger.debug(
      "Sending \(data.count, privacy: .public) bytes to printer \(connection.serialNumber)")
    try await connection.write(data)
  }

  private func getConnection(serialNumber: String? = nil) throws -> ZebraConnectedPrinter {
    if let serialNumber {
      if let connection = self.connections[serialNumber] {
        return connection
      } else {
        throw ZebraError.unknownPrinter
      }
    } else if let connection = connections.randomElement() {
      return connection.value
    } else {
      throw ZebraError.noPrinters
    }
  }

  private func connect(serialNumber: String) throws {
    guard connections[serialNumber] == nil else {
      return
    }

    let connection = try ZebraConnectedPrinter(accessorySerialNumber: serialNumber)
    self.connections[serialNumber] = connection
    events.send(.connected(serialNumber))
  }

  private func disconnect(serialNumber: String) async throws {
    if let connection = self.connections.removeValue(forKey: serialNumber) {
      await connection.close()
      self.events.send(.disconnected(serialNumber))
    }
  }

  @objc private nonisolated func deviceConnected(_ notification: Notification) {
    Self.logger.debug("Got connection notification, \(notification)")

    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else {
      Self.logger.error("Got notification with no accessory")
      return
    }

    guard accessory.protocolStrings.contains(ZebraConnectedPrinter.accessoryPrefix) else {
      Self.logger.debug("Accessory did not have required protocol")
      return
    }

    Task.detached {
      try await self.connect(serialNumber: accessory.serialNumber)
    }
  }

  @objc private nonisolated func deviceDisconnected(_ notification: Notification) {
    Self.logger.debug("Got disconnection notification, \(notification)")

    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else {
      Self.logger.error("Got notification with no accessory")
      return
    }

    Task.detached {
      try await self.disconnect(serialNumber: accessory.serialNumber)
    }
  }
}

extension DependencyValues {
  var zebra: ZebraClient {
    get { self[ZebraClient.self] }
    set { self[ZebraClient.self] = newValue }
  }
}

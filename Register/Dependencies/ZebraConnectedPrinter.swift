//
//  ZebraConnectedPrinter.swift
//  Register
//

import ExternalAccessory

enum ZebraPrintError: Error {
  case failedToConnect
}

struct ZebraPrintStatus: Equatable {
  let isReadyToPrint: Bool
  let isHeadOpen: Bool
  let isPaperOut: Bool
  let isPaused: Bool
}

actor ZebraConnectedPrinter {
  static let accessoryPrefix = "com.zebra.rawport"

  static var connectedAccessories: [EAAccessory] {
    EAAccessoryManager.shared().connectedAccessories.filter {
      $0.protocolStrings.contains(accessoryPrefix)
    }
  }

  public let serialNumber: String

  private let connection: NSObject & ZebraPrinterConnection
  private let printer: ZebraPrinter

  init(accessorySerialNumber serialNumber: String) throws {
    self.serialNumber = serialNumber
    connection = MfiBtPrinterConnection(serialNumber: serialNumber)

    if !connection.open() {
      throw ZebraPrintError.failedToConnect
    }

    printer = try ZebraPrinterFactory.getInstance(connection)
  }

  public func close() {
    connection.close()
  }

  public var isConnected: Bool {
    connection.isConnected()
  }

  public func status() throws -> ZebraPrintStatus {
    let status = try printer.getCurrentStatus()

    return ZebraPrintStatus(
      isReadyToPrint: status.isReadyToPrint,
      isHeadOpen: status.isHeadOpen,
      isPaperOut: status.isPaperOut,
      isPaused: status.isPaused
    )
  }

  public func write(_ data: Data) throws {
    var error: NSError? = nil
    connection.write(data, error: &error)
    if let error {
      throw error
    }
  }

  deinit {
    connection.close()
  }
}

//
//  ZebraScan.swift
//  Register
//

import Combine
import ComposableArchitecture
import CoreGraphics
import ZebraScannerSDK

actor ZebraScan {
  private let apiInstance: any ISbtSdkApi
  private let delegate: ZebraScanDelegate

  init(events: PassthroughSubject<ZebraScanEvent, Never>) {
    delegate = ZebraScanDelegate(events: events)

    apiInstance = SbtSdkFactory.createSbtSdkApiInstance()
    apiInstance.sbtSetDelegate(delegate)
    apiInstance.sbtSubsribe(
      forEvents: Int32(SBT_EVENT_SCANNER_APPEARANCE) | Int32(SBT_EVENT_SCANNER_DISAPPEARANCE)
        | Int32(SBT_EVENT_SESSION_ESTABLISHMENT) | Int32(SBT_EVENT_SESSION_TERMINATION)
        | Int32(SBT_EVENT_BARCODE) | Int32(SBT_EVENT_RAW_DATA)
    )
    apiInstance.sbtEnableAvailableScannersDetection(true)
    apiInstance.sbtSetOperationalMode(Int32(SBT_OPMODE_ALL))
    apiInstance.sbtAutoConnectToLastConnectedScanner(onAppRelaunch: true)
  }

  func generatePairingImage(frame: CGRect) -> CGImage? {
    return self.apiInstance.sbtGetPairingBarcode(
      BARCODE_TYPE_STC,
      withComProtocol: STC_SSI_BLE,
      withSetDefaultStatus: SETDEFAULT_NO,
      withImageFrame: frame
    )?.cgImage
  }

  func disconnectScanner(_ scannerId: Int32) throws {
    let result = apiInstance.sbtTerminateCommunicationSession(scannerId)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
  }

  func enableAutomaticConnection(_ enable: Bool, scannerId: Int32) throws {
    let result = apiInstance.sbtEnableAutomaticSessionReestablishment(enable, forScanner: scannerId)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
  }

  func enableAutomaticConnectOnLaunch(_ enable: Bool) throws {
    let result = apiInstance.sbtAutoConnectToLastConnectedScanner(onAppRelaunch: enable)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
  }

  func availableScanners() throws -> [ScannerInfo] {
    var scanners: NSMutableArray? = NSMutableArray()
    let result = apiInstance.sbtGetAvailableScannersList(&scanners)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
    return scanners?.compactMap { $0 as? SbtScannerInfo }.map(ScannerInfo.init) ?? []
  }

  func activeScanners() throws -> [ScannerInfo] {
    var scanners: NSMutableArray? = NSMutableArray()
    let result = apiInstance.sbtGetActiveScannersList(&scanners)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
    return scanners?.compactMap { $0 as? SbtScannerInfo }.map(ScannerInfo.init) ?? []
  }

  func connect(_ id: Int32) throws {
    let result = apiInstance.sbtEstablishCommunicationSession(id)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
  }

  func disconnect(_ id: Int32) throws {
    let result = apiInstance.sbtTerminateCommunicationSession(id)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
  }

  func enableAutomaticConnect(_ enable: Bool, scannerId: Int32) throws {
    let result = apiInstance.sbtEnableAutomaticSessionReestablishment(enable, forScanner: scannerId)
    if result != SBT_RESULT_SUCCESS {
      throw ZebraScanError(result)
    }
  }
}

enum ZebraScanError: UInt32, Error {
  case failure = 0x01
  case scannerNotAvailable = 0x02
  case scannerNotActive = 0x03
  case invalidParams = 0x04
  case responseTimeout = 0x05
  case opcodeNotSupported = 0x06
  case scannerNoSupport = 0x07
  case btAddressNotSet = 0x08
  case scannerNotConnectedStc = 0x09
  case invalidConfigFile = 0x259
  case incompatibleConfigFile = 0x25A

  init(_ result: SBT_RESULT) {
    self.init(rawValue: result.rawValue)!
  }
}

enum ZebraScanEvent {
  case scannerAppeared(ScannerInfo)
  case scannerDisappeared(Int32)
  case sessionEstablished(ScannerInfo)
  case sessionTerminated(Int32)
  case barcodeData(scannerId: Int32, barcodeType: Int32, data: Data)
}

struct ScannerInfo: Equatable, Identifiable {
  let id: Int32
  let connectionType: Int32
  var autoReconnect: Bool
  var active: Bool
  var available: Bool
  let stcConnected: Bool
  let name: String
  let model: String

  init(_ scanner: SbtScannerInfo) {
    id = scanner.getScannerID()
    connectionType = scanner.getConnectionType()
    autoReconnect = scanner.getAutoCommunicationSessionReestablishment()
    active = scanner.isActive()
    available = scanner.isAvailable()
    stcConnected = scanner.isStcConnected()
    name = scanner.getScannerName()
    model = scanner.getScannerModel()
  }
}

class ZebraScanDelegate: NSObject, ISbtSdkApiDelegate {
  let events: PassthroughSubject<ZebraScanEvent, Never>

  init(events: PassthroughSubject<ZebraScanEvent, Never>) {
    self.events = events
  }

  func sbtEventScannerAppeared(_ availableScanner: SbtScannerInfo!) {
    events.send(.scannerAppeared(.init(availableScanner)))
  }

  func sbtEventScannerDisappeared(_ scannerID: Int32) {
    events.send(.scannerDisappeared(scannerID))
  }

  func sbtEventCommunicationSessionEstablished(_ activeScanner: SbtScannerInfo!) {
    events.send(.sessionEstablished(.init(activeScanner)))
  }

  func sbtEventCommunicationSessionTerminated(_ scannerID: Int32) {
    events.send(.sessionTerminated(scannerID))
  }

  func sbtEventBarcodeData(_ barcodeData: Data!, barcodeType: Int32, fromScanner scannerID: Int32) {
    events.send(.barcodeData(scannerId: scannerID, barcodeType: barcodeType, data: barcodeData))
  }

  func sbtEventBarcode(_ barcodeData: String!, barcodeType: Int32, fromScanner scannerID: Int32) {}
  func sbtEventFirmwareUpdate(_ fwUpdateEventObj: FirmwareUpdateEvent!) {}
}

@DependencyClient
struct ZebraScanClient {
  var generatePairingImage: (CGRect) async -> CGImage?
  var availableScanners: () async throws -> [ScannerInfo]
  var activeScanners: () async throws -> [ScannerInfo]
  var connect: (Int32) async throws -> Void
  var disconnect: (Int32) async throws -> Void
  var enableAutomaticConnect: (Int32, Bool) async throws -> Void
  var events: () -> AsyncStream<ZebraScanEvent> = { AsyncStream.never }
}

extension ZebraScanClient: DependencyKey {
  static var liveValue: ZebraScanClient {
    let events = PassthroughSubject<ZebraScanEvent, Never>()
    let scan = ZebraScan(events: events)

    return Self(
      generatePairingImage: { frame in
        return await scan.generatePairingImage(frame: frame)
      },
      availableScanners: {
        return try await scan.availableScanners()
      },
      activeScanners: {
        return try await scan.activeScanners()
      },
      connect: { id in
        return try await scan.connect(id)
      },
      disconnect: { id in
        return try await scan.disconnect(id)
      },
      enableAutomaticConnect: { id, enable in
        return try await scan.enableAutomaticConnect(enable, scannerId: id)
      },
      events: {
        return AsyncStream { continuation in
          let subscription = events.sink { value in
            continuation.yield(value)
          }

          continuation.onTermination = { _ in subscription.cancel() }
        }
      }
    )
  }
}

extension DependencyValues {
  var zebraScan: ZebraScanClient {
    get { self[ZebraScanClient.self] }
    set { self[ZebraScanClient.self] = newValue }
  }
}

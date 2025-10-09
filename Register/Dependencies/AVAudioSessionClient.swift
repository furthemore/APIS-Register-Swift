//
//  AVAudioSessionClient.swift
//  Register
//

import AVFoundation
import ComposableArchitecture

enum RecordPermission: Equatable {
  case undetermined, granted, denied

  init(_ permission: AVAudioApplication.recordPermission) {
    switch permission {
    case .undetermined:
      self = .undetermined
    case .granted:
      self = .granted
    default:
      self = .denied
    }
  }
}

@DependencyClient
struct AVAudioSessionClient {
  var recordPermission: () -> RecordPermission = { .denied }
  var requestRecordPermission: () -> Effect<RecordPermission> = { .none }
}

extension AVAudioSessionClient: TestDependencyKey {
  static var previewValue = Self(
    recordPermission: { .granted },
    requestRecordPermission: { .none }
  )

  static var testValue = Self()
}

extension AVAudioSessionClient: DependencyKey {
  static var liveValue = Self(
    recordPermission: { RecordPermission(AVAudioApplication.shared.recordPermission) },
    requestRecordPermission: {
      return .run { send in
        let permission = await withCheckedContinuation { cont in
          AVAudioApplication.requestRecordPermission { resp in
            let permission: AVAudioApplication.recordPermission = resp ? .granted : .denied
            cont.resume(with: .success(RecordPermission(permission)))
          }
        }
        await send(permission)
      }
    }
  )
}

extension DependencyValues {
  var avAudioSession: AVAudioSessionClient {
    get { self[AVAudioSessionClient.self] }
    set { self[AVAudioSessionClient.self] = newValue }
  }
}

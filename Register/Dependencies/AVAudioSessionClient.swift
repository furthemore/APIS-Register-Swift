//
//  AVAudioSessionClient.swift
//  Register
//

import AVFoundation
import ComposableArchitecture

enum RecordPermission: Equatable {
  case undetermined, granted, denied

  init(_ permission: AVAudioSession.RecordPermission) {
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

struct AVAudioSessionClient {
  var recordPermission: () -> RecordPermission
  var requestRecordPermission: () -> EffectTask<RecordPermission>
}

extension AVAudioSessionClient: TestDependencyKey {
  static var previewValue = Self(
    recordPermission: { .granted },
    requestRecordPermission: { .none }
  )

  static var testValue = Self(
    recordPermission: unimplemented("\(Self.self).denied"),
    requestRecordPermission: unimplemented("\(Self.self).requestRecordPermission")
  )
}

extension AVAudioSessionClient: DependencyKey {
  static var liveValue = Self(
    recordPermission: { RecordPermission(AVAudioSession.sharedInstance().recordPermission) },
    requestRecordPermission: {
      return .task {
        return await withCheckedContinuation { cont in
          AVAudioSession.sharedInstance().requestRecordPermission { resp in
            let permission: AVAudioSession.RecordPermission = resp ? .granted : .denied
            cont.resume(with: .success(RecordPermission(permission)))
          }
        }
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

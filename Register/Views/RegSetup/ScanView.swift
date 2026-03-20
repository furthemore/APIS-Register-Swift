//
//  ScanView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct ScanFeature {
  @Dependency(\.zebraScan) var zebraScan

  @ObservableState
  struct State: Equatable {
    var pairingImage: CGImage? = nil
    var scanners: IdentifiedArrayOf<ScannerInfo> = .init()
    var recentScans: [String] = []
  }

  enum Action {
    case appeared
    case disappeared
    case resized(CGSize)
    case loadedImage(CGImage?)
    case loadedScanners([ScannerInfo])
    case event(ZebraScanEvent)
    case connect(Int32)
    case disconnect(Int32)
    case changedAutoReconnect(Int32, Bool)
    case addScan(String)
    case removeScan(String)
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .appeared:
        return .run { send in
          let available = try! await zebraScan.availableScanners()
          let active = try! await zebraScan.activeScanners()

          let scanners = (active + available).sorted { $0.name < $1.name }
          await send(.loadedScanners(scanners))
        }.animation(.easeIn)

      case .disappeared:
        state.pairingImage = nil
        return .none

      case .resized(let size):
        return .run { send in
          await send(
            .loadedImage(
              await zebraScan.generatePairingImage(
                CGRect(
                  origin: .zero,
                  size: .init(
                    width: size.width,
                    height: size.width * 1 / 3
                  )
                )
              )
            )
          )
        }.animation(.easeIn)

      case .loadedImage(let image):
        state.pairingImage = image
        return .none

      case .loadedScanners(let scanners):
        state.scanners = .init(uniqueElements: scanners)
        return .none

      case .event(.scannerAppeared(let info)):
        state.scanners.updateOrAppend(info)
        return .none
      case .event(.scannerDisappeared(let id)):
        state.scanners.remove(id: id)
        return .none
      case .event(.sessionEstablished(let info)):
        state.scanners.updateOrAppend(info)
        return .none
      case .event(.sessionTerminated(let id)):
        state.scanners[id: id]?.active = false
        return .none
      case .event(.barcodeData(scannerId: _, barcodeType: _, data: let data)):
        if let value = String(data: data, encoding: .utf8) {
          return .send(.addScan(value), animation: .easeIn)
        }
        return .none
      case .event:
        return .none

      case .connect(let id):
        return .run { send in
          do {
            try await zebraScan.connect(id)
            try await zebraScan.enableAutomaticConnect(id, true)
          } catch {}
          await send(.changedAutoReconnect(id, true))
        }.animation(.easeIn)

      case .disconnect(let id):
        return .run { _ in
          try? await zebraScan.disconnect(id)
        }.animation(.easeIn)

      case .changedAutoReconnect(let id, let enabled):
        state.scanners[id: id]?.autoReconnect = enabled
        return .none

      case .addScan(let value):
        if let index = state.recentScans.firstIndex(of: value) {
          state.recentScans.remove(at: index)
          state.recentScans.insert(value, at: 0)
        } else {
          if state.recentScans.count >= 10 {
            state.recentScans.removeLast()
          }
          state.recentScans.insert(value, at: 0)
        }

        return .none

      case .removeScan(let value):
        state.recentScans.removeAll { $0 == value }
        return .none
      }
    }

  }
}

struct ScanView: View {
  @Environment(\.displayScale) var displayScale
  @Bindable var store: StoreOf<ScanFeature>

  var body: some View {
    NavigationStack {
      Form {
        Section {
          GeometryReader { proxy in
            VStack {
              if let image = store.pairingImage {
                Image(uiImage: UIImage(cgImage: image, scale: displayScale, orientation: .up))
                  .renderingMode(.original)
              }
            }
            .frame(maxWidth: .infinity)
            .onChange(of: proxy.size, initial: true) { _, newValue in
              if newValue.width > 0 {
                store.send(
                  .resized(
                    .init(
                      width: newValue.width * displayScale,
                      height: newValue.height * displayScale
                    )
                  )
                )
              }
            }
          }
          .frame(height: CGFloat(store.pairingImage?.height ?? 0) / displayScale)
          .padding(8)
          .listRowBackground(Color.white)
        } header: {
          Text("Scan To Connect")
        }

        Section {
          ForEach(store.scanners) { scanner in
            HStack {
              Text(scanner.name)
              Spacer()
              Image(systemName: scanner.active ? "checkmark" : "xmark")
            }.swipeActions(edge: .trailing) {
              if scanner.active {
                Button {
                  store.send(.disconnect(scanner.id))
                } label: {
                  Label("Disconnect", systemImage: "xmark")
                }
              } else if scanner.available {
                Button {
                  store.send(.connect(scanner.id))
                } label: {
                  Label("Connect", systemImage: "link")
                }
              }
            }
          }
        } header: {
          Text("Paired Devices")
        }
        .contentTransition(.symbolEffect(.automatic))

        Section {
          ForEach(store.recentScans, id: \.self) { scan in
            NavigationLink {
              VStack {
                ScrollView {
                  Text(scan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)

                Button("Copy", systemImage: "clipboard") {
                  UIPasteboard.general.string = scan
                }
              }
              .navigationTitle("Scan")
            } label: {
              Text(scan)
                .lineLimit(3)
                .truncationMode(.tail)
                .contextMenu {
                  Button("Copy", systemImage: "clipboard") {
                    UIPasteboard.general.string = scan
                  }
                }
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                store.send(.removeScan(scan))
              } label: {
                Label("Remove", systemImage: "trash")
              }
            }
          }
        } header: {
          Text("Recent Scans")
        }
      }
      .navigationTitle("Scanners")
      .navigationBarTitleDisplayMode(.inline)
    }
    .onAppear { store.send(.appeared) }
    .onDisappear { store.send(.disappeared) }
  }
}

#Preview {
  ScanView(
    store: Store(initialState: .init()) {
      ScanFeature()
    }
  )
}

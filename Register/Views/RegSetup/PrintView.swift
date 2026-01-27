//
//  Print.swift
//  Register
//

import ComposableArchitecture
import SwiftUI

struct Printer: Identifiable, Equatable {
  var serialNumber: String
  var status: ZebraPrintStatus?

  var id: String { serialNumber }

  init(serialNumber: String, status: ZebraPrintStatus? = nil) {
    self.serialNumber = serialNumber
    self.status = status
  }
}

@Reducer
struct PrintFeature {
  @Dependency(\.zebra) var zebra

  @ObservableState
  struct State: Equatable {
    var connectedPrinters: IdentifiedArrayOf<Printer> = []
    var isRefreshing = false

    mutating func refresh(zebra: ZebraClient) -> Effect<Action> {
      self.isRefreshing = true

      return .run { send in
        var updatedPrinters: IdentifiedArrayOf<Printer> = []
        for serialNumber in await zebra.connectedPrinters() {
          let status = try? await zebra.status(serialNumber)
          updatedPrinters.append(.init(serialNumber: serialNumber, status: status))
        }

        await send(.loadedPrinters(updatedPrinters))
      }
    }
  }

  enum Action {
    case appeared
    case refresh
    case loadedPrinters(IdentifiedArrayOf<Printer>)
    case addedPrinter(Printer)
    case removedPrinter(String)
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .appeared:
        return .merge(
          .run { send in
            for await event in zebra.events() {
              switch event {
              case .connected(let serialNumber):
                await send(.addedPrinter(.init(serialNumber: serialNumber)))
                let status = try? await zebra.status(serialNumber)
                await send(.addedPrinter(.init(serialNumber: serialNumber, status: status)))
              case .disconnected(let serialNumber):
                await send(.removedPrinter(serialNumber))
              case .error(let error):
                throw error
              }
            }
          },
          .concatenate(
            .run { send in
              let printers = await zebra.connectedPrinters().map { Printer(serialNumber: $0) }
              await send(.loadedPrinters(.init(uniqueElements: printers)))
            },
            state.refresh(zebra: zebra)
          )
        )
        .animation(.easeInOut)

      case .refresh:
        return state.refresh(zebra: zebra).animation(.easeInOut)

      case .loadedPrinters(let printers):
        state.isRefreshing = false
        state.connectedPrinters = printers
        return .none

      case .addedPrinter(let printer):
        state.connectedPrinters.updateOrAppend(printer)
        return .none

      case .removedPrinter(let serialNumber):
        state.connectedPrinters.remove(id: serialNumber)
        return .none
      }
    }
  }
}

struct PrintView: View {
  @Bindable var store: StoreOf<PrintFeature>

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.connectedPrinters) { printer in
          Section(printer.serialNumber) {
            if let status = printer.status {
              LocationDetailView(name: "Ready", value: status.isReadyToPrint ? "Yes" : "No")
            } else {
              LocationDetailView(name: "Status", value: "Unknown")
            }
          }
        }

        Section {
          Button {
            EAAccessoryManager
              .shared()
              .showBluetoothAccessoryPicker(withNameFilter: nil, completion: nil)
          } label: {
            Label("Pair New Device", systemImage: "plus")
          }
        }
        .navigationTitle("Printers")
        .navigationBarTitleDisplayMode(.inline)
      }
      .refreshable {
        await store.send(.refresh).finish()
      }
    }
    .onAppear { store.send(.appeared) }
  }
}

#Preview {
  PrintView(
    store: Store(initialState: .init()) {
      PrintFeature()
    })
}

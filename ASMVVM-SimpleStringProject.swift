import SwiftUI
import Combine

actor StringManager {
    enum State {
        case idle
        case loading
        case success(String)
        case failure(Error)
    }
    
    private var currentState: State = .idle
    private var continuation: AsyncStream<State>.Continuation?
    
    var stream: AsyncStream<State> {
            AsyncStream { continuation in
                self.continuation = continuation
                continuation.yield(currentState) // 初期値を必ず流す
            }
        }
        
    func fetchString() async {
        currentState = .loading
        continuation?.yield(currentState)
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待機
            
            let fetchdString = "こんにちは、ASMVVM"
            currentState = .success(fetchdString)
            continuation?.yield(currentState)
        } catch {
            currentState = .failure(error)
            continuation?.yield(currentState)
        }
    }
    
    func getCurrentString() -> String {
        switch currentState {
        case .success(let str):
            return str
        default:
            return "No String"
        }
    }
}

@MainActor
final class StringViewModel: ObservableObject {
    @Published var displayString: String = "Press the button to fetch string."
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let manager: StringManager
    private var task: Task<Void, Never>?
    
    init(manager: StringManager) {
        self.manager = manager
        startObserving()
    }
    
    deinit {
        task?.cancel()
    }
    
    private func startObserving() {
        task = Task {
            for await state in await manager.stream {
                switch state {
                case .idle:
                    isLoading = false
                    errorMessage = nil
                case .loading:
                    isLoading = true
                    errorMessage = nil
                case .success(let str):
                    isLoading = false
                    displayString = str
                    errorMessage = nil
                case .failure(let error):
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func fetchString() {
        Task {
            await manager.fetchString()
        }
    }
}

struct StringView: View {
    @StateObject private var viewModel: StringViewModel
    
    init(manager: StringManager) {
        _viewModel = StateObject(wrappedValue: StringViewModel(manager: manager))
    }
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else {
                Text(viewModel.displayString)
                    .font(.largeTitle)
                    .padding()
            }
            
            Button("Fetch String") {
                viewModel.fetchString()
            }
            .padding()
        }
        .navigationTitle("ASMVVM Example")
    }
}

@main
struct StringApp: App {
    var body: some Scene {
        WindowGroup {
            StringView(manager: StringManager())
        }
    }
}

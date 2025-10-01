
import SwiftUI
import Combine

struct Todo: Identifiable {
    let id: Int
    let title: String
}

actor TodoManager {
    enum State {
        case idle
        case loading
        case success([Todo])
        case failure(Error)
    }
    
    private var currentState: State = .idle
    private var continuation: AsyncStream<State>.Continuation?
    
    var stream: AsyncStream<State> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(self.currentState)
        }
    }
    
    func fetchTodos() async {
        currentState = .loading
        continuation?.yield(currentState)
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1sec
            
            let todos = [
                Todo(id: 1, title: "Buy groceries"),
                Todo(id: 2, title: "Walk the dog"),
                Todo(id: 3, title: "Read a book")
            ]
            currentState = .success(todos)
            continuation?.yield(currentState)
        } catch {
            currentState = .failure(error)
            continuation?.yield(currentState)
        }
    }
}

@MainActor
final class TodoViewModel: ObservableObject {
    @Published var todos: [Todo] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let manager: TodoManager
    private var task: Task<Void, Never>?
    
    init(manager: TodoManager) {
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
                case .success(let todos):
                    isLoading = false
                    self.todos = todos
                case .failure(let error):
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func fetchTodos() {
        Task {
            await manager.fetchTodos()
        }
    }
}

struct TodoView: View {
    @StateObject private var viewModel: TodoViewModel
    
    init(manager: TodoManager) {
        _viewModel = StateObject(wrappedValue: TodoViewModel(manager: manager))
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                } else if let errorMessage = viewModel.errorMessage {
                    Text("Error: \(errorMessage)")
                } else {
                    List(viewModel.todos) { todo in
                        Text(todo.title)
                    }
                }
                
                Button("reload") {
                    viewModel.fetchTodos()
                }
                .padding()
            }
            .navigationTitle("Todos")
        }
    }
}

@main
struct test2App: App {
    
    var body: some Scene {
        WindowGroup {
            TodoView(manager: TodoManager())
        }
    }
}

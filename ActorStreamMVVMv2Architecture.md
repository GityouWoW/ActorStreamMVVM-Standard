# ActorStream MVVM (ASM) v2.0 アーキテクチャプロンプト

## 基本原則
- Swift 6 strict concurrency checks 準拠
- Actor + AsyncStream を中心としたスレッドセーフな設計
- Service層とManager層を分離してDI可能に
- State enumで状態遷移を明確化
- @MainActor でUI更新を保証
- キャンセル制御とエラーハンドリングを強化

## 変更点 (v2.0)
- LoadState<T> を導入して汎用化
- 複数購読対応（continuations配列で管理）
- Service層の抽象化によるDI対応
- ユーザー向けエラーメッセージ変換
- onTermination と Task.isCancelled によるキャンセル制御改善

## 構成

### 1. 汎用的な状態管理
```swift
enum LoadState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

protocol StringServiceProtocol: Sendable {
    func fetchString() async throws -> String
}

struct StringService: StringServiceProtocol {
    func fetchString() async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "こんにちは、ASMVVM v2.0"
    }
}

actor StringManager {
    typealias State = LoadState<String>
    private var currentState: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let service: StringServiceProtocol
    
    init(service: StringServiceProtocol = StringService()) {
        self.service = service
    }
    
    func createStream() -> (id: UUID, stream: AsyncStream<State>) {
        let id = UUID()
        let stream = AsyncStream<State> { continuation in
            self.continuations[id] = continuation
            continuation.yield(self.currentState)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
        return (id, stream)
    }
    
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
    
    func fetchString() async {
        currentState = .loading
        yieldToAll(currentState)
        do {
            let fetched = try await service.fetchString()
            currentState = .success(fetched)
            yieldToAll(currentState)
        } catch {
            currentState = .failure(error)
            yieldToAll(currentState)
        }
    }
    
    private func yieldToAll(_ state: State) {
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
    
    func getCurrentString() -> String {
        switch currentState {
        case .success(let str): return str
        default: return "No String"
        }
    }
}

@MainActor
final class StringViewModel: ObservableObject {
    @Published var displayString = "Press the button to fetch string."
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let manager: StringManager
    private var streamID: UUID?
    private var observeTask: Task<Void, Never>?
    
    init(manager: StringManager) {
        self.manager = manager
        startObserving()
    }
    
    deinit { observeTask?.cancel() }
    
    private func startObserving() {
        observeTask = Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await self.manager.createStream()
            self.streamID = id
            for await state in stream {
                if Task.isCancelled { break }
                self.updateUI(with: state)
            }
        }
    }
    
    private func updateUI(with state: LoadState<String>) {
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
            errorMessage = mapErrorToUserMessage(error)
        }
    }
    
    private func mapErrorToUserMessage(_ error: Error) -> String {
        if error is CancellationError { return "処理がキャンセルされました" }
        return "データの取得に失敗しました: \(error.localizedDescription)"
    }
    
    func fetchString() {
        Task { await manager.fetchString() }
    }
}

struct StringView: View {
    @StateObject private var viewModel: StringViewModel
    
    init(manager: StringManager) {
        _viewModel = StateObject(wrappedValue: StringViewModel(manager: manager))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isLoading {
                ProgressView().scaleEffect(1.5)
            } else if let error = viewModel.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error).foregroundColor(.red).multilineTextAlignment(.center)
                }
            } else {
                Text(viewModel.displayString).font(.largeTitle).padding()
            }
            
            Button("Fetch String") {
                viewModel.fetchString()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
        .navigationTitle("ASMVVM Example")
        .padding()
    }
}

@MainActor
class AppDependencies: ObservableObject {
    let stringManager: StringManager
    init(service: StringServiceProtocol = StringService()) {
        self.stringManager = StringManager(service: service)
    }
}

@main
struct StringApp: App {
    @StateObject private var dependencies = AppDependencies()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StringView(manager: dependencies.stringManager)
            }
        }
    }
}



チェックリスト

Actor実装時
 State enumを定義したか
 streamで初期値を流しているか
 continuation?.yield()で状態変更を通知しているか
 ビジネスロジックのみを実装しているか
ViewModel実装時
 @MainActorを指定したか
 @Publishedでプロパティを公開したか
 startObserving()をinit内で呼んだか
 deinitでtask?.cancel()したか
View実装時
 @StateObjectでViewModelを保持したか
 initでManagerを受け取ったか
 ローディング・エラー表示を実装したか

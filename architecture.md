# ActorStream MVVM Standard アーキテクチャガイド（中規模プロジェクト用）

## 基本原則
- Swift 6 strict concurrency checks 準拠
- 具体的な型ごとにActorを作成（ジェネリック不使用）
- State enumで状態を明確に管理
- @MainActorでUI更新を保証

---

## 1. Actor層（データ管理）

### 基本構造
```swift
actor [機能名]Manager {
    // 状態定義
    enum State {
        case idle
        case loading
        case success([データ型])
        case failure(Error)
    }
    
    // プライベート変数
    private var currentState: State = .idle
    private var continuation: AsyncStream<State>.Continuation?
    
    // Stream公開
    var stream: AsyncStream<State> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(currentState)  // 初期値を必ず流す
        }
    }
    
    // ビジネスロジック
    func [操作名]() async {
        currentState = .loading
        continuation?.yield(currentState)
        
        do {
            // 処理
            let result = try await [非同期処理]
            currentState = .success(result)
            continuation?.yield(currentState)
        } catch {
            currentState = .failure(error)
            continuation?.yield(currentState)
        }
    }
    
    // 同期的な値取得
    func get[値名]() -> [型] {
        // 現在の値を返す
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

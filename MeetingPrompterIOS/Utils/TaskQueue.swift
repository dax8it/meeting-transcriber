import Foundation

actor TaskQueue {
    static let shared = TaskQueue()
    
    private var currentTask: Task<Void, Never>?
    
    private init() {}
    
    func enqueue(priority: TaskPriority = .medium, operation: @escaping @Sendable () async -> Void) {
        cancelCurrent()
        
        currentTask = Task(priority: priority) {
            await operation()
        }
    }
    
    func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
    }
}
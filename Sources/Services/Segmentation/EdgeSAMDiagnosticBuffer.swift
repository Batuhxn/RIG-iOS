#if DEBUG
import Foundation

/// Process-local, bounded storage. No disk writes or telemetry transport.
/// The lock protects both append/snapshot and the optional experiment setting.
final class EdgeSAMDiagnosticBuffer: @unchecked Sendable {
    static let shared = EdgeSAMDiagnosticBuffer()
    private let lock = NSLock()
    private let byteLimit: Int
    private let recordLimit: Int
    private var records: [String] = []
    private var byteCount = 0
    private var dropped = 0
    private var boxOnly = false

    init(byteLimit: Int = 262_144, recordLimit: Int = 512) {
        self.byteLimit = max(1, byteLimit)
        self.recordLimit = max(1, recordLimit)
    }

    var knownGoodFirstPrompt: Bool {
        get { lock.lock(); defer { lock.unlock() }; return boxOnly }
        set { lock.lock(); defer { lock.unlock() }; boxOnly = newValue }
    }

    func append(_ record: String) {
        lock.lock()
        defer { lock.unlock() }
        let size = record.utf8.count + 1
        guard size <= byteLimit else { dropped += 1; return }
        while !records.isEmpty && (records.count >= recordLimit || byteCount + size > byteLimit) {
            byteCount -= records.removeFirst().utf8.count + 1
            dropped += 1
        }
        records.append(record)
        byteCount += size
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return "[RIG-EdgeSAM] buffer records=\(records.count) dropped=\(dropped)\n" + records.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll(keepingCapacity: true)
        byteCount = 0
        dropped = 0
    }
}
#endif

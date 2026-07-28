import Darwin
import Foundation

final class ApplicationInstanceLock {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var heldIdentifiers: Set<String> = []

    private let fileDescriptor: Int32
    private let identifier: String

    init?(identifier: String) {
        guard Self.reserve(identifier: identifier) else { return nil }
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifier).instance.lock", isDirectory: false)
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            Self.release(identifier: identifier)
            return nil
        }
        var request = flock()
        request.l_type = Int16(F_WRLCK)
        request.l_whence = Int16(SEEK_SET)
        guard Darwin.fcntl(descriptor, F_SETLK, &request) == 0 else {
            Darwin.close(descriptor)
            Self.release(identifier: identifier)
            return nil
        }
        fileDescriptor = descriptor
        self.identifier = identifier
    }

    deinit {
        var request = flock()
        request.l_type = Int16(F_UNLCK)
        request.l_whence = Int16(SEEK_SET)
        _ = Darwin.fcntl(fileDescriptor, F_SETLK, &request)
        Darwin.close(fileDescriptor)
        Self.release(identifier: identifier)
    }

    private static func reserve(identifier: String) -> Bool {
        registryLock.lock()
        defer { registryLock.unlock() }
        return heldIdentifiers.insert(identifier).inserted
    }

    private static func release(identifier: String) {
        registryLock.lock()
        heldIdentifiers.remove(identifier)
        registryLock.unlock()
    }
}

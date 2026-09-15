import Foundation
import Darwin

/// A pseudo-terminal pair used to run `softwareupdate` as if it were in Terminal.
///
/// `softwareupdate` only renders progress when its output is a TTY. Attached to a plain
/// `Pipe` it prints a couple of status lines and then stays silent for the entire
/// multi-gigabyte download, which is why downloads used to sit at "Preparing" for
/// fifteen minutes with no sign of life.
final class PseudoTerminal {
    /// Our end: everything the child writes shows up here.
    let primaryFD: Int32
    /// The child's end, handed to `Process` as stdout/stderr. Closed in the parent
    /// right after launch so that reads on `primaryFD` report EOF when the child exits.
    private(set) var replicaFD: Int32

    init?() {
        let primary = posix_openpt(O_RDWR | O_NOCTTY)
        guard primary >= 0 else { return nil }

        guard grantpt(primary) == 0, unlockpt(primary) == 0, let name = ptsname(primary) else {
            close(primary)
            return nil
        }

        let replica = open(name, O_RDWR | O_NOCTTY)
        guard replica >= 0 else {
            close(primary)
            return nil
        }

        // Nothing is ever typed into this terminal; echo would only duplicate output.
        var settings = termios()
        if tcgetattr(replica, &settings) == 0 {
            settings.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(replica, TCSANOW, &settings)
        }

        // Non-blocking reads so the drain loop can stop at EAGAIN instead of hanging.
        let flags = fcntl(primary, F_GETFL)
        _ = fcntl(primary, F_SETFL, flags | O_NONBLOCK)

        primaryFD = primary
        replicaFD = replica
    }

    /// Handed to `Process`; created once so the same object is retained by the child setup.
    private(set) lazy var replicaHandle = FileHandle(fileDescriptor: replicaFD, closeOnDealloc: false)

    func closeReplica() {
        guard replicaFD >= 0 else { return }
        close(replicaFD)
        replicaFD = -1
    }

    /// Reads whatever is buffered. Returns nil at end of file — on a pty that surfaces
    /// as EIO once the child's side is gone, not as a zero-length read.
    func drain() -> Data? { Self.drain(fd: primaryFD) }

    /// Free function form, so a dispatch source handler only has to capture the
    /// descriptor rather than this (non-Sendable) object.
    static func drain(fd: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 8192)
        var collected = Data()

        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                read(fd, raw.baseAddress, raw.count)
            }
            if count > 0 {
                collected.append(contentsOf: buffer[0..<count])
                continue
            }
            if count == 0 { return collected.isEmpty ? nil : collected }
            switch errno {
            case EINTR:
                continue
            case EAGAIN, EWOULDBLOCK:
                return collected
            default:
                return collected.isEmpty ? nil : collected
            }
        }
    }

    deinit {
        closeReplica()
        if primaryFD >= 0 { close(primaryFD) }
    }
}

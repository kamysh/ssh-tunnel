import Darwin
import Foundation

/// Liveness check for a local forward: can we open a TCP connection to the port
/// on loopback? A `localhost` forward binds BOTH 127.0.0.1 and [::1], so we try
/// each — checking only IPv4 was a real blind spot during the spike.
public enum PortProbe {
    public static func isListening(_ port: Int) -> Bool {
        connectLoopback(port, family: AF_INET) || connectLoopback(port, family: AF_INET6)
    }

    private static func connectLoopback(_ port: Int, family: Int32) -> Bool {
        let fd = socket(family, SOCK_STREAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }

        if family == AF_INET {
            var a = sockaddr_in()
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
            _ = "127.0.0.1".withCString { inet_pton(AF_INET, $0, &a.sin_addr) }
            return withUnsafePointer(to: &a) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        } else {
            var a = sockaddr_in6()
            a.sin6_family = sa_family_t(AF_INET6)
            a.sin6_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
            _ = "::1".withCString { inet_pton(AF_INET6, $0, &a.sin6_addr) }
            return withUnsafePointer(to: &a) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
                }
            }
        }
    }
}

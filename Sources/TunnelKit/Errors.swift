import Foundation

public enum TunnelError: Error, CustomStringConvertible {
    case sshConfig(String)
    case engine(String)

    public var description: String {
        switch self {
        case .sshConfig(let m): return m
        case .engine(let m): return m
        }
    }
}

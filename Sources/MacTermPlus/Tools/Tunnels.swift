import Citadel
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// A saved local port forward: 127.0.0.1:localPort → (through the SSH server) → remoteHost:remotePort.
struct TunnelConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var sessionID: UUID?
    var localPort: Int = 8080
    var remoteHost: String = "127.0.0.1"
    var remotePort: Int = 80
    var autoStart = false
    var updatedAt = Date()

    var summary: String { "localhost:\(localPort) → \(remoteHost):\(remotePort)" }
}

@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()
    static let changed = Notification.Name("MacTermPlus.tunnelsChanged")

    enum State: Equatable { case stopped, starting, running(connections: Int), failed(String) }

    @Published private(set) var tunnels: [TunnelConfig] = []
    @Published private(set) var states: [UUID: State] = [:]

    private var servers: [UUID: Channel] = [:]
    private var connections: [UUID: SSHConnection] = [:]
    private let url = AppPaths.supportDirectory.appendingPathComponent("tunnels.json")

    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([TunnelConfig].self, from: data) {
            tunnels = list
        }
    }

    func state(_ t: TunnelConfig) -> State { states[t.id] ?? .stopped }

    func upsert(_ t: TunnelConfig) {
        var t = t
        t.updatedAt = Date()
        if let i = tunnels.firstIndex(where: { $0.id == t.id }) { tunnels[i] = t } else { tunnels.append(t) }
        save()
    }

    func delete(_ t: TunnelConfig) {
        stop(t)
        tunnels.removeAll { $0.id == t.id }
        save()
    }

    func replaceAll(_ list: [TunnelConfig]) {
        tunnels = list
        save(notify: false)
    }

    var lastChange: Date { tunnels.map(\.updatedAt).max() ?? .distantPast }

    private func save(notify: Bool = true) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(tunnels).write(to: url, options: .atomic)
        if notify { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    func startAutoTunnels(store: SessionStore) {
        for t in tunnels where t.autoStart { start(t, store: store) }
    }

    func start(_ t: TunnelConfig, store: SessionStore) {
        guard servers[t.id] == nil else { return }
        guard let sid = t.sessionID, let profile = store.sessions.first(where: { $0.id == sid }) else {
            states[t.id] = .failed("Choose an SSH session for this tunnel.")
            return
        }
        guard profile.kind == .ssh || profile.kind == .sftp else {
            states[t.id] = .failed("Tunnels need an SSH or SFTP session.")
            return
        }
        let secret = Keychain.read(account: profile.keychainAccount)
        if profile.auth == .password && secret == nil {
            states[t.id] = .failed("Save this session’s password in the Keychain to use it for tunnels.")
            return
        }
        states[t.id] = .starting
        let conn = SSHConnection(profile: profile, secret: secret)
        connections[t.id] = conn
        Task {
            do {
                let client = try await conn.connectedClient()
                let server = try await Self.bind(t, client: client) { [weak self] delta in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .running(let n) = self.states[t.id] ?? .stopped {
                            self.states[t.id] = .running(connections: max(0, n + delta))
                        }
                    }
                }
                servers[t.id] = server
                states[t.id] = .running(connections: 0)
            } catch {
                states[t.id] = .failed(Self.describe(error, port: t.localPort))
                conn.disconnect()
                connections[t.id] = nil
            }
        }
    }

    func stop(_ t: TunnelConfig) {
        servers.removeValue(forKey: t.id)?.close(promise: nil)
        connections.removeValue(forKey: t.id)?.disconnect()
        states[t.id] = .stopped
    }

    func stopAll() {
        for t in tunnels { stop(t) }
    }

    private static func describe(_ error: Error, port: Int) -> String {
        let text = String(describing: error)
        if text.contains("Address already in use") || text.contains("EADDRINUSE") || text.contains("errno: 48") {
            return "Port \(port) on this Mac is already in use. Pick another local port."
        }
        return SSHConnection.describe(error)
    }

    /// Listens on 127.0.0.1:localPort; each accepted connection gets its own SSH direct-tcpip channel.
    nonisolated private static func bind(_ t: TunnelConfig, client: SSHClient,
                                         connectionCount: @escaping @Sendable (Int) -> Void) async throws -> Channel {
        let bootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { local in
                let localSide = RelayHandler()
                return local.pipeline.addHandler(localSide).flatMap {
                    let promise = local.eventLoop.makePromise(of: Void.self)
                    promise.completeWithTask {
                        let origin = try local.remoteAddress ?? SocketAddress(ipAddress: "127.0.0.1", port: 0)
                        let remote = try await client.createDirectTCPIPChannel(
                            using: SSHChannelType.DirectTCPIP(targetHost: t.remoteHost, targetPort: t.remotePort,
                                                              originatorAddress: origin)
                        ) { ssh in
                            ssh.pipeline.addHandler(RelayHandler(partner: local))
                        }
                        connectionCount(1)
                        remote.closeFuture.whenComplete { _ in connectionCount(-1) }
                        local.eventLoop.execute {
                            localSide.partner = remote
                            local.setOption(ChannelOptions.autoRead, value: true).whenComplete { _ in local.read() }
                        }
                    }
                    promise.futureResult.whenFailure { _ in local.close(promise: nil) }
                    return local.eventLoop.makeSucceededVoidFuture()
                }
            }
        return try await bootstrap.bind(host: "127.0.0.1", port: t.localPort).get()
    }
}

/// Copies bytes to the partner channel and closes it when this side closes.
private final class RelayHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    var partner: Channel?

    init(partner: Channel? = nil) { self.partner = partner }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        partner?.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        partner?.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

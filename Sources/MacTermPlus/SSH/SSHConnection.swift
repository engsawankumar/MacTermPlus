import Citadel
import Crypto
import Foundation
import NIOCore
import NIOSSH

enum ConnectionError: LocalizedError {
    case missingKey(String)
    case unsupportedKey

    var errorDescription: String? {
        switch self {
        case .missingKey(let path): return "Private key not found at \(path)"
        case .unsupportedKey: return "Unsupported private key. Use an OpenSSH-format Ed25519 or RSA key (ssh-keygen -t ed25519)."
        }
    }
}

/// One SSH connection per open tab. The terminal and the SFTP panel share it as separate channels.
@MainActor
final class SSHConnection: ObservableObject {
    enum State: Equatable {
        case idle, connecting, connected, failed(String), closed
    }

    let profile: SessionProfile
    @Published var state: State = .idle

    private var client: SSHClient?
    private var sftpClient: SFTPClient?
    private var connectTask: Task<SSHClient, Error>?
    private var secret: String?

    init(profile: SessionProfile, secret: String?) {
        self.profile = profile
        self.secret = secret
    }

    /// Returns the live client, connecting once if needed (concurrent callers share the attempt).
    func connectedClient() async throws -> SSHClient {
        if let client, client.isConnected { return client }
        if let connectTask { return try await connectTask.value }

        state = .connecting
        let profile = self.profile
        let secret = self.secret
        let task = Task<SSHClient, Error> {
            let auth = try Self.authMethod(for: profile, secret: secret)
            return try await SSHClient.connect(
                host: profile.host,
                port: profile.port,
                authenticationMethod: auth,
                hostKeyValidator: .custom(TOFUHostKeyDelegate(host: profile.host, port: profile.port)),
                reconnect: .never,
                connectTimeout: .seconds(15)
            )
        }
        connectTask = task
        do {
            let c = try await task.value
            client = c
            connectTask = nil
            state = .connected
            return c
        } catch {
            connectTask = nil
            state = .failed(Self.describe(error))
            throw error
        }
    }

    func sftp() async throws -> SFTPClient {
        if let sftpClient, sftpClient.isActive { return sftpClient }
        let c = try await connectedClient()
        let s = try await c.openSFTP()
        sftpClient = s
        return s
    }

    func disconnect() {
        let c = client
        let s = sftpClient
        client = nil
        sftpClient = nil
        state = .closed
        Task {
            try? await s?.close()
            try? await c?.close()
        }
    }

    nonisolated static func authMethod(for profile: SessionProfile, secret: String?) throws -> SSHAuthenticationMethod {
        switch profile.auth {
        case .password:
            return .passwordBased(username: profile.username, password: secret ?? "")
        case .privateKey:
            let path = (profile.keyPath as NSString).expandingTildeInPath
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                throw ConnectionError.missingKey(path)
            }
            let passphrase = (secret?.isEmpty == false) ? Data(secret!.utf8) : nil
            if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: text, decryptionKey: passphrase) {
                return .ed25519(username: profile.username, privateKey: key)
            }
            if let key = try? Insecure.RSA.PrivateKey(sshRsa: text, decryptionKey: passphrase) {
                return .rsa(username: profile.username, privateKey: key)
            }
            throw ConnectionError.unsupportedKey
        }
    }

    /// When the remote shell exits first, closing our end throws `alreadyClosed`; that is a normal end.
    nonisolated static func ignoringRemoteClose(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as ChannelError where error == .alreadyClosed || error == .ioOnClosedChannel {
            return
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        let text = String(describing: error)
        if text.contains("allAuthenticationOptionsFailed") { return "Authentication failed — check username, password or key." }
        if text.contains("connectTimeout") || text.contains("timeout") { return "Connection timed out." }
        if text.contains("connectionRefused") || text.contains("Connection refused") { return "Connection refused — is SSH running on that port?" }
        return text
    }
}

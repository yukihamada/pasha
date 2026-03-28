import Foundation
import CryptoKit
import Security

/// Solana on-chain Memo transaction anchoring for audit logs.
///
/// Submits a real Memo transaction to Solana mainnet containing:
///   "PASHA|v1|<merkleRoot>|<logCount>|<timestamp>"
/// Falls back to local-only anchoring if the RPC call fails.
actor SolanaAnchor {
    static let shared = SolanaAnchor()

    // MARK: - Wallet keypair (Ed25519) — stored in Keychain

    private static let keychainService = "com.enablerdao.pasha.solana"
    private static let keychainAccount = "wallet_keypair"

    /// Load keypair from Keychain. On first launch, generates a new Ed25519 keypair
    /// and stores it in Keychain. No hardcoded keys.
    private static func loadKeypairBytes() -> [UInt8]? {
        // Try reading from Keychain first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, data.count == 64 {
            return Array(data)
        }

        // First launch: generate a new Ed25519 keypair
        let privateKey = Curve25519.Signing.PrivateKey()
        let seed = privateKey.rawRepresentation  // 32 bytes
        let pubKey = privateKey.publicKey.rawRepresentation  // 32 bytes
        let keypairBytes = Array(seed) + Array(pubKey)  // 64 bytes total

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(keypairBytes),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            #if DEBUG
            print("[SolanaAnchor] Keychain save failed: \(addStatus)")
            #endif
        }
        return keypairBytes
    }

    /// Derive the Solana wallet address (Base58 of public key) from the Keychain keypair.
    private static func deriveWalletAddress() -> String {
        guard let kp = loadKeypairBytes(), kp.count == 64 else {
            return "unknown"
        }
        let pubKeyBytes = Array(kp[32..<64])
        return base58Encode(Data(pubKeyBytes))
    }

    /// Solana wallet address (Base58 of public key bytes), derived from Keychain keypair
    private let walletAddress: String = SolanaAnchor.deriveWalletAddress()

    /// Memo Program ID: MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr
    private static let memoProgramId: [UInt8] = {
        let data = SolanaAnchor.base58Decode("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr")
        return Array(data)
    }()

    private let rpcURL = URL(string: "https://api.mainnet-beta.solana.com")!

    // MARK: - Public API

    /// Return the Solana wallet address (for display)
    func getPublicKeyBase58() -> String {
        walletAddress
    }

    /// Fetch the SOL balance of the wallet via getBalance RPC.
    func getBalance() async throws -> Double {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [walletAddress]
        ]
        let result = try await rpcCall(body)
        guard let value = (result["result"] as? [String: Any])?["value"] as? Int else {
            throw SolanaError.invalidResponse
        }
        return Double(value) / 1_000_000_000.0
    }

    /// Anchor a batch of audit logs to Solana mainnet via Memo transaction.
    ///
    /// Returns either:
    ///  - A real Solana tx signature (Base58, 88 chars) on success
    ///  - A local anchor ID "local_..." as fallback if RPC fails
    func anchorBatch(_ logs: [AuditLog], modelContext: Any) async throws -> String {
        guard !logs.isEmpty else { return "" }

        let hashes = logs.map { $0.logHash }
        let merkleRoot = SolanaAnchor.computeMerkleRoot(hashes)
        let timestamp = Int(Date().timeIntervalSince1970)
        let memoContent = "PASHA|v1|\(merkleRoot)|\(hashes.count)|\(timestamp)"

        // Try on-chain submission first
        do {
            let txSignature = try await submitMemoTransaction(memo: memoContent)

            // Persist anchor record
            let record = AnchorRecord(
                anchorId: txSignature,
                merkleRoot: merkleRoot,
                logCount: hashes.count,
                logHashes: hashes,
                timestamp: Date(),
                isOnChain: true
            )
            saveAnchorRecord(record)

            return txSignature
        } catch {
            // Fallback to local anchor
            #if DEBUG
            print("[SolanaAnchor] On-chain failed: \(error.localizedDescription). Falling back to local.")
            #endif
            let anchorId = "local_\(String(merkleRoot.prefix(16)))_\(timestamp)"
            let record = AnchorRecord(
                anchorId: anchorId,
                merkleRoot: merkleRoot,
                logCount: hashes.count,
                logHashes: hashes,
                timestamp: Date(),
                isOnChain: false
            )
            saveAnchorRecord(record)
            return anchorId
        }
    }

    /// Verify that a set of hashes produces the expected Merkle root.
    func verifyHash(hashes: [String], expectedRoot: String) -> Bool {
        let computed = SolanaAnchor.computeMerkleRoot(hashes)
        return computed == expectedRoot
    }

    /// Export a JSON verification proof for all locally-anchored batches.
    func exportVerificationProof() -> String {
        let records = loadAnchorRecords()
        let entries: [[String: Any]] = records.map { r in
            [
                "anchorId": r.anchorId,
                "merkleRoot": r.merkleRoot,
                "logCount": r.logCount,
                "logHashes": r.logHashes,
                "timestamp": ISO8601DateFormatter().string(from: r.timestamp),
                "walletAddress": walletAddress,
                "status": r.isOnChain ? "on_chain" : "locally_verified"
            ]
        }
        let wrapper: [String: Any] = [
            "version": "PASHA_PROOF_v1",
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "walletAddress": walletAddress,
            "anchors": entries
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Solana Transaction Submission

    /// Submit a Memo transaction to Solana mainnet.
    /// Returns the transaction signature as a Base58 string.
    private func submitMemoTransaction(memo: String) async throws -> String {
        // 1. Get latest blockhash
        let blockhash = try await getLatestBlockhash()

        // 2. Build the transaction message
        let memoData = Array(memo.utf8)
        guard let kp = Self.loadKeypairBytes() else {
            throw SolanaError.rpcError("Failed to load keypair from Keychain")
        }
        let feePayer = Array(kp[32..<64]) // public key bytes
        let memoProgram = Self.memoProgramId

        // Transaction message layout:
        //   Header: [numRequiredSignatures=1][numReadonlySigned=0][numReadonlyUnsigned=1]
        //   numAccountKeys (compact-u16): 2
        //   Account keys: [feePayer (32 bytes)][memoProgram (32 bytes)]
        //   Recent blockhash: 32 bytes
        //   numInstructions (compact-u16): 1
        //   Instruction:
        //     programIdIndex: 1
        //     numAccounts (compact-u16): 0
        //     numData (compact-u16): len(memoData)
        //     data: memoData bytes

        var message = Data()
        // Header
        message.append(contentsOf: [1, 0, 1])
        // Compact array: 2 account keys
        message.append(contentsOf: compactU16(2))
        // Account key 1: fee payer
        message.append(contentsOf: feePayer)
        // Account key 2: memo program
        message.append(contentsOf: memoProgram)
        // Recent blockhash
        let blockhashBytes = Array(Self.base58Decode(blockhash))
        guard blockhashBytes.count == 32 else {
            throw SolanaError.rpcError("Invalid blockhash length: \(blockhashBytes.count)")
        }
        message.append(contentsOf: blockhashBytes)
        // Instructions: 1
        message.append(contentsOf: compactU16(1))
        // Instruction: program ID index = 1 (memo program)
        message.append(1)
        // No accounts for memo instruction
        message.append(contentsOf: compactU16(0))
        // Data length + data
        message.append(contentsOf: compactU16(memoData.count))
        message.append(contentsOf: memoData)

        // 3. Sign the message with Ed25519
        let seed = Data(kp[0..<32])
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let signature = try privateKey.signature(for: message)

        // 4. Build the full transaction
        var transaction = Data()
        // Compact array: 1 signature
        transaction.append(contentsOf: compactU16(1))
        // The signature (64 bytes)
        transaction.append(signature)
        // The message
        transaction.append(message)

        // 5. Send the transaction
        let txBase64 = transaction.base64EncodedString()
        let sendBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sendTransaction",
            "params": [
                txBase64,
                ["encoding": "base64"]
            ]
        ]
        let sendResult = try await rpcCall(sendBody)

        if let error = sendResult["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown"
            if message.contains("insufficient") {
                throw SolanaError.insufficientFunds
            }
            throw SolanaError.rpcError(message)
        }

        guard let txSig = sendResult["result"] as? String else {
            throw SolanaError.invalidResponse
        }

        return txSig
    }

    /// Get the latest blockhash from Solana RPC.
    private func getLatestBlockhash() async throws -> String {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": [["commitment": "finalized"]]
        ]
        let result = try await rpcCall(body)

        if let error = result["error"] as? [String: Any] {
            throw SolanaError.rpcError(error["message"] as? String ?? "unknown")
        }

        guard let value = (result["result"] as? [String: Any])?["value"] as? [String: Any],
              let blockhash = value["blockhash"] as? String else {
            throw SolanaError.invalidResponse
        }
        return blockhash
    }

    /// Generic JSON-RPC call to Solana.
    private func rpcCall(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SolanaError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SolanaError.invalidResponse
        }

        return json
    }

    // MARK: - Compact-u16 encoding (Solana wire format)

    private func compactU16(_ value: Int) -> [UInt8] {
        var val = value
        var bytes: [UInt8] = []
        while true {
            var elem = UInt8(val & 0x7f)
            val >>= 7
            if val != 0 {
                elem |= 0x80
            }
            bytes.append(elem)
            if val == 0 { break }
        }
        return bytes
    }

    // MARK: - Merkle Root (public static)

    /// Compute Merkle root from an array of hex hash strings.
    static func computeMerkleRoot(_ hashes: [String]) -> String {
        guard !hashes.isEmpty else { return "" }
        var layer = hashes
        while layer.count > 1 {
            var next: [String] = []
            for i in stride(from: 0, to: layer.count, by: 2) {
                let left = layer[i]
                let right = i + 1 < layer.count ? layer[i + 1] : left
                let combined = "\(left)\(right)"
                let hash = SHA256.hash(data: Data(combined.utf8)).hexString
                next.append(hash)
            }
            layer = next
        }
        return layer[0]
    }

    // MARK: - Base58 utilities

    static func base58Encode(_ data: Data) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var bytes = Array(data)
        var result: [Character] = []

        let leadingZeros = bytes.prefix(while: { $0 == 0 }).count

        while !bytes.isEmpty && !(bytes.count == 1 && bytes[0] == 0) {
            var carry = 0
            var newBytes: [UInt8] = []
            for byte in bytes {
                carry = carry * 256 + Int(byte)
                if !newBytes.isEmpty || carry / 58 > 0 {
                    newBytes.append(UInt8(carry / 58))
                }
                carry = carry % 58
            }
            result.insert(alphabet[carry], at: 0)
            bytes = newBytes
        }

        for _ in 0..<leadingZeros {
            result.insert("1", at: 0)
        }

        return String(result)
    }

    static func base58Decode(_ string: String) -> Data {
        let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var result: [UInt8] = [0]

        for char in string {
            guard let index = alphabet.firstIndex(of: char) else { continue }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            var carry = value
            for i in (0..<result.count).reversed() {
                carry += Int(result[i]) * 58
                result[i] = UInt8(carry % 256)
                carry /= 256
            }
            while carry > 0 {
                result.insert(UInt8(carry % 256), at: 0)
                carry /= 256
            }
        }

        let leadingOnes = string.prefix(while: { $0 == "1" }).count
        let leadingZeros = Array(repeating: UInt8(0), count: leadingOnes)
        return Data(leadingZeros + result.drop(while: { $0 == 0 }))
    }

    // MARK: - Local anchor persistence

    private struct AnchorRecord: Codable {
        let anchorId: String
        let merkleRoot: String
        let logCount: Int
        let logHashes: [String]
        let timestamp: Date
        let isOnChain: Bool
    }

    private let storageKey = "pasha_anchor_records"

    private func saveAnchorRecord(_ record: AnchorRecord) {
        var records = loadAnchorRecords()
        records.append(record)
        if records.count > 100 { records = Array(records.suffix(100)) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadAnchorRecords() -> [AnchorRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([AnchorRecord].self, from: data) else {
            return []
        }
        return records
    }
}

enum SolanaError: LocalizedError {
    case invalidResponse
    case rpcError(String)
    case insufficientFunds

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Solana RPC: invalid response"
        case .rpcError(let msg): return "Solana RPC: \(msg)"
        case .insufficientFunds: return "Solana wallet needs SOL for transaction fees"
        }
    }
}

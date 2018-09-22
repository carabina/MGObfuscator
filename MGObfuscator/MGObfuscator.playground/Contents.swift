import Foundation
import CommonCrypto

enum CripticAlgo {
    case AlgoAES
    case AlgoDES

    func blockSize() -> Int {
        switch self {
        case .AlgoAES:
            return kCCBlockSizeAES128
        case .AlgoDES:
            return kCCBlockSizeDES
        }
    }

    func keySize() -> size_t {
        switch self {
        case .AlgoAES:
            return kCCKeySizeAES128
        case .AlgoDES:
            return kCCKeySizeDES
        }
    }

    func algo() -> UInt32 {
        switch self {
        case .AlgoAES:
            return CCAlgorithm(kCCAlgorithmAES)
        case .AlgoDES:
            return CCAlgorithm(kCCAlgorithmDES)
        }
    }
}

final class MGObfuscator {

    private var ivData: [UInt8]
    private let derivedKey: Data
    private let cripticAlgo: CripticAlgo

    init(password: String, salt: String, algo: CripticAlgo) {
        //Quickly get the data to release the password string
        let passwordData = password.data(using: .utf8)!
        //
        // Rounds require for 1 sec delay in generating hash.
        // Salt is a public attribute. If attacker somehow get the drivedKey and try to crack
        // the password via brute force, The delay due to Rounds will make it frustrating
        // to get actual password and deter his/her efforts.
        //
        let rounds = CCCalibratePBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.count,
                                      salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), Int(CC_SHA1_DIGEST_LENGTH), 1000)

        let saltData = salt.data(using: .utf8)!
        derivedKey = MGObfuscator.derivedKey(for: passwordData,
                                             saltData: saltData, rounds: rounds)
        self.cripticAlgo = algo
        ivData = [UInt8](repeating: 0, count: algo.blockSize())
        // Random criptographically secure bytes for initialisation Vector
        let rStatus = SecRandomCopyBytes(kSecRandomDefault, ivData.count, &ivData)
        print(ivData)
        guard rStatus == errSecSuccess else {
            fatalError("seed not generated \(rStatus)")
        }
    }

    @inline(__always) private static func derivedKey(for passwordData: Data, saltData: Data, rounds: UInt32) -> Data {
        var derivedData = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
        let result = derivedData.withUnsafeMutableBytes { (drivedBytes: UnsafeMutablePointer<UInt8>?) in
            passwordData.withUnsafeBytes({ (passwordBytes: UnsafePointer<Int8>!) in
                saltData.withUnsafeBytes({ (saltBytes: UnsafePointer<UInt8>!) in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, passwordData.count, saltBytes, saltData.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), rounds, drivedBytes, Int(CC_SHA1_DIGEST_LENGTH))
                })
            })
        }
        if kCCSuccess != result {
            fatalError("failed to generate hash for password")
        }
        return derivedData
    }

    private func aesEncription(inputData: Data, keyData: Data, ivData: Data, operation: Int) -> Data {
        let cryptLength = size_t(inputData.count + cripticAlgo.blockSize())
        var cryptData = Data(count: cryptLength)
        let keyLength = cripticAlgo.keySize()

        var bytesProcessed: size_t = 0
        let cryptStatus = cryptData.withUnsafeMutableBytes {cryptBytes in
            inputData.withUnsafeBytes { dataBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData.withUnsafeBytes{ ivBytes in
                        CCCrypt(CCOperation(operation),
                                cripticAlgo.algo(),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBytes, keyLength,
                                ivBytes,
                                dataBytes, inputData.count,
                                cryptBytes, cryptLength,
                                &bytesProcessed)
                    }
                }
            }
        }
        if cryptStatus == CCCryptorStatus(kCCSuccess) {
            cryptData.removeSubrange(bytesProcessed..<cryptData.count)
        } else {
            fatalError("Error: \(cryptStatus)")
        }
        return cryptData
    }

    public func encript(inputString: String) -> Data {
        let inputdata = inputString.data(using: .utf8)!
        return aesEncription(inputData: inputdata, keyData: derivedKey, ivData: Data(bytes: ivData), operation: kCCEncrypt)
    }

    public func decript(data: Data, result: (String) -> Void) {
        let data = aesEncription(inputData: data, keyData: derivedKey, ivData: Data(bytes: ivData), operation: kCCDecrypt)
        result(String(data: data, encoding: .utf8)!)
    }
}

let obfs = MGObfuscator(password: "password", salt: String(describing:MGObfuscator.self),
                        algo: .AlgoDES)

let encrpted = obfs.encript(inputString: "Mrigank")

obfs.decript(data: encrpted) { (decripted) in
    print(decripted)
}

//
// Copyright (C) 2015-2018 Virgil Security Inc.
//
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     (1) Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//
//     (2) Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer in
//     the documentation and/or other materials provided with the
//     distribution.
//
//     (3) Neither the name of the copyright holder nor the names of its
//     contributors may be used to endorse or promote products derived from
//     this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR ''AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
// IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Lead Maintainer: Virgil Security Inc. <support@virgilsecurity.com>
//

import Foundation
import VirgilCryptoApiImpl

// MARK: - Extension with encrypt-decrypt operations
extension EThree {
    // Typealias for the valid result of lookupPublicKeys call
    public typealias LookupResult = [String: VirgilPublicKey]

    /// Signs then encrypts data for group of users
    ///
    /// Important: Avoid key duplication
    /// Note: Automatically includes self key to recipientsKeys.
    /// - Parameters:
    ///   - data: data to encrypt
    ///   - recipientKeys: result of lookupPublicKeys call recipient PublicKeys to sign and encrypt with.
    ///                    Use nil to sign and encrypt for self
    /// - Returns: decrypted Data
    /// - Throws: corresponding error
    /// - Important: Requires a bootstrapped user
    @objc public func encrypt(data: Data, for recipientKeys: LookupResult? = nil) throws -> Data {
        guard let selfKeyPair = self.localKeyManager.retrieveKeyPair() else {
            throw EThreeError.notBootstrapped
        }

        var publicKeys = [selfKeyPair.publicKey]

        if let recipientKeys = recipientKeys {
            guard !recipientKeys.isEmpty else {
                throw EThreeError.missingKeys
            }

            publicKeys += recipientKeys.values
        }

        let encryptedData = try self.crypto.signThenEncrypt(data, with: selfKeyPair.privateKey, for: publicKeys)

        return encryptedData
    }

    /// Decrypts and verifies data from users
    ///
    /// Important: Avoid key duplication
    /// Note: Automatically includes self key to recipientsKeys.
    /// - Parameters:
    ///   - data: data to decrypt
    ///   - senderPublicKey: sender PublicKey to verify with. Use nil to decrypt and verify from self
    /// - Returns: decrypted Data
    /// - Throws: corresponding error
    /// - Important: Requires a bootstrapped user
    @objc public func decrypt(data: Data, from senderPublicKey: VirgilPublicKey? = nil) throws -> Data {
        guard let selfKeyPair = self.localKeyManager.retrieveKeyPair() else {
            throw EThreeError.notBootstrapped
        }

        let senderPublicKey = senderPublicKey ?? selfKeyPair.publicKey

        let decryptedData = try self.crypto.decryptThenVerify(data, with: selfKeyPair.privateKey,
                                                              using: senderPublicKey)

        return decryptedData
    }

    /// Signs then encrypts string for group of users
    ///
    /// Important: Avoid key duplication
    /// Note: Automatically includes self key to recipientsKeys.
    /// - Parameters:
    ///   - text: String to encrypt
    ///   - recipientKeys: result of lookupPublicKeys call recipient PublicKeys to sign and encrypt with.
    ///                    Use nil to sign and encrypt for self
    /// - Returns: encrypted base64String
    /// - Throws: corresponding error
    /// - Important: Requires a bootstrapped user
    @objc public func encrypt(text: String, for recipientKeys: LookupResult? = nil) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw EThreeError.strToDataFailed
        }

        return try self.encrypt(data: data, for: recipientKeys).base64EncodedString()
    }

    /// Decrypts and verifies base64 string from users
    ///
    /// Important: Avoid key duplication
    /// Note: Automatically includes self key to recipientsKeys.
    /// - Parameters:
    ///   - text: encrypted String
    ///   - senderPublicKey: sender PublicKey to verify with. Use nil to decrypt and verify from self.
    /// - Returns: decrypted String
    /// - Throws: corresponding error
    /// - Important: Requires a bootstrapped user
    @objc public func decrypt(text: String, from senderPublicKey: VirgilPublicKey? = nil) throws -> String {
        guard let data = Data(base64Encoded: text) else {
            throw EThreeError.strToDataFailed
        }

        let decryptedData = try self.decrypt(data: data, from: senderPublicKey)

        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw EThreeError.strFromDataFailed
        }

        return decryptedString
    }

    /// Retrieves user public keys from the cloud for encryption/verification.
    ///
    /// Important: Avoid identities duplication
    /// - Parameters:
    ///   - identities: array of identities to search for
    ///   - completion: completion handler
    ///     - lookupResult: dictionary with idenities as keys and found public keys as values
    ///     - errors: array with Errors
    @objc public func lookupPublicKeys(of identities: [String],
                                       completion: @escaping (_ lookupResult: LookupResult, _ errors: [Error]) -> ()) {
        guard !identities.isEmpty else {
            completion([:], [EThreeError.missingIdentities])
            return
        }

        let group = DispatchGroup()
        var result: LookupResult = [:]
        var errors: [Error] = []

        for identity in identities {
            group.enter()
            self.cardManager.searchCards(identity: identity) { cards, error in
                if let error = error {
                    errors.append(error)
                    return
                }
                guard let publicKey = cards?.first?.publicKey else {
                    errors.append(EThreeError.missingKeys)
                    return
                }
                guard let virgilPublicKey = publicKey as? VirgilPublicKey else {
                    errors.append(EThreeError.keyIsNotVirgil)
                    return
                }

                result[identity] = virgilPublicKey

                defer { group.leave() }
            }
        }

        group.notify(queue: .main) {
            completion(result, errors)
        }
    }
}

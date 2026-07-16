import Foundation
import Supabase

protocol InviteAcceptanceServicing: Sendable {
    func requestSMSCode(phoneNumber: String) async throws
    func verifySMSCode(phoneNumber: String, code: String) async throws -> UUID
    func requestEmailCode(email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws -> UUID
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> UUID
    func acceptChildInvite(token: String) async throws -> AcceptedChildInvite
    func acceptParentInvite(token: String) async throws -> AcceptedParentInvite
}

struct SupabaseInviteAcceptanceService: InviteAcceptanceServicing {
    var client: SupabaseClient = SupabaseClientProvider.shared

    func requestSMSCode(phoneNumber: String) async throws {
        try await client.auth.signInWithOTP(
            phone: phoneNumber,
            shouldCreateUser: true
        )
    }

    func verifySMSCode(phoneNumber: String, code: String) async throws -> UUID {
        let response = try await client.auth.verifyOTP(
            phone: phoneNumber,
            token: code,
            type: .sms
        )

        if let session = response.session {
            client.functions.setAuth(token: session.accessToken)
        }

        return response.user.id
    }

    func requestEmailCode(email: String) async throws {
        try await client.auth.signInWithOTP(
            email: email,
            shouldCreateUser: true
        )
    }

    func verifyEmailCode(email: String, code: String) async throws -> UUID {
        let response = try await verifyEmailCode(
            email: email,
            code: code,
            allowedTypes: [.email, .signup, .magiclink]
        )

        if let session = response.session {
            client.functions.setAuth(token: session.accessToken)
        }

        return response.user.id
    }

    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )

        client.functions.setAuth(token: session.accessToken)

        let trimmedFullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedFullName, !trimmedFullName.isEmpty {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(trimmedFullName)])
            )
        }

        return session.user.id
    }

    private func verifyEmailCode(
        email: String,
        code: String,
        allowedTypes: [EmailOTPType]
    ) async throws -> AuthResponse {
        var lastError: Error?

        for type in allowedTypes {
            do {
                return try await client.auth.verifyOTP(
                    email: email,
                    token: code,
                    type: type
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? InviteAcceptanceError.invalidCode
    }

    func acceptChildInvite(token: String) async throws -> AcceptedChildInvite {
        try await client.functions.invoke(
            "accept-child-invite",
            options: FunctionInvokeOptions(
                method: .post,
                body: AcceptInviteRequest(token: token)
            )
        )
    }

    func acceptParentInvite(token: String) async throws -> AcceptedParentInvite {
        try await client.functions.invoke(
            "accept-parent-invite",
            options: FunctionInvokeOptions(
                method: .post,
                body: AcceptInviteRequest(token: token)
            )
        )
    }
}

struct AcceptInviteRequest: Encodable, Sendable {
    var token: String
}

struct AcceptedChildInvite: Decodable, Equatable, Sendable {
    var familyId: UUID
    var childProfileId: UUID
    var childName: String
    var acceptedChildUserId: UUID

    enum CodingKeys: String, CodingKey {
        case familyId = "family_id"
        case childProfileId = "child_profile_id"
        case childName = "child_name"
        case acceptedChildUserId = "accepted_child_user_id"
    }
}

struct AcceptedParentInvite: Decodable, Equatable, Sendable {
    var familyId: UUID
    var parentName: String
    var acceptedParentUserId: UUID

    enum CodingKeys: String, CodingKey {
        case familyId = "family_id"
        case parentName = "parent_name"
        case acceptedParentUserId = "accepted_parent_user_id"
    }
}

enum InviteAcceptanceError: LocalizedError {
    case missingInvite
    case invalidPhoneNumber
    case invalidEmail
    case invalidCode
    case missingAuthenticatedSession

    var errorDescription: String? {
        switch self {
        case .missingInvite:
            return "Open the invite link again."
        case .invalidPhoneNumber:
            return "Enter a 10-digit US number or a number starting with +."
        case .invalidEmail:
            return "Enter a valid email address."
        case .invalidCode:
            return "Enter the one-time code."
        case .missingAuthenticatedSession:
            return "Sign in before accepting the invite."
        }
    }
}

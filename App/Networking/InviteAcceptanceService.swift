import Foundation
import Supabase

protocol InviteAcceptanceServicing: Sendable {
    func requestSMSCode(phoneNumber: String) async throws
    func verifySMSCode(phoneNumber: String, code: String) async throws -> UUID
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
    case invalidCode
    case missingAuthenticatedSession

    var errorDescription: String? {
        switch self {
        case .missingInvite:
            return "Open the invite link again."
        case .invalidPhoneNumber:
            return "Enter a 10-digit US number or a number starting with +."
        case .invalidCode:
            return "Enter the code from the text message."
        case .missingAuthenticatedSession:
            return "Sign in before accepting the invite."
        }
    }
}

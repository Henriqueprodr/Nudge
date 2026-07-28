import Foundation

enum OAuthTokenRequestValidator {
    static func validateAuthorizationCode(_ fields: [URLQueryItem]) throws {
        let values = try validatedValues(
            fields,
            requiredNames: [
                "client_id",
                "code",
                "code_verifier",
                "grant_type",
                "redirect_uri",
            ],
            optionalNames: ["client_secret"]
        )

        guard values["grant_type"] == "authorization_code" else {
            throw GoogleOAuthError.oauthMalformedRequest
        }
        guard let verifier = values["code_verifier"], isValidVerifier(verifier) else {
            throw GoogleOAuthError.oauthVerifierRejected
        }
        guard
            let redirectValue = values["redirect_uri"],
            let redirectURL = URL(string: redirectValue),
            isValidLoopbackRedirect(redirectURL)
        else {
            throw GoogleOAuthError.oauthRedirectRejected
        }
    }

    static func validateRefreshToken(_ fields: [URLQueryItem]) throws {
        let values = try validatedValues(
            fields,
            requiredNames: ["client_id", "refresh_token", "grant_type"],
            optionalNames: ["client_secret"]
        )
        guard values["grant_type"] == "refresh_token" else {
            throw GoogleOAuthError.oauthMalformedRequest
        }
    }

    private static func validatedValues(
        _ fields: [URLQueryItem],
        requiredNames: Set<String>,
        optionalNames: Set<String>
    ) throws -> [String: String] {
        let allowedNames = requiredNames.union(optionalNames)
        guard
            fields.count >= requiredNames.count,
            fields.count <= allowedNames.count
        else {
            throw errorForInvalidFields(
                fields,
                requiredNames: requiredNames,
                optionalNames: optionalNames
            )
        }

        var values: [String: String] = [:]
        for field in fields {
            guard
                allowedNames.contains(field.name),
                values[field.name] == nil,
                let value = field.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                throw errorForField(field.name)
            }
            values[field.name] = value
        }

        guard Set(values.keys).isSuperset(of: requiredNames) else {
            throw errorForInvalidFields(
                fields,
                requiredNames: requiredNames,
                optionalNames: optionalNames
            )
        }
        return values
    }

    private static func errorForInvalidFields(
        _ fields: [URLQueryItem],
        requiredNames: Set<String>,
        optionalNames: Set<String>
    ) -> GoogleOAuthError {
        let counts = Dictionary(grouping: fields, by: \.name).mapValues(\.count)
        for name in ["client_id", "code", "code_verifier", "redirect_uri"] {
            if requiredNames.contains(name), counts[name] != 1 {
                return errorForField(name)
            }
        }
        for name in optionalNames where (counts[name] ?? 0) > 1 {
            return errorForField(name)
        }
        return .oauthMalformedRequest
    }

    private static func errorForField(_ name: String) -> GoogleOAuthError {
        switch name {
        case "client_id":
            return .oauthClientRejected
        case "code":
            return .oauthAuthorizationCodeRejected
        case "code_verifier":
            return .oauthVerifierRejected
        case "redirect_uri":
            return .oauthRedirectRejected
        default:
            return .oauthMalformedRequest
        }
    }

    private static func isValidVerifier(_ verifier: String) -> Bool {
        guard (43...128).contains(verifier.utf8.count) else {
            return false
        }
        return verifier.utf8.allSatisfy { byte in
            switch byte {
            case 0x2D, 0x2E, 0x30...0x39, 0x41...0x5A, 0x5F, 0x61...0x7A, 0x7E:
                return true
            default:
                return false
            }
        }
    }

    private static func isValidLoopbackRedirect(_ url: URL) -> Bool {
        guard
            url.scheme?.lowercased() == "http",
            url.host == "127.0.0.1",
            let port = url.port,
            (1_024...65_535).contains(port),
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil
        else {
            return false
        }
        return url.path.isEmpty || url.path == "/"
    }
}

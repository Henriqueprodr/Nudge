import Foundation

enum OAuthFormEncoder {
    static func encode(_ fields: [URLQueryItem]) -> Data {
        let body = fields.map { field in
            "\(encode(field.name))=\(encode(field.value ?? ""))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func encode(_ value: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(value.utf8.count)

        for byte in value.utf8 {
            switch byte {
            case 0x20:
                encoded.append("+")
            case 0x2A, 0x2D, 0x2E, 0x30...0x39, 0x41...0x5A, 0x5F, 0x61...0x7A:
                encoded.append(Character(UnicodeScalar(byte)))
            default:
                encoded.append(String(format: "%%%02X", byte))
            }
        }

        return encoded
    }
}

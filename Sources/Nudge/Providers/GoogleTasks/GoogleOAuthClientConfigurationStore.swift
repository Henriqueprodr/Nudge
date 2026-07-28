import Foundation

@MainActor
protocol GoogleOAuthClientConfigurationStore: AnyObject {
    func loadConfiguration() throws -> GoogleOAuthClientConfiguration?
    func saveConfiguration(_ configuration: GoogleOAuthClientConfiguration) throws
    func deleteConfiguration() throws
}

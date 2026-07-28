import Foundation

@MainActor
final class GoogleCalendarClient: GoogleCalendarProviding {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let mapper: GoogleCalendarMapper

    init(
        baseURL: URL = URL(string: "https://www.googleapis.com")!,
        transport: any HTTPTransport,
        decoder: JSONDecoder = JSONDecoder(),
        mapper: GoogleCalendarMapper = GoogleCalendarMapper()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = decoder
        self.mapper = mapper
    }

    func fetchCalendars(accessToken: String) async throws -> [CalendarDescriptor] {
        var calendars: [CalendarDescriptor] = []
        var pageToken: String?
        var seenTokens: Set<String> = []
        repeat {
            try Task.checkCancellation()
            let page: GoogleCalendarDTO.CalendarListPage = try await fetch(
                path: "/calendar/v3/users/me/calendarList",
                queryItems: [
                    URLQueryItem(name: "maxResults", value: "250"),
                    URLQueryItem(name: "showDeleted", value: "false"),
                    URLQueryItem(name: "showHidden", value: "false"),
                    URLQueryItem(name: "pageToken", value: pageToken),
                ],
                accessToken: accessToken
            )
            calendars.append(contentsOf: (page.items ?? []).compactMap(mapper.calendar(from:)))
            pageToken = try nextPageToken(page.nextPageToken, seen: &seenTokens)
        } while pageToken != nil
        return calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func fetchEvents(
        calendar: CalendarDescriptor,
        in interval: DateInterval,
        accessToken: String
    ) async throws -> [CalendarEventSnapshot] {
        var events: [CalendarEventSnapshot] = []
        var pageToken: String?
        var seenTokens: Set<String> = []
        let calendarID = Self.percentEncodedPathComponent(calendar.id)
        repeat {
            try Task.checkCancellation()
            let page: GoogleCalendarDTO.EventPage = try await fetch(
                path: "/calendar/v3/calendars/\(calendarID)/events",
                queryItems: [
                    URLQueryItem(name: "singleEvents", value: "true"),
                    URLQueryItem(name: "orderBy", value: "startTime"),
                    URLQueryItem(name: "showDeleted", value: "false"),
                    URLQueryItem(name: "maxResults", value: "2500"),
                    URLQueryItem(name: "timeMin", value: Self.rfc3339(interval.start)),
                    URLQueryItem(name: "timeMax", value: Self.rfc3339(interval.end)),
                    URLQueryItem(name: "pageToken", value: pageToken),
                ],
                accessToken: accessToken
            )
            events.append(contentsOf: (page.items ?? []).compactMap {
                mapper.event(from: $0, calendar: calendar)
            })
            pageToken = try nextPageToken(page.nextPageToken, seen: &seenTokens)
        } while pageToken != nil
        return events
    }

    private func fetch<Value: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws -> Value {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GoogleCalendarError.invalidResponse
        }
        components.percentEncodedPath = path
        components.queryItems = queryItems.filter { $0.value != nil }
        guard let url = components.url else { throw GoogleCalendarError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw GoogleCalendarError.normalized(error)
        }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 { throw GoogleCalendarError.authenticationRequired }
            if response.statusCode == 403 {
                let reasons = (try? decoder.decode(
                    GoogleCalendarDTO.ErrorEnvelope.self,
                    from: data
                ))?.error.errors?.compactMap(\.reason) ?? []
                if reasons.contains(where: {
                    [
                        "rateLimitExceeded",
                        "userRateLimitExceeded",
                        "quotaExceeded",
                        "dailyLimitExceeded",
                    ].contains($0)
                }) {
                    throw GoogleCalendarError.quotaLimited
                }
                throw GoogleCalendarError.authorizationRequired
            }
            throw GoogleCalendarError.httpStatus(response.statusCode)
        }
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw GoogleCalendarError.decodingFailed
        }
    }

    private func nextPageToken(_ value: String?, seen: inout Set<String>) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard seen.insert(value).inserted else { throw GoogleCalendarError.invalidResponse }
        return value
    }

    private static func percentEncodedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func rfc3339(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

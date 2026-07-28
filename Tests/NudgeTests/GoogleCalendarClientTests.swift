import Foundation
import XCTest
@testable import Nudge

final class GoogleCalendarClientTests: XCTestCase {
    @MainActor
    func testCalendarListPaginationFiltersAccessAndUsesInvariantParameters() async throws {
        let transport = CalendarQueueTransport(responses: [
            .init(status: 200, body: """
            {"nextPageToken":"page-2","items":[
              {"id":"reader","summary":"Reader","timeZone":"UTC","selected":true,"accessRole":"reader","defaultReminders":[]},
              {"id":"freebusy","summary":"Hidden","accessRole":"freeBusyReader"}
            ]}
            """),
            .init(status: 200, body: """
            {"items":[{"id":"owner","summary":"Owner","primary":true,"accessRole":"owner"}]}
            """),
        ])
        let client = GoogleCalendarClient(transport: transport)

        let calendars = try await client.fetchCalendars(accessToken: "token")

        XCTAssertEqual(Set(calendars.map(\.id)), ["reader", "owner"])
        XCTAssertEqual(transport.requests.count, 2)
        for request in transport.requests {
            let query = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let values = Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(values["maxResults"]!, "250")
            XCTAssertEqual(values["showDeleted"]!, "false")
            XCTAssertEqual(values["showHidden"]!, "false")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        }
        XCTAssertNil(URLComponents(url: transport.requests[0].url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "pageToken" }))
        XCTAssertEqual(URLComponents(url: transport.requests[1].url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "pageToken" })?.value, "page-2")
    }

    @MainActor
    func testEventsRequestEncodesCalendarIDAndKeepsBoundedParametersAcrossPages() async throws {
        let transport = CalendarQueueTransport(responses: [
            .init(status: 200, body: "{\"nextPageToken\":\"next\",\"items\":[]}"),
            .init(status: 200, body: "{\"items\":[]}"),
        ])
        let client = GoogleCalendarClient(transport: transport)
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 2_000_000_000),
            duration: 42 * 24 * 60 * 60
        )

        _ = try await client.fetchEvents(
            calendar: testCalendar(id: "person+calendar@example.com"),
            in: interval,
            accessToken: "token"
        )

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests[0].url!.absoluteString.contains(
            "person%2Bcalendar%40example.com/events"
        ))
        let queries = transport.requests.map {
            Dictionary(uniqueKeysWithValues: (URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        }
        for query in queries {
            XCTAssertEqual(query["singleEvents"]!, "true")
            XCTAssertEqual(query["orderBy"]!, "startTime")
            XCTAssertEqual(query["showDeleted"]!, "false")
            XCTAssertEqual(query["maxResults"]!, "2500")
            XCTAssertNotNil(query["timeMin"]!)
            XCTAssertNotNil(query["timeMax"]!)
            XCTAssertNil(query["syncToken"] ?? nil)
        }
        XCTAssertNil(queries[0]["pageToken"] ?? nil)
        XCTAssertEqual(queries[1]["pageToken"]!, "next")
    }

    @MainActor
    func testRepeatedPageTokenAndPartialPageFailureRejectWholeFetch() async {
        let repeated = CalendarQueueTransport(responses: [
            .init(status: 200, body: "{\"nextPageToken\":\"same\",\"items\":[]}"),
            .init(status: 200, body: "{\"nextPageToken\":\"same\",\"items\":[]}"),
        ])
        do {
            _ = try await GoogleCalendarClient(transport: repeated)
                .fetchCalendars(accessToken: "token")
            XCTFail("Expected repeated token rejection")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .invalidResponse)
        }

        let partial = CalendarQueueTransport(responses: [
            .init(status: 200, body: "{\"nextPageToken\":\"next\",\"items\":[]}"),
            .init(status: 500, body: "{}"),
        ])
        do {
            _ = try await GoogleCalendarClient(transport: partial)
                .fetchCalendars(accessToken: "token")
            XCTFail("Expected partial page failure")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .httpStatus(500))
        }
    }

    @MainActor
    func testAuthQuotaCancellationAndDecodingErrorsAreTyped() async {
        let cases: [(CalendarQueueTransport.Response, GoogleCalendarError)] = [
            (.init(status: 401, body: "{}"), .authenticationRequired),
            (.init(status: 403, body: "{\"error\":{\"errors\":[{\"reason\":\"rateLimitExceeded\"}]}}"), .quotaLimited),
            (.init(status: 200, body: "not-json"), .decodingFailed),
        ]
        for value in cases {
            do {
                _ = try await GoogleCalendarClient(
                    transport: CalendarQueueTransport(responses: [value.0])
                ).fetchCalendars(accessToken: "token")
                XCTFail("Expected typed error")
            } catch {
                XCTAssertEqual(error as? GoogleCalendarError, value.1)
            }
        }

        do {
            _ = try await GoogleCalendarClient(transport: CancellingCalendarTransport())
                .fetchCalendars(accessToken: "token")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .cancelled)
        }
    }

    @MainActor
    func testEventMappingResolvesDefaultsOverridesAllDayDSTAndStableRecurrence() async throws {
        let transport = CalendarQueueTransport(responses: [
            .init(status: 200, body: """
            {"items":[
              {"id":"instance","status":"confirmed","htmlLink":"https://calendar.google.com/calendar/event?eid=opaque","summary":"Event","start":{"date":"2026-11-01"},"end":{"date":"2026-11-02"},"recurringEventId":"series","originalStartTime":{"date":"2026-11-01"},"reminders":{"useDefault":true}},
              {"id":"none","status":"confirmed","start":{"dateTime":"2026-11-02T10:00:00-03:00"},"end":{"dateTime":"2026-11-02T11:00:00-03:00"},"reminders":{"useDefault":false,"overrides":[]}},
              {"id":"filtered","status":"confirmed","start":{"dateTime":"2026-11-03T10:00:00Z"},"end":{"dateTime":"2026-11-03T11:00:00Z"},"reminders":{"useDefault":false,"overrides":[{"method":"email","minutes":5},{"method":"popup","minutes":5},{"method":"popup","minutes":5},{"method":"popup","minutes":40321}]}},
              {"id":"cancelled","status":"cancelled"}
            ]}
            """),
        ])
        let calendar = CalendarDescriptor(
            id: "calendar",
            title: "calendar",
            timeZoneIdentifier: "America/Sao_Paulo",
            isSelectedInGoogleCalendar: true,
            isPrimary: true,
            defaultReminders: [.init(method: "popup", minutes: 30)]
        )

        let events = try await GoogleCalendarClient(transport: transport).fetchEvents(
            calendar: calendar,
            in: DateInterval(start: .distantPast, end: .distantFuture),
            accessToken: "token"
        )

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].stableOccurrenceValue, "date:2026-11-01|America/Sao_Paulo")
        XCTAssertEqual(events[0].reminders.map(\.minutes), [30])
        XCTAssertEqual(events[1].reminders, [])
        XCTAssertEqual(events[2].reminders.map(\.duplicateOrdinal), [0, 1])
        XCTAssertEqual(events[2].reminders.map(\.minutes), [5, 5])
        XCTAssertEqual(events[0].sourceURL?.host, "calendar.google.com")
    }

    private func testCalendar(id: String) -> CalendarDescriptor {
        CalendarDescriptor(
            id: id,
            title: id,
            timeZoneIdentifier: "UTC",
            isSelectedInGoogleCalendar: true,
            isPrimary: true,
            defaultReminders: []
        )
    }
}

@MainActor
private final class CalendarQueueTransport: HTTPTransport {
    struct Response {
        let status: Int
        let body: String
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let next = responses.removeFirst()
        return (
            Data(next.body.utf8),
            HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        )
    }
}

@MainActor
private final class CancellingCalendarTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw CancellationError()
    }
}

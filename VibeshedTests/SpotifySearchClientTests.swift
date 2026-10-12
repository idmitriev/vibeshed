@testable import Vibeshed
import XCTest

final class SpotifySearchClientTests: XCTestCase {
    /// AuthenticationServices calls the sign-in sheet's completion handler off the main
    /// thread. Made on the main actor (as `performAuthSession` does) and called from a
    /// background queue, the handler must resume its continuation instead of trapping.
    @MainActor
    func testAuthCompletionRunsOffTheMainThread() async throws {
        let callback = try XCTUnwrap(URL(string: "vibeshed://spotify-callback?code=abc"))
        let received = try await withCheckedThrowingContinuation { continuation in
            let completion = SpotifySearchClient.authSessionCompletion(continuation)
            DispatchQueue.global().async { completion(callback, nil) }
        }
        XCTAssertEqual(received, callback)
    }

    @MainActor
    func testAuthCompletionReportsCancelAndMissingCallback() async {
        let cancelled = NSError(domain: "com.apple.AuthenticationServices.WebAuthenticationSession", code: 1)
        await assertAuthFails(error: cancelled, message: cancelled.localizedDescription)
        await assertAuthFails(error: nil, message: "No callback URL")
    }

    @MainActor
    private func assertAuthFails(error: NSError?, message: String) async {
        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                let completion = SpotifySearchClient.authSessionCompletion(continuation)
                DispatchQueue.global().async { completion(nil, error) }
            }
            XCTFail("expected the sign-in to fail")
        } catch let SpotifySearchClient.SearchError.authFailed(reason) {
            XCTAssertEqual(reason, message)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

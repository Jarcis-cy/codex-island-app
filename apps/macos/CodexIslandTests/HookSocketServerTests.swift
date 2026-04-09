import XCTest
@testable import Codex_Island

final class HookSocketServerTests: XCTestCase {
    func testReadEventWaitsForSplitPayloadInsteadOfBreakingOnShortIdleGap() throws {
        let sockets = try makeSocketPair()
        defer {
            close(sockets.reader)
            close(sockets.writer)
        }

        let payload = """
        {"session_id":"session-1","provider":"codex","cwd":"/tmp/project","event":"UserPromptSubmit","status":"processing"}
        """
        let midpoint = payload.index(payload.startIndex, offsetBy: payload.count / 2)
        let firstHalf = String(payload[..<midpoint])
        let secondHalf = String(payload[midpoint...])

        let writerExpectation = expectation(description: "writer finishes sending split payload")
        DispatchQueue.global().async {
            _ = firstHalf.withCString { pointer in
                write(sockets.writer, pointer, strlen(pointer))
            }
            usleep(250_000)
            _ = secondHalf.withCString { pointer in
                write(sockets.writer, pointer, strlen(pointer))
            }
            writerExpectation.fulfill()
        }

        let event = try HookSocketIO.readEvent(from: sockets.reader, timeout: 1.5)

        wait(for: [writerExpectation], timeout: 2)
        XCTAssertEqual(event.sessionId, "session-1")
        XCTAssertEqual(event.event, "UserPromptSubmit")
        XCTAssertEqual(event.status, "processing")
    }

    func testWriteAllRetriesUntilEntirePayloadIsSent() throws {
        let payload = Data("permission-response".utf8)
        var callSizes: [Int] = []
        var writtenData = Data()
        var remainingBeforeSuccess = 5

        try HookSocketIO.writeAll(payload, to: 42, writer: { _, buffer, count in
            callSizes.append(count)

            let chunkSize = min(remainingBeforeSuccess, count)
            guard chunkSize > 0 else {
                writtenData.append(buffer.assumingMemoryBound(to: UInt8.self), count: count)
                return count
            }

            writtenData.append(buffer.assumingMemoryBound(to: UInt8.self), count: chunkSize)
            remainingBeforeSuccess -= chunkSize
            return chunkSize
        })

        XCTAssertEqual(writtenData, payload)
        XCTAssertEqual(callSizes, [payload.count, payload.count - 5])
    }

    func testWriteAllRecoversFromWouldBlockAndUsesPollBeforeRetrying() throws {
        let payload = Data("ok".utf8)
        var writeAttempts = 0
        var pollCalls = 0
        var writtenData = Data()

        try HookSocketIO.writeAll(
            payload,
            to: 7,
            timeout: 1,
            writer: { _, buffer, count in
                writeAttempts += 1
                if writeAttempts == 1 {
                    errno = EAGAIN
                    return -1
                }
                writtenData.append(buffer.assumingMemoryBound(to: UInt8.self), count: count)
                return count
            },
            poller: { fds, _, _ in
                pollCalls += 1
                fds?.pointee.revents = Int16(POLLOUT)
                return 1
            }
        )

        XCTAssertEqual(writeAttempts, 2)
        XCTAssertEqual(pollCalls, 1)
        XCTAssertEqual(writtenData, payload)
    }

    private func makeSocketPair() throws -> (reader: Int32, writer: Int32) {
        var fds = [Int32](repeating: 0, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        let flags = fcntl(fds[0], F_GETFL)
        _ = fcntl(fds[0], F_SETFL, flags | O_NONBLOCK)
        return (fds[0], fds[1])
    }
}

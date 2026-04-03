import XCTest
@testable import Codex_Island

final class PendingInteractionTests: XCTestCase {
    func testPresentationModeUsesInlineWhenQuestionsCanBeAnsweredInline() {
        let interaction = makeInteraction(questions: [
            PendingInteractionQuestion(
                id: "theme",
                header: "主题方向",
                question: "这次你想让我用哪类主题来触发选项？",
                options: [
                    PendingInteractionOption(label: "通用需求 (Recommended)", description: "中性场景。")
                ],
                isOther: false,
                isSecret: false
            )
        ])

        XCTAssertEqual(interaction.presentationMode(canRespondInline: true), .inline)
    }

    func testPresentationModeFallsBackToReadOnlyWhenInlineUnavailable() {
        let interaction = makeInteraction(questions: [
            PendingInteractionQuestion(
                id: "theme",
                header: "主题方向",
                question: "这次你想让我用哪类主题来触发选项？",
                options: [
                    PendingInteractionOption(label: "通用需求 (Recommended)", description: "中性场景。")
                ],
                isOther: false,
                isSecret: false
            )
        ])

        XCTAssertEqual(interaction.presentationMode(canRespondInline: false), .readOnly)
    }

    func testPresentationModeUsesTerminalOnlyWhenQuestionListIsEmpty() {
        let interaction = makeInteraction(questions: [])

        XCTAssertEqual(interaction.presentationMode(canRespondInline: true), .terminalOnly)
        XCTAssertEqual(interaction.presentationMode(canRespondInline: false), .terminalOnly)
    }

    private func makeInteraction(questions: [PendingInteractionQuestion]) -> PendingUserInputInteraction {
        PendingUserInputInteraction(
            id: "call-1",
            title: "Codex needs your input",
            questions: questions,
            transport: .codexLocal(callId: "call-1", turnId: "turn-1")
        )
    }
}

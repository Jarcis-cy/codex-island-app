import XCTest
@testable import Codex_Island

final class ToolResultDecoderTests: XCTestCase {
    // 锁住 Read 的嵌套 file payload 兼容，避免拆 decoder 后丢掉旧 transcript 结构。
    func testDecodeReadSupportsNestedFilePayload() {
        let result = ToolResultDecoder.decode(
            toolName: "Read",
            toolUseResult: [
                "file": [
                    "filePath": "/tmp/example.txt",
                    "content": "line 1\nline 2",
                    "numLines": 2,
                    "startLine": 5,
                    "totalLines": 20
                ]
            ],
            isError: false
        )

        guard case .read(let read) = result else {
            return XCTFail("Expected read result")
        }

        XCTAssertEqual(read.filePath, "/tmp/example.txt")
        XCTAssertEqual(read.content, "line 1\nline 2")
        XCTAssertEqual(read.numLines, 2)
        XCTAssertEqual(read.startLine, 5)
        XCTAssertEqual(read.totalLines, 20)
    }

    // Edit/Write 共享 structuredPatch 解析 helper，这里用一条样例同时锁住 hunk 字段映射。
    func testDecodeEditParsesStructuredPatch() {
        let result = ToolResultDecoder.decode(
            toolName: "Edit",
            toolUseResult: [
                "filePath": "/tmp/example.swift",
                "oldString": "before",
                "newString": "after",
                "replaceAll": true,
                "userModified": false,
                "structuredPatch": [
                    [
                        "oldStart": 10,
                        "oldLines": 2,
                        "newStart": 10,
                        "newLines": 3,
                        "lines": ["-before", "+after", "+extra"]
                    ]
                ]
            ],
            isError: false
        )

        guard case .edit(let edit) = result else {
            return XCTFail("Expected edit result")
        }

        XCTAssertEqual(edit.filePath, "/tmp/example.swift")
        XCTAssertEqual(edit.oldString, "before")
        XCTAssertEqual(edit.newString, "after")
        XCTAssertEqual(edit.replaceAll, true)
        XCTAssertEqual(edit.structuredPatch?.count, 1)
        XCTAssertEqual(edit.structuredPatch?.first?.oldStart, 10)
        XCTAssertEqual(edit.structuredPatch?.first?.lines, ["-before", "+after", "+extra"])
    }

    // MCP 工具名的 server/tool 拆分规则较怪，单测可以防止后续再次把 `mcp__` 前缀解析坏掉。
    func testDecodeMCPExtractsServerAndToolName() {
        let result = ToolResultDecoder.decode(
            toolName: "mcp__chrome_devtools__click",
            toolUseResult: ["uid": "button-1"],
            isError: false
        )

        guard case .mcp(let mcp) = result else {
            return XCTFail("Expected mcp result")
        }

        XCTAssertEqual(mcp.serverName, "chrome_devtools")
        XCTAssertEqual(mcp.toolName, "click")
        XCTAssertEqual(mcp.rawResult["uid"] as? String, "button-1")
    }

    // AskUserQuestion 的 questions/options/answers 是嵌套最深的一类输入，拆 helper 后要锁住完整映射。
    func testDecodeAskUserQuestionParsesQuestionsOptionsAndAnswers() {
        let result = ToolResultDecoder.decode(
            toolName: "AskUserQuestion",
            toolUseResult: [
                "questions": [
                    [
                        "header": "下一步",
                        "question": "要怎么继续？",
                        "options": [
                            [
                                "label": "继续实现",
                                "description": "直接开始修改代码"
                            ],
                            [
                                "label": "补充调研"
                            ]
                        ]
                    ]
                ],
                "answers": [
                    "next_step": "继续实现"
                ]
            ],
            isError: false
        )

        guard case .askUserQuestion(let question) = result else {
            return XCTFail("Expected ask user question result")
        }

        XCTAssertEqual(question.questions.count, 1)
        XCTAssertEqual(question.questions.first?.header, "下一步")
        XCTAssertEqual(question.questions.first?.options.map(\.label), ["继续实现", "补充调研"])
        XCTAssertEqual(question.questions.first?.options.first?.description, "直接开始修改代码")
        XCTAssertEqual(question.answers["next_step"], "继续实现")
    }
}

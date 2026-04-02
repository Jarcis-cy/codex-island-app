//
//  RemoteChatView.swift
//  CodexIsland
//
//  Chat surface for app-server managed remote threads.
//

import SwiftUI

enum RemoteChatSubmitAction: Equatable {
    case send(String)
    case presentSlashCommand(RemoteSlashCommand)
    case rejectSlashCommand(String)
}

enum RemoteSlashCommand: String, CaseIterable, Identifiable {
    case plan = "/plan"
    case model = "/model"
    case permissions = "/permissions"
    case resume = "/resume"

    var id: String { rawValue }

    var title: String { rawValue }

    var description: String {
        switch self {
        case .plan:
            return "进入或退出计划模式"
        case .model:
            return "查看或请求切换模型"
        case .permissions:
            return "查看或请求调整权限策略"
        case .resume:
            return "恢复同一远端主机上的其它线程"
        }
    }

    static func exactMatch(for text: String) -> RemoteSlashCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first(where: { $0.rawValue == trimmed })
    }

    static func matches(for text: String) -> [RemoteSlashCommand] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }
        return allCases.filter { $0.rawValue.hasPrefix(trimmed.lowercased()) }
    }

    static func submitAction(for text: String) -> RemoteChatSubmitAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let command = exactMatch(for: trimmed) {
            return .presentSlashCommand(command)
        }
        if trimmed.hasPrefix("/") {
            return .rejectSlashCommand("Unsupported remote command: \(trimmed)")
        }
        return .send(trimmed)
    }
}

struct RemoteChatView: View {
    let initialThread: RemoteThreadState
    @ObservedObject var remoteSessionMonitor: RemoteSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @State private var thread: RemoteThreadState
    @State private var inputText: String = ""
    @State private var shouldScrollToBottom: Bool = false
    @State private var isAutoscrollPaused = false
    @State private var newMessageCount = 0
    @State private var previousHistoryCount = 0
    @State private var activeSlashCommand: RemoteSlashCommand?
    @State private var slashFeedbackMessage: String?
    @State private var customModelName: String = ""
    @State private var isExecutingSlashAction = false
    @FocusState private var isInputFocused: Bool

    init(
        initialThread: RemoteThreadState,
        remoteSessionMonitor: RemoteSessionMonitor,
        viewModel: NotchViewModel
    ) {
        self.initialThread = initialThread
        self.remoteSessionMonitor = remoteSessionMonitor
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._thread = State(initialValue: initialThread)
    }

    private var history: [ChatHistoryItem] {
        thread.history
    }

    private var pendingInteraction: PendingInteraction? {
        thread.primaryPendingInteraction
    }

    private var matchingSlashCommands: [RemoteSlashCommand] {
        guard activeSlashCommand == nil else { return [] }
        return RemoteSlashCommand.matches(for: inputText)
    }

    private var availableResumeThreads: [RemoteThreadState] {
        remoteSessionMonitor.availableThreads(hostId: thread.hostId, excluding: thread.threadId)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if history.isEmpty {
                emptyState
            } else {
                messageList
            }

            if let pendingInteraction {
                PendingInteractionBar(
                    interaction: pendingInteraction,
                    canRespondInline: true,
                    canOpenTerminal: false,
                    onApprovalAction: { action in
                        respondToApproval(action)
                    },
                    onSubmitAnswers: { answers in
                        await respondToQuestions(answers)
                    },
                    onOpenTerminal: {}
                )
                .id(pendingInteraction.id)
            } else {
                composer
            }
        }
        .task {
            remoteSessionMonitor.refreshHost(id: initialThread.hostId)
            if !initialThread.isLoaded {
                if let updated = try? await remoteSessionMonitor.openThread(
                    hostId: initialThread.hostId,
                    threadId: initialThread.threadId
                ) {
                    thread = updated
                }
            }
        }
        .onReceive(remoteSessionMonitor.$threads) { threads in
            if let updated = threads.first(where: { $0.stableId == thread.stableId }) {
                let countChanged = updated.history.count != thread.history.count
                if isAutoscrollPaused && updated.history.count > previousHistoryCount {
                    newMessageCount += updated.history.count - previousHistoryCount
                    previousHistoryCount = updated.history.count
                }
                thread = updated
                if countChanged && !isAutoscrollPaused {
                    shouldScrollToBottom = true
                }
            }
        }
        .onChange(of: thread.canSendMessage) { _, canSend in
            if canSend && !isInputFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if thread.canSendMessage {
                    isInputFocused = true
                }
            }
        }
        .onChange(of: inputText) { _, newValue in
            if activeSlashCommand == nil,
               !newValue.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
                slashFeedbackMessage = nil
            }
        }
    }

    @State private var isHeaderHovered = false

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.exitChat()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.6))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(thread.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                Text(thread.sourceDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }

            Spacer()

            if thread.canInterrupt {
                Button {
                    interrupt()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
        .onHover { isHeaderHovered = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text("No thread history yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let fadeColor = Color.black

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")

                    ForEach(history.reversed()) { item in
                        MessageItemView(item: item, sessionId: thread.logicalSessionId)
                            .padding(.horizontal, 16)
                            .scaleEffect(x: 1, y: -1)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .scaleEffect(x: 1, y: -1)
            .onChange(of: shouldScrollToBottom) { _, shouldScroll in
                if shouldScroll {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    shouldScrollToBottom = false
                    resumeAutoscroll()
                }
            }
            .overlay(alignment: .bottom) {
                if isAutoscrollPaused && newMessageCount > 0 {
                    NewMessagesIndicator(count: newMessageCount) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        resumeAutoscroll()
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let activeSlashCommand {
                slashActionPanel(for: activeSlashCommand)
            } else if !matchingSlashCommands.isEmpty {
                slashSuggestionsPanel
            }

            if let slashFeedbackMessage, !slashFeedbackMessage.isEmpty {
                slashFeedbackBanner(message: slashFeedbackMessage)
            }

            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(inputPrompt, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(thread.canSendMessage ? .white : .white.opacity(0.4))
                .focused($isInputFocused)
                .disabled(!thread.canSendMessage)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(thread.canSendMessage ? 0.08 : 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .onSubmit {
                    handleSubmit()
                }

            Button {
                handleSubmit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(!thread.canSendMessage || inputText.isEmpty ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(!thread.canSendMessage || inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [fadeColor.opacity(0), fadeColor.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: -24)
            .allowsHitTesting(false)
        }
    }

    private var slashSuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remote commands")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            ForEach(matchingSlashCommands) { command in
                Button {
                    presentSlashCommand(command)
                } label: {
                    HStack(spacing: 10) {
                        Text(command.title)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                        Text(command.description)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func slashFeedbackBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundColor(TerminalColors.amber)

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 16)
    }

    private func slashActionPanel(for command: RemoteSlashCommand) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(command.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                Text(command.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Button {
                    dismissSlashCommand()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            switch command {
            case .plan:
                slashActionButton("进入计划模式", note: "发送语义化请求到远端 Codex") {
                    await sendSlashPrompt(
                        "请进入计划模式，并先用简短中文说明你已经进入计划模式。后续回答保持计划模式。"
                    )
                }
                slashActionButton("退出计划模式", note: "让远端 Codex 自行退出 plan mode") {
                    await sendSlashPrompt(
                        "请退出计划模式，并用简短中文确认已经退出计划模式。"
                    )
                }
                slashActionButton("说明当前计划模式", note: "仅查询当前状态") {
                    await sendSlashPrompt(
                        "请说明当前线程是否处于计划模式；如果不是，也请直接说明。"
                    )
                }

            case .model:
                slashActionButton("查看当前模型", note: "查询当前 thread 正在使用的模型") {
                    await sendSlashPrompt(
                        "请告诉我当前这个远端会话正在使用的模型和 provider，并说明当前是否支持切换模型。"
                    )
                }
                slashActionButton("请求切换到 gpt-5.4", note: "不会伪装成底层 RPC 已成功") {
                    await sendSlashPrompt(
                        "如果当前环境支持，请切换到 gpt-5.4；如果不支持，请明确说明原因和可用替代项。"
                    )
                }
                slashActionButton("请求切换到 gpt-5.3-codex", note: "由远端 Codex 决定是否支持") {
                    await sendSlashPrompt(
                        "如果当前环境支持，请切换到 gpt-5.3-codex；如果不支持，请明确说明原因和可用替代项。"
                    )
                }
                HStack(spacing: 8) {
                    TextField("Custom model name", text: $customModelName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                        )

                    Button("请求切换") {
                        let modelName = customModelName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !modelName.isEmpty else { return }
                        Task {
                            await sendSlashPrompt(
                                "如果当前环境支持，请切换到模型 `\(modelName)`；如果不支持，请说明原因和可用替代项。"
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(customModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.2 : 0.9))
                    .clipShape(Capsule())
                    .disabled(customModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecutingSlashAction)
                }

            case .permissions:
                slashActionButton("查看当前权限", note: "查询 approval policy / sandbox / permissions") {
                    await sendSlashPrompt(
                        "请说明当前这个远端会话的 permissions、approval policy 和 sandbox 配置。"
                    )
                }
                slashActionButton("请求 workspace-write", note: "如果不能直接调整，就要求远端说明如何操作") {
                    await sendSlashPrompt(
                        "如果当前环境支持，请把当前会话调整为 workspace-write 级别并保留网络限制；如果不能直接调整，请说明需要我怎么操作。"
                    )
                }
                slashActionButton("请求 full access", note: "如果不能直接调整，就要求远端说明如何操作") {
                    await sendSlashPrompt(
                        "如果当前环境支持，请把当前会话调整为 full access；如果不能直接调整，请说明需要我怎么操作。"
                    )
                }

            case .resume:
                if availableResumeThreads.isEmpty {
                    Text("No other remote threads available on this host")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.vertical, 4)
                } else {
                    ForEach(availableResumeThreads) { candidate in
                        Button {
                            Task {
                                await resumeRemoteThread(candidate)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(candidate.displayTitle)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.88))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(candidate.updatedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.35))
                                }
                                Text(candidate.sourceDetail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isExecutingSlashAction)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func slashActionButton(
        _ title: String,
        note: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
                Text(note)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(isExecutingSlashAction)
    }

    private var inputPrompt: String {
        if thread.canSteerTurn {
            return "Steer active turn..."
        }
        if thread.canStartTurn {
            return "Message remote Codex..."
        }
        return "Remote thread is busy"
    }

    private func pauseAutoscroll() {
        isAutoscrollPaused = true
        previousHistoryCount = history.count
    }

    private func resumeAutoscroll() {
        isAutoscrollPaused = false
        newMessageCount = 0
        previousHistoryCount = history.count
    }

    private func handleSubmit() {
        guard let action = RemoteSlashCommand.submitAction(for: inputText) else { return }

        switch action {
        case .send(let text):
            inputText = ""
            slashFeedbackMessage = nil
            resumeAutoscroll()
            shouldScrollToBottom = true

            Task {
                try? await remoteSessionMonitor.sendMessage(thread: thread, text: text)
            }

        case .presentSlashCommand(let command):
            presentSlashCommand(command)

        case .rejectSlashCommand(let message):
            slashFeedbackMessage = message
        }
    }

    private func presentSlashCommand(_ command: RemoteSlashCommand) {
        activeSlashCommand = command
        slashFeedbackMessage = command == .resume
            ? "Selecting a thread here resumes it locally instead of sending `/resume` into the current conversation."
            : "This command opens a local interaction first and then sends a semantic request to remote Codex."
        inputText = ""
        customModelName = ""
        resumeAutoscroll()
    }

    private func dismissSlashCommand() {
        activeSlashCommand = nil
        customModelName = ""
    }

    private func sendSlashPrompt(_ prompt: String) async {
        isExecutingSlashAction = true
        defer {
            isExecutingSlashAction = false
        }
        resumeAutoscroll()
        shouldScrollToBottom = true

        do {
            try await remoteSessionMonitor.sendMessage(thread: thread, text: prompt)
            activeSlashCommand = nil
            slashFeedbackMessage = nil
            customModelName = ""
        } catch {
            slashFeedbackMessage = error.localizedDescription
        }
    }

    private func resumeRemoteThread(_ candidate: RemoteThreadState) async {
        isExecutingSlashAction = true
        defer {
            isExecutingSlashAction = false
        }

        do {
            let opened = try await remoteSessionMonitor.openThread(
                hostId: candidate.hostId,
                threadId: candidate.threadId
            )
            await MainActor.run {
                activeSlashCommand = nil
                slashFeedbackMessage = nil
                customModelName = ""
                viewModel.showRemoteChat(for: opened)
            }
        } catch {
            await MainActor.run {
                slashFeedbackMessage = error.localizedDescription
            }
        }
    }

    private func interrupt() {
        Task {
            try? await remoteSessionMonitor.interrupt(thread: thread)
        }
    }

    private func approve() {
        Task {
            try? await remoteSessionMonitor.approve(thread: thread)
        }
    }

    private func deny() {
        Task {
            try? await remoteSessionMonitor.deny(thread: thread)
        }
    }

    private func respondToApproval(_ action: PendingApprovalAction) {
        Task {
            try? await remoteSessionMonitor.respond(thread: thread, action: action)
        }
    }

    private func respondToQuestions(_ answers: PendingInteractionAnswerPayload) async -> Bool {
        guard case .userInput(let interaction)? = pendingInteraction else { return false }
        do {
            try await remoteSessionMonitor.respond(thread: thread, interaction: interaction, answers: answers)
            return true
        } catch {
            return false
        }
    }
}

import SwiftUI

struct AccountManagementView: View {
    @Environment(AccountLifecycleStore.self) private var lifecycleStore
    @State private var showingChallenge = false
    @State private var showingDeletionConfirmation = false

    var body: some View {
        @Bindable var store = lifecycleStore

        Group {
            if case .deletionCompleted(let status) = store.state {
                completedView(status)
            } else if case .receiptStatus(let status) = store.state {
                receiptStatusView(status)
            } else if case .status(let status) = store.state {
                statusView(status)
            } else {
                Form {
                    Section {
                        Text("重新验证后可查看注册审核和账号状态。这里使用独立的短期会话，不会进入学习功能。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("验证账号") {
                        TextField("手机号", text: $store.managementPhone)
                            .keyboardType(.numberPad)
                            .textContentType(.telephoneNumber)
                        SecureField("密码", text: $store.managementPassword)
                            .textContentType(.password)
                    }

                    if case .failure(let message) = store.state {
                        Section {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if store.canRetryDeletionReceiptSave {
                        Section("注销回执") {
                            Button("重试保存注销回执") {
                                store.retryPersistDeletionReceipt()
                            }
                        }
                    }

                    Section {
                        Button {
                            if store.validateManagementForChallenge() {
                                showingChallenge = true
                            }
                        } label: {
                            if store.isManaging {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("验证并查看状态").frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(store.isManaging)
                    }

                    if store.hasDeletionReceipt {
                        Section("注销回执") {
                            Button("查看注销处理进度") {
                                Task { await store.refreshReceiptStatus() }
                            }
                            .disabled(store.isDeletionInFlight)
                            Text("回执可在退出登录后继续查询，不需要学习账号令牌。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("申请与账号状态")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if case .deletionCompleted = store.state {
                return
            }
            store.dismissManagement()
        }
        .sheet(isPresented: $showingChallenge) {
            NavigationStack {
                TurnstileChallengeView { token in
                    showingChallenge = false
                    store.setManagementChallengeToken(token)
                    Task { await store.authenticateAndLoadStatus() }
                } onFailure: { message in
                    showingChallenge = false
                    store.challengeFailed(message)
                }
                .navigationTitle("人机验证")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingChallenge = false }
                    }
                }
            }
        }
        .confirmationDialog(
            "确认提交账号注销申请？",
            isPresented: $showingDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("提交注销申请", role: .destructive) {
                Task { await store.requestDeletion() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("注销会影响 senior 平台网页和 App 登录，并删除词汇、练习、作文、辅导与学习计划等账号数据。")
        }
    }

    @ViewBuilder
    private func statusView(_ response: AccountStatusResponse) -> some View {
        @Bindable var store = lifecycleStore
        List {
            Section("当前状态") {
                LabeledContent("账号", value: title(for: response.accountStatus))
                Text(detail(for: response.accountStatus))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if response.accountStatus == .rejected,
                   let reason = response.rejectionReason,
                   !reason.isEmpty {
                    LabeledContent("未通过原因", value: reason)
                }
            }

            if let deletion = response.deletionRequest {
                Section("注销进度") {
                    deletionStatusRows(deletion)
                    if deletion.status == .requested {
                        Button("撤回注销申请", role: .destructive) {
                            Task { await lifecycleStore.cancelDeletion() }
                        }
                        .disabled(lifecycleStore.isDeletionInFlight)
                    }
                }
            }

            if response.deletionPolicy.enabled,
               response.deletionRequest == nil || response.deletionRequest?.status == .cancelled {
                Section("注销账号") {
                    Text("注销将同时影响网页端登录，以及该账号的词汇、练习、作文、辅导和学习计划数据。提交前请先同步仍保存在本机的学习结果。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("注销理由（选填）", text: $store.deletionReason)
                    TextField("输入 DELETE_ACCOUNT 确认", text: $store.deletionConfirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("申请注销账号", role: .destructive) {
                        showingDeletionConfirmation = true
                    }
                    .disabled(
                        lifecycleStore.isDeletionInFlight
                            || lifecycleStore.deletionConfirmation != "DELETE_ACCOUNT"
                    )
                }
            } else if !response.deletionPolicy.enabled {
                Section("注销账号") {
                    Text("账号注销功能尚未启用，请稍后再试。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = lifecycleStore.deletionMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button("刷新状态") {
                    Task { await lifecycleStore.refreshStatus() }
                }
            }
        }
    }

    private func receiptStatusView(_ response: ReceiptStatusResponse) -> some View {
        List {
            Section("注销进度") {
                deletionStatusRows(response)
            }
            Section {
                Button("刷新处理进度") {
                    Task { await lifecycleStore.refreshReceiptStatus() }
                }
                .disabled(lifecycleStore.isDeletionInFlight)
            }
        }
    }

    private func completedView(_ response: ReceiptStatusResponse) -> some View {
        List {
            Section("账号注销已完成") {
                Label("服务器已确认账号注销完成", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let completedAt = response.completedAt {
                    LabeledContent("完成时间", value: completedAt.formatted())
                }
                Text("本机学习缓存、待同步结果、打卡、个人设置及账号凭据已清理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("返回登录") {
                    lifecycleStore.dismissManagement()
                }
            }
        }
    }

    @ViewBuilder
    private func deletionStatusRows(_ deletion: DeletionStatusSummary) -> some View {
        LabeledContent("状态", value: deletionTitle(deletion.status))
        LabeledContent("提交时间", value: deletion.requestedAt.formatted())
        LabeledContent("预计处理期限", value: deletion.dueAt.formatted())
        if deletion.status == .failed {
            Text("处理遇到异常，管理员可继续处理。账号不会被误报为已注销。")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func title(for status: AccountStatus) -> String {
        switch status {
        case .pendingApproval: "等待审核"
        case .active: "已启用"
        case .rejected: "申请未通过"
        case .disabled: "已停用"
        case .deleting: "注销处理中"
        }
    }

    private func detail(for status: AccountStatus) -> String {
        switch status {
        case .pendingApproval: "管理员审核通过后即可使用学习功能。"
        case .active: "账号已可正常登录网页和 App。"
        case .rejected: "请查看管理员提供的原因；内部备注不会在此显示。"
        case .disabled: "账号当前不能进入学习功能。"
        case .deleting: "账号正在注销处理中，不能恢复学习访问。"
        }
    }

    private func deletionTitle(_ status: DeletionRequestStatus) -> String {
        switch status {
        case .requested: "已收到"
        case .processing: "处理中"
        case .completed: "已完成"
        case .failed: "处理异常"
        case .cancelled: "已撤回"
        }
    }
}

#Preview {
    NavigationStack { AccountManagementView() }
        .environment(AccountLifecycleStore())
}

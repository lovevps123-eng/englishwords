import SwiftUI

struct AccountManagementView: View {
    @Environment(AccountLifecycleStore.self) private var lifecycleStore
    @State private var showingChallenge = false

    var body: some View {
        @Bindable var store = lifecycleStore

        Group {
            if case .status(let status) = store.state {
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
                }
            }
        }
        .navigationTitle("申请与账号状态")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.dismissManagement() }
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
    }

    @ViewBuilder
    private func statusView(_ response: AccountStatusResponse) -> some View {
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
                    LabeledContent("状态", value: deletionTitle(deletion.status))
                    LabeledContent("提交时间", value: deletion.requestedAt.formatted())
                    LabeledContent("预计处理期限", value: deletion.dueAt.formatted())
                    if deletion.status == .failed {
                        Text("处理遇到异常，管理员可继续处理。账号不会被误报为已注销。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button("刷新状态") {
                    Task { await lifecycleStore.refreshStatus() }
                }
            }
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

import SwiftUI

struct RegistrationView: View {
    @Environment(AccountLifecycleStore.self) private var lifecycleStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingChallenge = false

    private let privacyURL = AppConfiguration.productionBaseURL.appendingPathComponent("privacy")

    var body: some View {
        @Bindable var store = lifecycleStore

        Group {
            if let message = store.registrationPendingMessage {
                ContentUnavailableView {
                    Label("申请已提交", systemImage: "clock.badge.checkmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("返回登录") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Form {
                    Section("基本信息") {
                        TextField("姓名", text: $store.registrationName)
                            .textContentType(.name)
                        TextField("手机号", text: $store.registrationPhone)
                            .keyboardType(.numberPad)
                            .textContentType(.telephoneNumber)

                        Picker("地区", selection: $store.registrationRegionId) {
                            if store.regions.isEmpty {
                                Text("暂无可用地区").tag("")
                            }
                            ForEach(store.regions) { region in
                                Text(region.name).tag(region.id)
                            }
                        }

                        Picker("年级（选填）", selection: $store.registrationGrade) {
                            Text("不填写").tag("")
                            Text("高一").tag("高一")
                            Text("高二").tag("高二")
                            Text("高三").tag("高三")
                        }
                        TextField("学校（选填）", text: $store.registrationSchool)
                    }

                    Section("安全验证") {
                        SecureField("密码（至少 8 位，含字母和数字）", text: $store.registrationPassword)
                            .textContentType(.newPassword)
                        SecureField("确认密码", text: $store.registrationPasswordConfirmation)
                            .textContentType(.newPassword)

                        HStack {
                            TextField("短信验证码（选填）", text: $store.registrationSMSCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button(store.isSendingSMS ? "发送中" : "获取验证码") {
                                Task { await store.sendRegistrationSMS() }
                            }
                            .disabled(store.isSendingSMS)
                        }

                        if let smsMessage = store.smsMessage {
                            Text(smsMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Text("提交后账号进入待审核状态；审核通过前不会登录，也不会获得学习访问权限。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link("查看隐私政策", destination: privacyURL)
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
                            if store.validateRegistrationForChallenge() {
                                showingChallenge = true
                            }
                        } label: {
                            if store.isRegistering {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("提交注册申请").frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(store.isRegistering || store.isLoadingRegions || store.regions.isEmpty)
                    }
                }
            }
        }
        .navigationTitle("申请账号")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadRegions() }
        .sheet(isPresented: $showingChallenge) {
            NavigationStack {
                TurnstileChallengeView { token in
                    showingChallenge = false
                    store.setRegistrationChallengeToken(token)
                    Task { await store.submitRegistration() }
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
}

#Preview {
    NavigationStack { RegistrationView() }
        .environment(AccountLifecycleStore())
}

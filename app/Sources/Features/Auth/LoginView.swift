// LoginView.swift — 手机号+密码登录页。v1 不做注册流程，引导用户去网页版注册。
import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var phone: String = ""
    @State private var password: String = ""

    private var canSubmit: Bool {
        !phone.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !authStore.isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 4) {
                    Text("MASF English")
                        .font(.largeTitle.bold())
                    Text("登录以同步你的学习进度")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    TextField("手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .textFieldStyle(.roundedBorder)

                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage = authStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await authStore.login(phone: phone, password: password) }
                } label: {
                    if authStore.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("登录")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Text("还没有账号？请先在网页版注册")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
        }
        #if DEBUG
        .task { await runSmokeAutoIfNeeded() }
        #endif
    }

    #if DEBUG
    /// 冒烟自动化：自动填账号密码（先留一小段时间给截图脚本拍"登录页已填"），再自动提交登录。
    /// 仅在运行环境显式提供完整冒烟凭据时触发，正常使用不受影响。
    private func runSmokeAutoIfNeeded() async {
        guard let credentials = SmokeAuto.credentials else { return }
        phone = credentials.phone
        password = credentials.password
        try? await Task.sleep(nanoseconds: 500_000_000)
        SmokeAuto.writeMarker("login_filled")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await authStore.login(phone: phone, password: password)
    }
    #endif
}

#Preview {
    LoginView()
        .environment(AuthStore())
}

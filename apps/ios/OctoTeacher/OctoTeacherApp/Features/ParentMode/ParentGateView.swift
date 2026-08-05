import SwiftUI

/// 家长模式门禁页：首次使用引导设置 PIN，之后输入 PIN 验证。
struct ParentGateView: View {
    @Environment(ParentGate.self) private var gate
    @Environment(LocalFamilyStore.self) private var store
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var errorText: String?

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        Form {
            if gate.hasPin {
                unlockSection
            } else {
                setupSection
            }
        }
    }

    // MARK: - 日常验证

    private var unlockSection: some View {
        Section {
            SecureField(lang.pick("输入家长 PIN", "Enter Parent PIN"), text: $pin)
                .keyboardType(.numberPad)
            Button(lang.pick("解锁", "Unlock")) {
                if gate.unlock(with: pin) {
                    errorText = nil
                    pin = ""
                } else {
                    errorText = lang.pick("PIN 不对，再试一次。", "That PIN is incorrect. Try again.")
                }
            }
            .accessibilityIdentifier("parent-mode-unlock")
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(lang.pick("家长验证", "Parent Verification"))
        } footer: {
            Text(lang.pick(
                "这里是给爸爸妈妈用的。输入家长 PIN 后可以审核任务、布置任务。忘记 PIN 时删除并重装 App 可重置（本机数据会清空）。",
                "This area is for parents. Enter the parent PIN to review and assign tasks. If you forget it, deleting and reinstalling the app resets the PIN and clears on-device data."
            ))
        }
    }

    // MARK: - 首次设置

    private var setupSection: some View {
        Section {
            SecureField(lang.pick("设置 4–6 位数字 PIN", "Set a 4–6 digit PIN"), text: $pin)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("parent-mode-setup-pin")
            SecureField(lang.pick("再输入一次确认", "Enter the PIN again"), text: $confirmPin)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("parent-mode-setup-pin-confirm")
            Button(lang.pick("设置并进入家长模式", "Set PIN and Enter Parent Mode")) {
                setupPin()
            }
            .disabled(pin.isEmpty || confirmPin.isEmpty)
            .accessibilityIdentifier("parent-mode-setup-confirm")
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(lang.pick("第一次使用：设置家长 PIN", "First Use: Set a Parent PIN"))
        } footer: {
            Text(lang.pick(
                "家长 PIN 用来防止孩子自己批准任务。请用孩子猜不到的数字，只存在这台手机上。",
                "The parent PIN prevents children from approving their own tasks. Choose digits they cannot guess. The PIN stays on this device."
            ))
        }
    }

    private func setupPin() {
        guard ParentGate.isValidPin(pin) else {
            errorText = lang.pick("PIN 需要是 4–6 位数字。", "The PIN must contain 4–6 digits.")
            return
        }
        guard pin == confirmPin else {
            errorText = lang.pick("两次输入不一致，请重新输入。", "The PINs do not match. Try again.")
            return
        }
        if gate.setPin(pin) {
            errorText = nil
            pin = ""
            confirmPin = ""
        }
    }
}

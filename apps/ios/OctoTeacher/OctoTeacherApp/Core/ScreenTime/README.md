# 屏幕时间执行面（ScreenTime）

本目录是 章鱼老师 iOS 端「奖励兑换 → 屏幕时间会话」的执行面。当前主奖励链路使用
`MockScreenTimeController` 保持单元测试确定性，真机则在 FamilyControls、App Group 和单独 App 选择都就绪时桥接到
`ScreenTimePOCManager`。未就绪时禁止兑换，避免出现“扣了成长积分但设备没有真正解锁”的假成功。

## 主奖励链路（成长积分兑换 / 会话硬化）

`MockScreenTimeController` 是主奖励链路当前使用的确定性执行面，承担会话生命周期：

- `startSession(minutes:now:)`：开启解锁会话，重复解锁抛 `alreadyActive`，不叠加时间。
- `tick(now:)`：倒计时到期 → 生成「到期」收据并进入 `expired`（重锁）。
- `endSessionByParent(now:)` / `reshieldNow()`：家长提前结束 → 生成「家长结束」收据并重锁。
- `simulateDeviceFailure`：仅测试注入，模拟设备命令失败，验证失败回滚。
- `latestDeviceCommandReceipt`：设备命令即时回执。打开命令成功/失败立即可见；到期/家长提前结束会生成重锁命令回执。

会话状态对外只暴露 `shieldState`（locked / unlocked），其中 `expired` 也表现为 locked——**过期窗口绝不保持解锁**。

成长积分安全由 `StartRewardSessionUseCase` 保证：先扣成长积分再下发解锁；任何下发失败都 `refundRewardMinutes` 回滚，**失败会话不会扣成长积分且无法回滚**。

孩子端 `RewardRedemptionView` 和家长端 `RewardStatusView` 必须同时展示：

- 本次兑换结果：成功、余额不足、已有会话、非法分钟、设备失败回滚。
- 设备执行回执：命令是否落地，失败时说明成长积分已保护。
- 会话结束回执：到期/家长提前结束后的已用与未用分钟。

## 真机执行边界（已桥接主链路）

`ScreenTimePOCManager` 在家长端「更多功能 → 设备控制 POC」里验证真实系统能力，并把准备状态暴露给
孩子端 `RewardRedemptionView` 与家长端 `RewardStatusView`：

- 通过 `AuthorizationCenter` 请求 FamilyControls 授权。
- 通过 `FamilyActivityPicker` 选择要遮挡的 App / 类别 / 网域，选择内容只按 token 计数展示。
- 通过 `ManagedSettingsStore("rewardUnlock")` 只豁免孩子明确选择的一个 App；其余 App、分类和网域继续锁定。
- 提供本地 2 分钟解锁演示、前台重锁检查，以及奖励兑换窗口 `startRewardWindow(minutes:now:)`；没有点击令牌的旧入口只在恰好选择一个 App 时执行，避免从多个不透明令牌中随机解锁。
- 15/30 分钟正式窗口由 `章鱼老师ScreenTimeMonitor` DeviceActivity extension 到期恢复完整遮挡，主 App 前台 timer 再做一次补偿检查。
- 活跃窗口和 opaque token 只写入 App Group，不解析、不保存 bundle id。

主奖励链路现在按“真实执行或拒绝兑换”执行：授权 approved、App Group 生效且已有单独 App 选择时，先调用
`ScreenTimePOCManager.startSingleAppRewardWindow` 打开真实窗口，再让 `MockScreenTimeController.adoptExternalUnlock`
接管本地状态、倒计时和回执展示；真实执行失败时，`StartRewardSessionUseCase` 退回已扣成长积分并记录设备命令失败。

网站安全由独立的 `ManagedSettingsStore("webSafety")` 承担：系统自动成人内容过滤叠加本地 20 个推荐域名和家长自定义域名。奖励兑换、紧急解锁和 POC 解锁都不会清除该 store。章鱼老师 只保存规则，不收集浏览历史。

紧急解锁由独立审批库维护：孩子申请固定 30 分钟，家长批准后孩子一次性选择一个受控 App；不扣成长积分，批准不可跨孩子或重复消费。

## 真实生产接入边界（下一阶段）

真实屏幕时间必须先通过 Apple 家长授权（`FamilyControls` / `AuthorizationCenter`），且只能在用户显式授权后操作。当前边界如下：

| 能力 | Apple 框架 / Target | 未来职责 | 当前边界 |
|---|---|---|---|
| 选择并遮挡 App | `FamilyControls` + `ManagedSettings` | 家长选定受控范围，孩子每次只豁免一个 App | 已实现，需真机授权 |
| 到期自动重锁 | `DeviceActivityMonitor` extension | 系统到期恢复完整遮挡 | 已实现，需付费开发者签名真机验证 |
| 成人网站过滤 | `ManagedSettings.webContent` | 自动分类 + 补充域名，且不收集历史 | 已实现，需真机 Safari 验证 |
| Shield 自定义动作 | `ManagedSettingsUI` / `ShieldActionExtension`（`ShieldAction`） | 用户点遮挡页按钮时的处理（关闭 / 请求更多时间） | 未实现 |
| Shield 外观 | `ManagedSettingsUI`（`ShieldConfigurationExtension` / `ShieldConfiguration`） | 自定义遮挡页文案与样式 | 未实现 |

接入时的硬性约束（与产品安全边界一致）：

- 必须走真实 Apple 家长授权，不得绕过。
- App Group 在 App 与扩展间只传**会话分钟与时间戳**这类最小数据，不传孩子隐私字段、真实 bundle id、设备标识或局域网地址。
- `DeviceActivity` schedule 到期必须真实重锁；任何「到期仍解锁」都视为安全缺陷。
- 真实设备控制只在跑通本 mock 闭环、并完成家长授权链路后才接生产 entitlement。

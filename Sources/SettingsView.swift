import SwiftUI
import Combine

private func notifySettingsChanged() {
    NotificationCenter.default.post(name: .settingsChanged, object: nil)
}

extension View {
    /// @AppStorage の変更をバックエンド（TouchGestureManager / EventInterceptor）へ伝える。
    func notifyOnChange<V: Equatable>(of value: V) -> some View {
        self.onChange(of: value) { _, _ in notifySettingsChanged() }
    }
}

/// 3本指タップに割り当てられる ActionKind の種別(設定UI用)。
private enum BoundActionKind: String, CaseIterable, Identifiable {
    case macro
    case trackpadToggle
    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .macro: return NSLocalizedString("マクロ", comment: "3本指タップの割り当て種別")
        case .trackpadToggle: return NSLocalizedString("トラックパッドモード切替", comment: "3本指タップの割り当て種別")
        }
    }
}

/// Window-local UI state. StateObject also builds with Command Line Tools
/// installations that do not ship the SwiftUI StateMacro plugin.
private final class SettingsTransientState: ObservableObject {
    @Published var showDiagnostics = false
    @Published var permissionGranted = false
    @Published var deviceCount = 0
    @Published var page: SettingsPage = .trackpad
    @Published var recognitionExpanded = false
    @Published var vetoExpanded = false
    @Published var zoneExpanded = false
    @Published var speedExpanded = false
    @Published var diagnosticsExpanded = false
    @Published var tap3ActionKind: BoundActionKind = AppSettings.shared.threeFingerTapAction.isTrackpadToggle ? .trackpadToggle : .macro
    @Published var cachedTap3MacroAction: ActionKind = {
        if case .macro = AppSettings.shared.threeFingerTapAction {
            return AppSettings.shared.threeFingerTapAction
        }
        return .macro([])
    }()
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case common, trackpad, mouse, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .common: return NSLocalizedString("常用", comment: "Settings category")
        case .trackpad: return NSLocalizedString("トラックパッドモード", comment: "Settings category")
        case .mouse: return NSLocalizedString("鼠标模式", comment: "Settings category")
        case .advanced: return NSLocalizedString("高级与诊断", comment: "Settings category")
        }
    }
}

/// Settings are grouped by task; navigation never changes the active input mode.
struct SettingsView: View {
    // 一般
    @AppStorage(AppSettings.Key.enabled) private var enabled: Bool = true
    @AppStorage(AppSettings.Key.startInTrackpadMode) private var startInTrackpadMode: Bool = true

    // ジェスチャー
    @AppStorage(AppSettings.Key.oneFingerTapEnabled) private var oneFingerTapEnabled: Bool = true
    @AppStorage(AppSettings.Key.tapAlwaysLeftClick) private var tapAlwaysLeftClick: Bool = false
    @AppStorage(AppSettings.Key.twoFingerTapEnabled) private var twoFingerTapEnabled: Bool = true
    @AppStorage(AppSettings.Key.threeFingerTapEnabled) private var threeFingerTapEnabled: Bool = false
    @ObservedObject private var macroRecorder = MacroRecorder.shared
    @AppStorage(AppSettings.Key.middleClickEnabled) private var middleClickEnabled: Bool = true
    @AppStorage(AppSettings.Key.verticalScrollOnly) private var verticalScrollOnly: Bool = false
    @AppStorage(AppSettings.Key.rightZoneMinX) private var rightZoneMinX: Double = 0.6

    // 反応範囲
    @AppStorage(AppSettings.Key.zoneMinX) private var zoneMinX: Double = 0.0
    @AppStorage(AppSettings.Key.zoneMaxX) private var zoneMaxX: Double = 1.0
    @AppStorage(AppSettings.Key.zoneMinY) private var zoneMinY: Double = 0.75
    @AppStorage(AppSettings.Key.zoneMaxY) private var zoneMaxY: Double = 1.0

    // 感度
    @AppStorage(AppSettings.Key.tapMaxDuration) private var tapMaxDuration: Double = 0.25
    @AppStorage(AppSettings.Key.tapMaxStraightDistance) private var tapMaxStraightDistance: Double = 0.15
    @AppStorage(AppSettings.Key.tapMaxPathLength) private var tapMaxPathLength: Double = 0.18
    @AppStorage(AppSettings.Key.tapMaxVelocity) private var tapMaxVelocity: Double = 4.0
    @AppStorage(AppSettings.Key.tapMinFrames) private var tapMinFrames: Int = 2

    // 誤反応対策
    @AppStorage(AppSettings.Key.scrollVetoWindow) private var scrollVetoWindow: Double = 0.20
    @AppStorage(AppSettings.Key.buttonVetoWindow) private var buttonVetoWindow: Double = 0.10
    @AppStorage(AppSettings.Key.twoFingerSyncWindow) private var twoFingerSyncWindow: Double = 0.08

    // トラッキング速度ブースト
    @AppStorage(AppSettings.Key.pointerSpeedBoost) private var pointerSpeedBoost: Double = 0.0

    // 仮想トラックパッドモード
    @AppStorage(AppSettings.Key.trackpadModeGain) private var trackpadModeGain: Double = 1000.0
    @AppStorage(AppSettings.Key.trackpadAccelerationStrength) private var trackpadAccelerationStrength: Double = 1.0
    @AppStorage(AppSettings.Key.trackpadModeOrientation) private var trackpadModeOrientation: Int = 0
    @AppStorage(AppSettings.Key.trackpadTapZones) private var trackpadTapZones: Bool = false
    @AppStorage(AppSettings.Key.trackpadTapDragEnabled) private var trackpadTapDragEnabled: Bool = true
    @AppStorage(AppSettings.Key.trackpadSidewaysAspectRatio) private var trackpadSidewaysAspectRatio: Double = 2.0

    @ObservedObject private var debugFeed = DebugFeed.shared
    @ObservedObject private var trackpadMode = TrackpadModeController.shared
    @StateObject private var transient = SettingsTransientState()

    /// MacroRecorder のセッションラベル(保存先の確定と録画中の相互排他に使う)
    private let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let tap3MacroLabel = "tap3"

    private var tapMinFramesBinding: Binding<Double> {
        Binding(
            get: { Double(tapMinFrames) },
            set: { tapMinFrames = Int($0.rounded()) }
        )
    }

    /// 現在UserDefaultsに保存されているマクロのイベント数(録画セッション外の状態表示用)。
    private var savedMacroEventCount: Int {
        if case .macro(let events) = AppSettings.shared.threeFingerTapAction {
            return events.count
        }
        return 0
    }

    private var isRecordingTap3Macro: Bool {
        macroRecorder.isRecording && macroRecorder.sessionLabel == Self.tap3MacroLabel
    }

    /// 「先端から◯%」表現。zoneMinY=0.75 は先端から25%。
    private var frontDepthBinding: Binding<Double> {
        Binding(
            get: { 1.0 - zoneMinY },
            set: { zoneMinY = min(1.0 - $0, zoneMaxY) }
        )
    }

    private func l(_ key: String) -> String { NSLocalizedString(key, comment: "Settings") }
    private var leftBoundary: Binding<Double> {
        Binding(get: { zoneMinX }, set: { zoneMinX = min($0, zoneMaxX) })
    }
    private var rightBoundary: Binding<Double> {
        Binding(get: { zoneMaxX }, set: { zoneMaxX = max($0, zoneMinX) })
    }
    private var rearBoundary: Binding<Double> {
        Binding(get: { zoneMinY }, set: { zoneMinY = min($0, zoneMaxY) })
    }
    private var frontBoundary: Binding<Double> {
        Binding(get: { zoneMaxY }, set: { zoneMaxY = max($0, zoneMinY) })
    }
    private var liveDiagnosticsEnabled: Bool {
        transient.page == .advanced && transient.diagnosticsExpanded && transient.showDiagnostics
    }
    private var modeBinding: Binding<Bool> {
        Binding(get: { trackpadMode.isActive }, set: { value in
            if value != trackpadMode.isActive { trackpadMode.toggle() }
        })
    }
    private var diagnosticsBinding: Binding<Bool> {
        Binding(get: { transient.showDiagnostics }, set: { value in
            transient.showDiagnostics = value
            debugFeed.isActive = value && transient.page == .advanced && transient.diagnosticsExpanded
        })
    }
    private func refreshStatus() {
        transient.permissionGranted = SharedState.shared.accessibilityGranted
        transient.deviceCount = MultitouchDeviceManager.shared.activeDeviceCount
    }

    var body: some View {
        VStack(spacing: DS.Space.l) {
            header
            Picker("", selection: $transient.page) {
                ForEach(SettingsPage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, DS.Layout.contentLeading)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    pageHeading
                    switch transient.page {
                    case .common: commonPage
                    case .trackpad: trackpadPage
                    case .mouse: mousePage
                    case .advanced: advancedPage
                    }
                }
                .padding(.horizontal, DS.Layout.contentLeading)
                .padding(.bottom, DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(transient.page)
        }
        .padding(.top, DS.Layout.contentTop)
        .font(DS.Font.body)
        .scrollEdgeEffectHidden(true, for: .top)
        .frame(width: DS.Layout.windowSize.width, height: DS.Layout.windowSize.height)
        .background(
            ZStack {
                SwiftUI.Color.clear.glassEffect(.regular, in: Rectangle())
                RoundedRectangle(cornerRadius: DS.Plate.radius, style: .continuous)
                    .fill(DS.Color.plateBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Plate.radius, style: .continuous)
                            .fill(DS.Color.plateCore).blur(radius: DS.Plate.fadeBlur)
                            .padding(DS.Plate.fadeWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Plate.radius, style: .continuous))
                    .padding(DS.Plate.inset)
            }.ignoresSafeArea()
        )
        .onAppear { refreshStatus(); debugFeed.isActive = liveDiagnosticsEnabled }
        .onDisappear { debugFeed.isActive = false }
        .onChange(of: liveDiagnosticsEnabled) { _, value in debugFeed.isActive = value }
        .onReceive(statusTimer) { _ in if transient.page == .common { refreshStatus() } }
        .onChange(of: transient.tap3ActionKind) { _, kind in
            if kind == .trackpadToggle {
                if case .macro = AppSettings.shared.threeFingerTapAction {
                    transient.cachedTap3MacroAction = AppSettings.shared.threeFingerTapAction
                }
                AppSettings.shared.threeFingerTapAction = .toggleTrackpadMode
            } else {
                AppSettings.shared.threeFingerTapAction = transient.cachedTap3MacroAction
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.m) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: DS.Layout.settingsIconSide, height: DS.Layout.settingsIconSide)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            Text("Magic Mouse Toolkit").font(DS.Font.settingsTitle)
            Spacer()
            Text(!enabled ? l("已暂停") : l("当前模式") + "：" + (trackpadMode.isActive ? l("トラックパッドモード") : l("鼠标模式")))
                .font(DS.Font.caption).foregroundStyle(DS.Color.labelSecondary)
        }
        .padding(.horizontal, DS.Layout.contentLeading)
    }

    private var pageHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(transient.page.title).font(DS.Font.settingsTitle)
            Spacer()
            if transient.page == .trackpad || transient.page == .mouse {
                let isCurrent = enabled && (transient.page == .trackpad ? trackpadMode.isActive : !trackpadMode.isActive)
                caption(isCurrent ? "当前正在使用" : "当前未启用，可预先调整")
            }
        }
    }

    private func caption(_ key: String) -> some View {
        Text(l(key)).font(DS.Font.caption).foregroundStyle(DS.Color.labelSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(l(title)).font(DS.Font.sectionHeader).foregroundStyle(DS.Color.labelSecondary)
            content()
        }
    }
    private func row<Control: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(l(title)).fixedSize(horizontal: false, vertical: true)
                    if let detail { caption(detail) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                control()
            }.padding(.vertical, DS.Space.m)
            Divider()
        }
    }
    private func toggle(_ title: String, detail: String? = nil, value: Binding<Bool>) -> some View {
        row(title, detail: detail) {
            Toggle(l(title), isOn: value).labelsHidden().toggleStyle(.switch)
                .controlSize(.small).tint(DS.Color.accent)
        }.notifyOnChange(of: value.wrappedValue)
    }
    private func slider(_ title: String, detail: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        row(title, detail: detail) {
            HStack(spacing: DS.Space.m) {
                Slider(value: value, in: range).controlSize(.small).accessibilityLabel(l(title))
                Text(format(value.wrappedValue)).font(DS.Font.value)
                    .foregroundStyle(DS.Color.labelSecondary)
                    .frame(width: DS.Layout.valueWidth, alignment: .trailing)
            }.frame(width: DS.Layout.settingsControlWidth)
        }.notifyOnChange(of: value.wrappedValue)
    }
    private func percent(_ title: String, value: Binding<Double>) -> some View {
        slider(title, value: value, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
    }
    private func resetButton(_ title: String, action: @escaping () -> Void) -> some View {
        HStack { Spacer(); Button(l(title), action: action).buttonStyle(.bordered).controlSize(.small) }
            .padding(.top, DS.Space.s)
    }

    private var commonPage: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            group("使用状态") {
                toggle("启用鼠标增强", value: $enabled)
                row("使用模式", detail: "鼠标模式保留原生移动；触控板模式用手指滑动控制光标。") {
                    Picker(l("使用模式"), selection: modeBinding) {
                        Text(l("鼠标")).tag(false)
                        Text(l("触控板")).tag(true)
                    }.labelsHidden().pickerStyle(.segmented)
                        .frame(width: DS.Layout.sliderLabelWidth).disabled(!enabled || !transient.permissionGranted)
                }
                toggle("起動時にトラックパッドモードを有効化", detail: "应用启动且权限就绪后自动开启；手动切换模式不受影响。", value: $startInTrackpadMode)
                row("设备") {
                    Text(transient.deviceCount > 0 ? "Magic Mouse" : l("未检测到妙控鼠标"))
                        .foregroundStyle(DS.Color.labelSecondary)
                }
                row("辅助功能权限") {
                    if transient.permissionGranted { Text(l("已授权")).foregroundStyle(DS.Color.labelSecondary) }
                    else {
                        Button(l("打开权限设置…")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            group("共用操作") {
                row("滚动方向", detail: "鼠标模式与触控板模式共用。") {
                    Picker(l("滚动方向"), selection: $verticalScrollOnly) {
                        Text(l("上下与左右")).tag(false)
                        Text(l("仅上下")).tag(true)
                    }.labelsHidden().frame(width: DS.Layout.settingsControlWidth)
                }.notifyOnChange(of: verticalScrollOnly)
                toggle("三指快捷操作", value: $threeFingerTapEnabled)
                if threeFingerTapEnabled { macroSettings }
                caption("菜单栏保留触控板模式快捷开关。")
            }
        }
    }

    private var macroSettings: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            row("操作") {
                Picker(l("操作"), selection: $transient.tap3ActionKind) {
                    Text(l("双击切换使用模式")).tag(BoundActionKind.trackpadToggle)
                    Text(l("轻点执行按键宏")).tag(BoundActionKind.macro)
                }.labelsHidden().frame(width: DS.Layout.settingsControlWidth)
            }
            if transient.tap3ActionKind == .macro {
                HStack(spacing: DS.Space.s) {
                    Text(isRecordingTap3Macro ? String(format: l("録画中… %dイベント"), macroRecorder.recordedEvents.count) : String(format: l("登録済み：%dイベント"), savedMacroEventCount))
                        .font(DS.Font.caption).foregroundStyle(DS.Color.labelSecondary)
                    Spacer()
                    Button(isRecordingTap3Macro ? l("録画を停止して保存") : l("録画を開始")) {
                        if isRecordingTap3Macro { macroRecorder.stop() }
                        else {
                            macroRecorder.start(label: Self.tap3MacroLabel) { events in
                                AppSettings.shared.threeFingerTapAction = .macro(events)
                            }
                        }
                    }.disabled(macroRecorder.isRecording && !isRecordingTap3Macro)
                    Button(l("クリア")) {
                        macroRecorder.clear()
                        AppSettings.shared.threeFingerTapAction = .macro([])
                    }.disabled(macroRecorder.isRecording || savedMacroEventCount == 0)
                }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var trackpadPage: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            group("光标移动") {
                slider("基础移动速度", detail: "控制慢速移动与精细瞄准时的光标距离。", value: $trackpadModeGain, range: 200...3000) { String(format: "%.0f", $0) }
                slider("快速移动加速", detail: "快速连续滑动时提高倍率，减速后回到基础速度。0 表示关闭。", value: $trackpadAccelerationStrength, range: 0...2) { String(format: "%.1f", $0) }
            }
            group("点击与拖动") {
                row("点击方式") {
                    Picker(l("点击方式"), selection: $trackpadTapZones) {
                        Text(l("触控板式")).tag(false)
                        Text(l("左右分区式")).tag(true)
                    }.labelsHidden().frame(width: DS.Layout.settingsControlWidth)
                }.notifyOnChange(of: trackpadTapZones)
                caption(trackpadTapZones ? "单指轻点按左右区域区分；双指轻点为左键。" : "单指轻点为左键；双指轻点为右键。")
                if trackpadTapZones {
                    percent("右键区域起点", value: $rightZoneMinX)
                    toggle("2本指タップで左クリック", value: $twoFingerTapEnabled)
                }
                toggle("双轻点拖动", detail: "第二次轻触后不抬手，滑动即可拖动；抬手放下。", value: $trackpadTapDragEnabled)
            }
            group("摆放方向") {
                row("鼠标摆放") {
                    Picker(l("鼠标摆放"), selection: $trackpadModeOrientation) {
                        Text(l("通常（先端が上）")).tag(0)
                        Text(l("横置き（先端が右）")).tag(1)
                        Text(l("横置き（先端が左）")).tag(2)
                    }.labelsHidden().frame(width: DS.Layout.settingsControlWidth)
                }.notifyOnChange(of: trackpadModeOrientation)
                if trackpadModeOrientation != 0 {
                    slider("横置光标横纵比例", detail: "轨迹偏瘦就调大，偏扁就调小。", value: $trackpadSidewaysAspectRatio, range: 0.5...3) { String(format: "%.2f", $0) }
                }
            }
            resetButton("恢复此页默认设置") { AppSettings.shared.resetTrackpadToDefaults() }
        }
    }

    private var mousePage: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            group("轻点点击") {
                toggle("单指轻点点击", value: $oneFingerTapEnabled)
                row("单指点击方式") {
                    Picker(l("单指点击方式"), selection: $tapAlwaysLeftClick) {
                        Text(l("按左右区域区分")).tag(false)
                        Text(l("始终执行左键")).tag(true)
                    }.labelsHidden().frame(width: DS.Layout.settingsControlWidth).disabled(!oneFingerTapEnabled)
                }.notifyOnChange(of: tapAlwaysLeftClick)
                if !tapAlwaysLeftClick { percent("右键区域起点", value: $rightZoneMinX) }
                toggle("2本指タップで左クリック", value: $twoFingerTapEnabled)
                toggle("2本指クリックでミドルクリック", value: $middleClickEnabled)
            }
            group("轻点响应范围") {
                slider("前端响应范围", detail: "从鼠标头部向后，只在此范围内识别轻点。", value: frontDepthBinding, range: 0.05...1) { String(format: "%.0f%%", $0 * 100) }
                caption("更细的触摸区域边界在高级与诊断中调整。")
            }
            resetButton("恢复此页默认设置") { AppSettings.shared.resetMouseToDefaults() }
        }
    }

    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            DisclosureGroup(l("轻点识别参数"), isExpanded: $transient.recognitionExpanded) {
                slider("タップの最長時間", value: $tapMaxDuration, range: 0.05...0.5) { String(format: l("%.2f秒"), $0) }
                slider("位置ズレの許容量", value: $tapMaxStraightDistance, range: 0.01...0.3) { String(format: "%.2f", $0) }
                slider("動きの合計の許容量", value: $tapMaxPathLength, range: 0.01...0.3) { String(format: "%.2f", $0) }
                slider("動きの速さの許容量", value: $tapMaxVelocity, range: 0.2...8) { String(format: "%.1f", $0) }
                slider("最短の接触フレーム数", value: tapMinFramesBinding, range: 1...10) { String(format: "%.0f", $0) }
                resetButton("恢复本组默认设置") { AppSettings.shared.resetSensitivityToDefaults() }
            }
            Divider()
            DisclosureGroup(l("誤反応の防止"), isExpanded: $transient.vetoExpanded) {
                slider("スクロール後の待ち時間", value: $scrollVetoWindow, range: 0...1) { String(format: l("%.2f秒"), $0) }
                slider("クリック後の待ち時間", value: $buttonVetoWindow, range: 0...0.5) { String(format: l("%.2f秒"), $0) }
                slider("2本指の同時判定時間", value: $twoFingerSyncWindow, range: 0.02...0.2) { String(format: l("%.2f秒"), $0) }
                resetButton("恢复本组默认设置") { AppSettings.shared.resetVetoToDefaults() }
            }
            Divider()
            DisclosureGroup(l("鼠标模式 · 触摸区域边界"), isExpanded: $transient.zoneExpanded) {
                percent("左右: 左端", value: leftBoundary)
                percent("左右: 右端", value: rightBoundary)
                percent("前後: 手前端", value: rearBoundary)
                percent("前後: 先端", value: frontBoundary)
                resetButton("恢复本组默认设置") { AppSettings.shared.resetZoneToDefaults() }
            }
            Divider()
            DisclosureGroup(l("系统指针速度增强"), isExpanded: $transient.speedExpanded) {
                slider("系统鼠标轨迹速度", detail: "影响系统鼠标速度；与手指控制光标的基础移动速度分开。", value: $pointerSpeedBoost, range: 0...9) { $0 <= 0 ? l("オフ") : String(format: "%.1f", $0) }
            }
            Divider()
            DisclosureGroup(l("诊断信息"), isExpanded: $transient.diagnosticsExpanded) {
                toggle("显示触点与轻点判定", value: diagnosticsBinding)
                if transient.showDiagnostics { debugContent.padding(.vertical, DS.Space.m) }
            }
        }.padding(.top, DS.Space.s)
    }

    private var debugContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text(String(format: NSLocalizedString("指の本数：%d", comment: "ライブ表示: 指の本数"), debugFeed.currentFingerCount))
                Spacer()
                Text(String(format: NSLocalizedString("左から%.0f%% 手前から%.0f%%", comment: "座標(%)"),
                            debugFeed.latestTouchX * 100, debugFeed.latestTouchY * 100))
            }
            .font(DS.Font.caption)
            .foregroundColor(DS.Color.labelSecondary)

            Divider()

            Text(NSLocalizedString("直近のイベント", comment: "ライブ表示見出し"))
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.labelSecondary)
            ForEach(debugFeed.recentEvents) { event in
                Text(event.text)
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.labelPrimary)
            }

            Divider()

            Text(NSLocalizedString("直近のタップ試行の判定内訳", comment: "ライブ表示見出し"))
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.labelSecondary)
            if debugFeed.lastAttempt.isEmpty {
                Text(NSLocalizedString("(まだ試行なし)", comment: "ライブ表示: 判定内訳が空のときの表示"))
                    .font(DS.Font.caption)
                    .foregroundColor(DS.Color.labelSecondary)
            } else {
                ForEach(debugFeed.lastAttempt) { condition in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.xs) {
                            Text(condition.passed ? "✓" : "✗")
                                .font(DS.Font.caption)
                                .foregroundColor(condition.passed ? DS.Color.debugPass : DS.Color.debugFail)
                            Text(condition.label)
                                .font(DS.Font.caption)
                                .foregroundColor(DS.Color.labelPrimary)
                        }
                        Text("\(condition.actual) / \(condition.threshold)")
                            .font(DS.Font.value)
                            .foregroundColor(DS.Color.labelSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

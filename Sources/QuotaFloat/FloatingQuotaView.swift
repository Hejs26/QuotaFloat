import AppKit
import SwiftUI

enum PanelMargins {
  static let right: CGFloat = 45
  static let left: CGFloat = right + 8
}

struct FloatingQuotaView: View {
  @ObservedObject var store: QuotaStore
  @ObservedObject var displayPreferences: DisplayPreferences
  @ObservedObject var contentPreferences: ContentPreferences
  @ObservedObject var credentialPreferences: ProviderCredentialPreferences
  @State private var isHovering = false
  @State private var isShowingManualRefreshFeedback = false

  var body: some View {
    GeometryReader { proxy in
      let designSize = self.contentPreferences.designSize
      let scale = min(
        proxy.size.width / designSize.width,
        proxy.size.height / designSize.height)

      self.design
        .frame(width: designSize.width, height: designSize.height)
        .scaleEffect(scale)
        .frame(width: proxy.size.width, height: proxy.size.height)
        .background {
          RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
            .inset(by: 0.5 * scale)
            .fill(Color.black.opacity(0.035))
        }
    }
  }

  private var design: some View {
    ZStack {
      if self.contentPreferences.isCollapsed {
        self.collapsedBrand
      } else {
        self.providerContent

        self.controls
          .frame(width: 32)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 13)
          .opacity(self.isHovering ? 1 : 0)
          .allowsHitTesting(self.isHovering)
      }
    }
    .frame(
      width: self.contentPreferences.designSize.width,
      height: self.contentPreferences.designSize.height
    )
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .contextMenu {
      if self.contentPreferences.isCollapsed {
        Button {
          self.displayPreferences.selectAlwaysDisplay()
          self.contentPreferences.expandAll()
        } label: {
          Label("全局显示", systemImage: "globe")
        }

        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Label("退出", systemImage: "power")
        }
      } else {
        self.expandedContextMenu
      }
    }
    .onHover { self.isHovering = $0 }
    .animation(.easeOut(duration: 0.14), value: self.isHovering)
  }

  private var collapsedBrand: some View {
    HStack(spacing: 7) {
      ZStack {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.42, green: 0.31, blue: 0.96),
                Color(red: 0.96, green: 0.39, blue: 0.24),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing))

        Text("QF")
          .font(.system(size: 9, weight: .black, design: .rounded))
          .tracking(-0.5)
          .foregroundStyle(.white)
      }
      .frame(width: 24, height: 24)

      Text("Quota Float")
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.black.opacity(0.72))
        .fixedSize()
    }
  }

  @ViewBuilder
  private var expandedContextMenu: some View {
    Section("显示位置") {
      Button {
        self.displayPreferences.toggleApp("com.openai.codex")
      } label: {
        Label(
          "仅在 Codex 中显示",
          systemImage: self.displayPreferences.isEnabled("com.openai.codex") ? "checkmark" : "")
      }

      Button {
        self.displayPreferences.toggleApp("com.anthropic.claudefordesktop")
      } label: {
        Label(
          "仅在 Claude 中显示",
          systemImage: self.displayPreferences.isEnabled("com.anthropic.claudefordesktop")
            ? "checkmark" : "")
      }

      Button {
        self.displayPreferences.toggleTerminals()
      } label: {
        Label(
          "仅在 Terminal / iTerm 中显示",
          systemImage: self.displayPreferences.terminalsEnabled ? "checkmark" : "")
      }

      Button {
        self.displayPreferences.selectAlwaysDisplay()
      } label: {
        Label(
          "始终显示",
          systemImage: self.displayPreferences.alwaysDisplay ? "checkmark" : "")
      }
    }

    Section("显示内容") {
      Button {
        self.contentPreferences.selectAll()
      } label: {
        Label(
          "全部显示",
          systemImage: self.contentPreferences.selectedProviders
            == Set(QuotaProviderCatalog.orderedProviders) ? "checkmark" : "")
      }

      ForEach(QuotaProviderCatalog.orderedProviders) { provider in
        Button {
          self.toggleProvider(provider)
        } label: {
          Label(
            provider.displayName,
            systemImage: self.contentPreferences.selectedProviders.contains(provider)
              ? "checkmark" : "")
        }
      }
    }

    Section("服务设置") {
      Button {
        if self.credentialPreferences.promptForKimiAPIKey() {
          if !self.contentPreferences.selectedProviders.contains(.kimi) {
            self.contentPreferences.toggle(.kimi)
          } else {
            self.store.refresh()
          }
        }
      } label: {
        Label(
          self.credentialPreferences.hasKimiAPIKey
            ? "更新 Kimi API Key…" : "设置 Kimi API Key…",
          systemImage: "key")
      }

      if self.credentialPreferences.hasKimiAPIKey {
        Button {
          if self.credentialPreferences.confirmAndClearKimiAPIKey() {
            self.store.refresh()
          }
        } label: {
          Label("清除 Kimi API Key", systemImage: "trash")
        }
      }
    }
  }

  private func toggleProvider(_ provider: QuotaProvider) {
    let isEnabling = !self.contentPreferences.selectedProviders.contains(provider)
    if isEnabling,
      provider.definition.credential == .kimiCodingPlanAPIKey,
      !self.credentialPreferences.hasKimiAPIKey,
      !self.credentialPreferences.promptForKimiAPIKey()
    {
      return
    }
    self.contentPreferences.toggle(provider)
  }

  private var providerContent: some View {
    self.providerContentForMode
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.trailing, PanelMargins.right)
  }

  @ViewBuilder
  private var providerContentForMode: some View {
    let providers = self.contentPreferences.orderedSelectedProviders
    if providers.count == 1, let provider = providers.first {
      self.singleProviderContent(provider)
    } else {
      HStack(spacing: 14) {
        ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
          if index > 0 {
            Rectangle()
              .fill(Color.black.opacity(0.08))
              .frame(width: 1, height: 21)
          }

          self.multiProviderContent(provider)
        }
      }
    }
  }

  @ViewBuilder
  private func multiProviderContent(_ provider: QuotaProvider) -> some View {
    let snapshot = self.store.snapshot(for: provider)
    if self.contentPreferences.multiResetPinned {
      HStack(spacing: 14) {
        ProviderStrip(
          provider: provider,
          snapshot: snapshot,
          showsResetOnHover: false,
          onPinReset: nil)

        ResetHoverSummary(
          session: snapshot?.session,
          weekly: snapshot?.weekly,
          width: 110,
          onHide: {
            self.contentPreferences.setMultiResetPinned(false)
          })
      }
    } else {
      ProviderStrip(
        provider: provider,
        snapshot: snapshot,
        showsResetOnHover: true,
        onPinReset: {
          self.contentPreferences.setMultiResetPinned(true)
        })
    }
  }

  @ViewBuilder
  private func singleProviderContent(_ provider: QuotaProvider) -> some View {
    let snapshot = self.store.snapshot(for: provider)
    if self.contentPreferences.singleResetPinned {
      HStack(spacing: 14) {
        ProviderStrip(
          provider: provider,
          snapshot: snapshot,
          showsResetOnHover: false,
          onPinReset: nil)

        ResetHoverSummary(
          session: snapshot?.session,
          weekly: snapshot?.weekly,
          width: 110,
          onHide: {
            self.contentPreferences.setSingleResetPinned(false)
          })
      }
    } else {
      ProviderStrip(
        provider: provider,
        snapshot: snapshot,
        showsResetOnHover: true,
        onPinReset: {
          self.contentPreferences.setSingleResetPinned(true)
        })
    }
  }

  private var controls: some View {
    HStack(spacing: 1) {
      Button {
        self.contentPreferences.collapse()
      } label: {
        Image(systemName: "xmark")
      }
      .help("收起")

      Button {
        self.isShowingManualRefreshFeedback = true
        self.store.refresh()
        Task {
          try? await Task.sleep(for: .milliseconds(700))
          await MainActor.run {
            self.isShowingManualRefreshFeedback = false
          }
        }
      } label: {
        Image(systemName: "arrow.clockwise")
          .rotationEffect(
            self.store.isRefreshing || self.isShowingManualRefreshFeedback
              ? .degrees(360) : .zero)
          .animation(
            self.store.isRefreshing || self.isShowingManualRefreshFeedback
              ? .linear(duration: 0.9).repeatForever(autoreverses: false)
              : .default,
            value: self.store.isRefreshing || self.isShowingManualRefreshFeedback)
      }
      .disabled(self.store.isRefreshing || self.isShowingManualRefreshFeedback)
      .help("立即刷新")
    }
    .buttonStyle(StripButtonStyle())
  }
}

private struct ProviderStrip: View {
  let provider: QuotaProvider
  let snapshot: QuotaSnapshot?
  let showsResetOnHover: Bool
  let onPinReset: (() -> Void)?
  @State private var isHoveringMetrics = false
  @State private var isHoveringIcon = false

  var body: some View {
    HStack(spacing: 9) {
      ProviderMark(
        provider: self.provider,
        resetCredits: self.snapshot?.resetCredits,
        onHover: { hovering in
          self.isHoveringIcon = hovering
        })

      Group {
        if self.isHoveringIcon,
          self.provider == .codex,
          let resetCredits = self.snapshot?.resetCredits
        {
          ResetCreditsHoverSummary(
            resetCredits: resetCredits,
            width: 191)
          .transition(.opacity)
        } else if self.showsResetOnHover && self.isHoveringMetrics {
          ResetHoverSummary(
            session: self.snapshot?.session,
            weekly: self.snapshot?.weekly,
            width: 191,
            onPin: self.onPinReset
          )
          .transition(.opacity)
        } else {
          HStack(spacing: 9) {
            CompactMetric(label: "5h", window: self.snapshot?.session, color: self.color)
            CompactMetric(label: "周", window: self.snapshot?.weekly, color: self.color)
          }
          .help(self.helpText)
          .transition(.opacity)
        }
      }
      .frame(width: 191, alignment: .leading)
      .contentShape(Rectangle())
      .onHover { self.isHoveringMetrics = $0 }
    }
    .frame(width: 224)
    .opacity(self.contentOpacity)
    .animation(.easeOut(duration: 0.12), value: self.isHoveringMetrics)
    .animation(.easeOut(duration: 0.12), value: self.isHoveringIcon)
  }

  private var color: Color {
    let color = self.provider.definition.color
    return Color(red: color.red, green: color.green, blue: color.blue)
  }

  private var contentOpacity: Double {
    switch self.snapshot?.freshness {
    case .stale, .authRequired, .unavailable: 0.55
    default: 1
    }
  }

  private var helpText: String {
    guard let snapshot else {
      return "\(self.provider.displayName)：等待首次同步"
    }

    var lines = [
      self.provider.displayName,
      "5h：\(self.metricText(snapshot.session))，\(ResetTimeFormatter.string(snapshot.session, now: Date()))",
      "周额度：\(self.metricText(snapshot.weekly))，\(ResetTimeFormatter.string(snapshot.weekly, now: Date()))",
      "来源：\(snapshot.source)",
      "更新：\(RelativeTimeFormatter.string(from: snapshot.updatedAt, to: Date()))",
    ]
    if let message = snapshot.message {
      lines.append(message)
    }
    if self.provider == .codex,
      let resetCredits = snapshot.resetCredits,
      resetCredits.availableCount > 0
    {
      lines.append(ResetCreditFormatter.helpText(resetCredits, now: Date()))
    }
    return lines.joined(separator: "\n")
  }

  private func metricText(_ window: QuotaWindow?) -> String {
    guard let window else { return "暂不可用" }
    return "剩余 \(Int(window.remainingPercent.rounded()))%"
  }
}

private struct ResetCreditsHoverSummary: View {
  let resetCredits: QuotaResetCredits
  let width: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 14) {
        Text("重置卡")
          .foregroundStyle(Color(red: 0.65, green: 0.64, blue: 0.60))
        Text("\(self.resetCredits.availableCount)张可用")
          .foregroundStyle(Color(red: 0.27, green: 0.26, blue: 0.24))
      }

      Text(ResetCreditFormatter.expirationSummary(self.resetCredits, now: Date()))
        .foregroundStyle(Color(red: 0.48, green: 0.47, blue: 0.44))
    }
    .font(.system(size: 9, weight: .medium, design: .monospaced))
    .lineLimit(1)
    .frame(width: self.width, alignment: .leading)
  }
}

private struct ResetHoverSummary: View {
  let session: QuotaWindow?
  let weekly: QuotaWindow?
  let width: CGFloat
  var onHide: (() -> Void)? = nil
  var onPin: (() -> Void)? = nil
  @State private var isHovering = false

  var body: some View {
    ZStack {
      HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          self.row(label: "5h", window: self.session)
          self.row(label: "周", window: self.weekly)
        }

        if let onPin {
          Button(action: onPin) {
            HStack(spacing: 4) {
              PinOutlineIcon()
                .frame(width: 8, height: 8)
              Text("常驻显示")
                .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.42, green: 0.40, blue: 0.38))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
              Color.white.opacity(0.9),
              in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.14), lineWidth: 0.8)
            }
          }
          .buttonStyle(.plain)
          .help("常驻显示重置时间")
        }
      }
      .opacity(self.isHovering && self.onHide != nil ? 0.2 : 1)

      if let onHide, self.isHovering {
        Button(action: onHide) {
          Image(systemName: "eye.slash")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.55))
            .frame(width: 18, height: 18)
            .background(Color.black.opacity(0.055), in: Circle())
        }
        .buttonStyle(.plain)
        .help("隐藏常驻重置时间")
      }
    }
    .frame(width: self.width, alignment: .leading)
    .contentShape(Rectangle())
    .onHover { self.isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: self.isHovering)
  }

  private func row(label: String, window: QuotaWindow?) -> some View {
    let now = Date()
    let evaluation = window?.paceEvaluation(now: now)

    return HStack(spacing: 0) {
      Text(label)
        .foregroundStyle(Color(red: 0.65, green: 0.64, blue: 0.60))
        .frame(width: 16, alignment: .trailing)

      Spacer().frame(width: 7)

      ResetLoopIcon()
        .foregroundStyle(Color(red: 0.48, green: 0.48, blue: 0.46))
        .frame(width: 10)

      Spacer().frame(width: 7)

      Text(ResetTimeFormatter.paceString(window, now: now))
        .foregroundStyle(Color(red: 0.27, green: 0.26, blue: 0.24))
        .frame(width: 36, alignment: .leading)

      Spacer().frame(width: 10)

      Text(evaluation?.status.rawValue ?? "")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Self.statusColor(evaluation?.status))
        .frame(width: 22, alignment: .leading)
        .help(Self.paceHelp(window: window, evaluation: evaluation))
    }
    .font(.system(size: 9, weight: .medium, design: .monospaced))
    .lineLimit(1)
  }

  private static func statusColor(_ status: QuotaPaceStatus?) -> Color {
    switch status {
    case .roomy:
      Color(red: 105 / 255, green: 168 / 255, blue: 117 / 255)
    case .normal:
      Color(red: 91 / 255, green: 130 / 255, blue: 201 / 255)
    case .fast:
      Color(red: 201 / 255, green: 90 / 255, blue: 46 / 255)
    case .urgent, .exhausted:
      Color(red: 217 / 255, green: 74 / 255, blue: 74 / 255)
    case nil:
      .clear
    }
  }

  private static func paceHelp(
    window: QuotaWindow?,
    evaluation: QuotaPaceEvaluation?
  ) -> String {
    guard let window, let evaluation else { return "缺少重置时间，暂时无法评价节奏" }
    if evaluation.status == .exhausted { return "实际剩余 0%，额度已耗尽" }
    let actual = Int(window.remainingPercent.rounded())
    let ideal = Int(evaluation.idealRemainingPercent.rounded())
    let delta = Int(evaluation.deltaPercent.rounded())
    let sign = delta >= 0 ? "+" : ""
    return "实际剩余 \(actual)%，理想剩余 \(ideal)%，余量差 \(sign)\(delta)%"
  }
}

private struct PinOutlineIcon: View {
  var body: some View {
    Canvas { context, size in
      let scaleX = size.width / 24
      let scaleY = size.height / 24
      func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * scaleX, y: y * scaleY)
      }

      var pin = Path()
      pin.move(to: point(9, 4))
      pin.addLine(to: point(15, 4))
      pin.addLine(to: point(14, 10))
      pin.addLine(to: point(17, 13))
      pin.addLine(to: point(17, 14.5))
      pin.addLine(to: point(7, 14.5))
      pin.addLine(to: point(7, 13))
      pin.addLine(to: point(10, 10))
      pin.closeSubpath()
      pin.move(to: point(12, 17.5))
      pin.addLine(to: point(12, 21))

      context.stroke(
        pin,
        with: .foreground,
        style: StrokeStyle(
          lineWidth: 1.8 * min(scaleX, scaleY),
          lineCap: .round,
          lineJoin: .round))
    }
  }
}

private struct ResetLoopIcon: View {
  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = min(size.width, size.height) * 0.39
      let arrowAngle = Angle.degrees(189)
      var path = Path()
      path.addArc(
        center: center,
        radius: radius,
        startAngle: .degrees(24),
        endAngle: .degrees(354),
        clockwise: false)
      context.stroke(
        path,
        with: .foreground,
        style: StrokeStyle(lineWidth: 1.25, lineCap: .round))

      let tip = CGPoint(
        x: center.x + cos(arrowAngle.radians) * radius,
        y: center.y + sin(arrowAngle.radians) * radius)
      let tangent = CGVector(
        dx: -sin(arrowAngle.radians),
        dy: cos(arrowAngle.radians))
      let radial = CGVector(
        dx: cos(arrowAngle.radians),
        dy: sin(arrowAngle.radians))
      let wingLength = min(size.width, size.height) * 0.19
      let wingSpread = min(size.width, size.height) * 0.13
      var arrow = Path()
      arrow.move(to: CGPoint(
        x: tip.x - tangent.dx * wingLength + radial.dx * wingSpread,
        y: tip.y - tangent.dy * wingLength + radial.dy * wingSpread))
      arrow.addLine(to: tip)
      arrow.addLine(to: CGPoint(
        x: tip.x - tangent.dx * wingLength - radial.dx * wingSpread,
        y: tip.y - tangent.dy * wingLength - radial.dy * wingSpread))
      context.stroke(
        arrow,
        with: .foreground,
        style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
    }
    .frame(width: 10, height: 10)
  }
}

private struct CompactMetric: View {
  let label: String
  let window: QuotaWindow?
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      Text(self.label)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(Color(red: 0.65, green: 0.64, blue: 0.60))
        .frame(width: 16, alignment: .trailing)
        .fixedSize()

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.black.opacity(0.075))
          Capsule()
            .fill(self.color)
            .frame(width: proxy.size.width * self.remainingPercent / 100)
        }
      }
      .frame(width: 34, height: 5)

      Text(self.percentText)
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color(red: 0.27, green: 0.26, blue: 0.24))
        .frame(width: 31, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .allowsTightening(true)
    }
    .frame(width: 91)
  }

  private var remainingPercent: Double {
    self.window?.remainingPercent ?? 0
  }

  private var percentText: String {
    guard let window else { return "--" }
    return "\(Int(window.remainingPercent.rounded()))%"
  }
}

private struct ProviderMark: View {
  let provider: QuotaProvider
  let resetCredits: QuotaResetCredits?
  let onHover: (Bool) -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Group {
        switch self.provider.definition.icon {
        case .codex:
          CodexMark()
        case .claude:
          ClaudeMark()
        case .kimi:
          KimiMark()
        }
      }
      .frame(width: 24, height: 24)

      if self.provider == .codex,
        let resetCredits,
        resetCredits.availableCount > 0
      {
        Text("\(resetCredits.availableCount)")
          .font(.system(size: 5, weight: .bold, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.92))
          .padding(.horizontal, 1.5)
          .frame(minWidth: 7, minHeight: 7)
          .background(Color(red: 0.52, green: 0.47, blue: 0.86).opacity(0.78), in: Capsule())
          .overlay {
            Capsule()
              .stroke(Color.white.opacity(0.9), lineWidth: 0.6)
          }
          .offset(x: 2.5, y: -2.5)
      }
    }
    .frame(width: 24, height: 24)
    .contentShape(Rectangle())
    .onHover(perform: self.onHover)
  }
}

private struct CodexMark: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(Color.white)
      .overlay {
        Canvas { context, size in
          let scale = 18.0 / 23.4
          let origin = CGPoint(
            x: (size.width - 18) / 2,
            y: (size.height - 18) / 2)
          func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
              x: origin.x + (x - 5.3) * scale,
              y: origin.y + (y - 5.3) * scale)
          }
          let centers = [
            CGPoint(x: 17, y: 17),
            CGPoint(x: 23.3, y: 17),
            CGPoint(x: 20.2, y: 22.5),
            CGPoint(x: 13.8, y: 22.5),
            CGPoint(x: 10.7, y: 17),
            CGPoint(x: 13.8, y: 11.5),
            CGPoint(x: 20.2, y: 11.5),
          ]
          let gradient = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [
              Color(red: 0.63, green: 0.69, blue: 1),
              Color(red: 0.43, green: 0.36, blue: 0.94),
              Color(red: 0.31, green: 0.19, blue: 0.78),
            ]),
            startPoint: point(7, 7),
            endPoint: point(28, 28))

          for center in centers {
            let rect = CGRect(
              x: point(center.x - 5.4, center.y - 5.4).x,
              y: point(center.x - 5.4, center.y - 5.4).y,
              width: 10.8 * scale,
              height: 10.8 * scale)
            context.fill(Path(ellipseIn: rect), with: gradient)
          }

          var prompt = Path()
          prompt.move(to: point(12.5, 14))
          prompt.addLine(to: point(14.6, 17))
          prompt.addLine(to: point(12.5, 20))
          context.stroke(
            prompt,
            with: .color(.white),
            style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))

          var dash = Path()
          dash.move(to: point(18.5, 18.8))
          dash.addLine(to: point(22.2, 18.8))
          context.stroke(
            dash,
            with: .color(.white),
            style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(Color.black.opacity(0.06), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
  }
}

private struct ClaudeMark: View {
  var body: some View {
    Image(nsImage: Self.image)
      .resizable()
      .interpolation(.high)
      .antialiased(true)
      .aspectRatio(contentMode: .fit)
  }

  private static let image: NSImage = {
    guard let url = Bundle.module.url(forResource: "claude-mark", withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(size: NSSize(width: 24, height: 24))
    }
    return image
  }()
}

private struct KimiMark: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(Color.white)
      .overlay {
        Image(nsImage: Self.image)
          .resizable()
          .renderingMode(.template)
          .foregroundStyle(Color.black.opacity(0.82))
          .aspectRatio(contentMode: .fit)
          .padding(4)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(Color.black.opacity(0.06), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
  }

  private static let image: NSImage = {
    guard let url = Bundle.module.url(forResource: "kimi-mark", withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(size: NSSize(width: 24, height: 24))
    }
    image.isTemplate = true
    return image
  }()
}

private struct StripButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 8, weight: .semibold))
      .foregroundStyle(Color.black.opacity(0.48))
      .frame(width: 13, height: 13)
      .background(Color.black.opacity(configuration.isPressed ? 0.09 : 0.035), in: Circle())
      .frame(width: 15.5, height: 20)
      .contentShape(Rectangle())
  }
}

enum RelativeTimeFormatter {
  static func string(from date: Date, to now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 5 { return "刚刚" }
    if seconds < 60 { return "\(seconds) 秒前" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes) 分钟前" }
    return "\(minutes / 60) 小时前"
  }
}

enum ResetTimeFormatter {
  static func paceString(_ window: QuotaWindow?, now: Date) -> String {
    guard let window else { return "--" }
    guard let date = window.resetsAt else {
      return window.usedPercent <= 0.5 ? "使用后" : "--"
    }
    let seconds = Int(date.timeIntervalSince(now))
    guard seconds > 0 else { return "刷新中" }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)天\(hours)h" }
    if hours > 0 { return "\(hours)h\(minutes)m" }
    return "\(max(1, minutes))m"
  }

  static func compactString(_ window: QuotaWindow?, now: Date) -> String {
    guard let window else { return "重置时间未知" }
    guard let date = window.resetsAt else {
      return window.usedPercent <= 0.5 ? "使用后开始计时" : "重置时间未知"
    }
    let seconds = Int(date.timeIntervalSince(now))
    guard seconds > 0 else { return "等待刷新" }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)天\(hours)小时后重置" }
    if hours > 0 { return "\(hours)小时\(minutes)分后重置" }
    return "\(max(1, minutes))分钟后重置"
  }

  static func string(_ window: QuotaWindow?, now: Date) -> String {
    guard let window else { return "重置时间未知" }
    guard let date = window.resetsAt else {
      return window.usedPercent <= 0.5 ? "使用后开始计时" : "重置时间未知"
    }
    let seconds = Int(date.timeIntervalSince(now))
    guard seconds > 0 else { return "等待刷新" }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)天\(hours)小时后重置" }
    if hours > 0 { return "\(hours)小时\(minutes)分后重置" }
    return "\(max(1, minutes))分钟后重置"
  }
}

enum ResetCreditFormatter {
  static func helpText(_ credits: QuotaResetCredits, now: Date) -> String {
    let countText = "\(credits.availableCount) 张可用重置卡"
    guard let expiration = credits.nextExpirationDate else {
      return "\(countText)\n接口未提供可用重置卡的过期时间"
    }
    return "\(countText)\n最近一张 \(self.expirationText(expiration, now: now))过期"
  }

  static func expirationSummary(_ credits: QuotaResetCredits, now: Date) -> String {
    guard let expiration = credits.nextExpirationDate else {
      return credits.availableCount > 0 ? "过期时间未知" : "暂无可用重置卡"
    }
    return "最近一张 \(self.expirationText(expiration, now: now))过期"
  }

  private static func expirationText(_ expiration: Date, now: Date) -> String {
    let seconds = max(0, Int(expiration.timeIntervalSince(now)))
    if seconds < 60 { return "即将" }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)天\(hours)小时后" }
    if hours > 0 { return "\(hours)小时\(minutes)分钟后" }
    return "\(max(1, minutes))分钟后"
  }
}

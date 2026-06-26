import AppKit
import ApplicationServices
import CodexBarCore
import Combine
import CoreGraphics
import Darwin
import SwiftUI

@MainActor
final class DisplayPreferences: ObservableObject {
  private static let configurationVersion = 2
  private static let configurationVersionKey = "QuotaFloatDisplayConfigurationVersion"
  private static let legacyStorageKey = "QuotaFloatDisplayMode"
  private static let alwaysStorageKey = "QuotaFloatAlwaysDisplay"
  private static let selectedAppsStorageKey = "QuotaFloatSelectedApps"

  @Published private(set) var alwaysDisplay: Bool
  @Published private(set) var selectedApps: Set<String>
  static let terminalBundleIdentifiers: Set<String> = [
    "com.googlecode.iterm2",
    "com.apple.Terminal",
  ]

  init() {
    let defaults = UserDefaults.standard
    if defaults.integer(forKey: Self.configurationVersionKey) < Self.configurationVersion {
      self.alwaysDisplay = true
      self.selectedApps = []
      self.save()
    } else if defaults.object(forKey: Self.alwaysStorageKey) != nil {
      self.alwaysDisplay = defaults.bool(forKey: Self.alwaysStorageKey)
      self.selectedApps = Set(
        defaults.stringArray(forKey: Self.selectedAppsStorageKey) ?? [])
    } else {
      let legacyValue = defaults.string(forKey: Self.legacyStorageKey)
      let shouldAlwaysDisplay = legacyValue == nil || legacyValue == "always"
      self.alwaysDisplay = shouldAlwaysDisplay
      self.selectedApps =
        shouldAlwaysDisplay
        ? []
        : ["com.openai.codex", "com.anthropic.claudefordesktop"]
      self.save()
    }
  }

  func isEnabled(_ bundleIdentifier: String) -> Bool {
    self.selectedApps.contains(bundleIdentifier)
  }

  func toggleApp(_ bundleIdentifier: String) {
    self.alwaysDisplay = false
    if self.selectedApps.contains(bundleIdentifier) {
      self.selectedApps.remove(bundleIdentifier)
    } else {
      self.selectedApps.insert(bundleIdentifier)
    }
    self.save()
  }

  var terminalsEnabled: Bool {
    Self.terminalBundleIdentifiers.isSubset(of: self.selectedApps)
  }

  func toggleTerminals() {
    self.alwaysDisplay = false
    if self.terminalsEnabled {
      self.selectedApps.subtract(Self.terminalBundleIdentifiers)
    } else {
      self.selectedApps.formUnion(Self.terminalBundleIdentifiers)
    }
    self.save()
  }

  func selectAlwaysDisplay() {
    self.alwaysDisplay = true
    self.selectedApps.removeAll()
    self.save()
  }

  private func save() {
    let defaults = UserDefaults.standard
    defaults.set(Self.configurationVersion, forKey: Self.configurationVersionKey)
    defaults.set(self.alwaysDisplay, forKey: Self.alwaysStorageKey)
    defaults.set(Array(self.selectedApps).sorted(), forKey: Self.selectedAppsStorageKey)
  }
}

@MainActor
final class ContentPreferences: ObservableObject {
  @Published private(set) var selectedProviders = Set(QuotaProviderCatalog.orderedProviders)
  @Published private(set) var singleResetPinned = true
  @Published private(set) var multiResetPinned = false
  @Published private(set) var isCollapsed = false

  private static let providerStripWidth: CGFloat = 224
  private static let providerSeparatorWidth: CGFloat = 29
  private static let pinnedResetWidth: CGFloat = 110
  private static let collapsedWidth: CGFloat = 126

  var designSize: NSSize {
    if self.isCollapsed {
      return NSSize(width: Self.collapsedWidth, height: 40)
    }

    let providerCount = max(1, self.selectedProviders.count)
    let providerWidth = Self.providerStripWidth
      + ((providerCount == 1 ? self.singleResetPinned : self.multiResetPinned)
        ? 14 + Self.pinnedResetWidth
        : 0)
    let contentWidth: CGFloat = if providerCount == 1 {
      providerWidth
    } else {
      CGFloat(providerCount) * providerWidth
        + CGFloat(providerCount - 1) * Self.providerSeparatorWidth
    }
    return NSSize(
      width: contentWidth + PanelMargins.left + PanelMargins.right,
      height: 40)
  }

  private static let minimumSizeScale: CGFloat = 0.8

  var minimumSize: NSSize {
    let designSize = self.designSize
    return NSSize(
      width: designSize.width * Self.minimumSizeScale,
      height: designSize.height * Self.minimumSizeScale)
  }

  var activeProviders: Set<QuotaProvider> {
    self.isCollapsed ? [] : self.selectedProviders
  }

  var orderedSelectedProviders: [QuotaProvider] {
    QuotaProviderCatalog.orderedProviders.filter(self.selectedProviders.contains)
  }

  var selectionKey: String {
    if self.selectedProviders == Set(QuotaProviderCatalog.orderedProviders) { return "all" }
    return self.orderedSelectedProviders.map(\.rawValue).joined(separator: "+")
  }

  func setSelectedProviders(_ providers: Set<QuotaProvider>) {
    let available = providers.intersection(Set(QuotaProviderCatalog.orderedProviders))
    self.selectedProviders = available.isEmpty ? [QuotaProviderCatalog.orderedProviders[0]] : available
  }

  func selectAll() {
    self.selectedProviders = Set(QuotaProviderCatalog.orderedProviders)
  }

  func toggle(_ provider: QuotaProvider) {
    if self.selectedProviders.contains(provider) {
      guard self.selectedProviders.count > 1 else { return }
      self.selectedProviders.remove(provider)
    } else {
      self.selectedProviders.insert(provider)
    }
  }

  func collapse() {
    self.isCollapsed = true
  }

  func expandAll() {
    self.selectAll()
    self.isCollapsed = false
  }

  func setSingleResetPinned(_ pinned: Bool) {
    self.singleResetPinned = pinned
  }

  func setMultiResetPinned(_ pinned: Bool) {
    self.multiResetPinned = pinned
  }
}

@MainActor
final class WindowAttachmentState: ObservableObject {
  @Published fileprivate(set) var isAttached = false
  @Published fileprivate(set) var canAttachToFrontmostWindow = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private static let supportedBundleIdentifiers = [
    "com.openai.codex",
    "com.anthropic.claudefordesktop",
    "com.googlecode.iterm2",
    "com.apple.Terminal",
  ]

  private let credentialPreferences = ProviderCredentialPreferences()
  private lazy var store = QuotaStore(
    fetcher: CodexBarQuotaFetcher(
      kimiAPIKeyStore: self.credentialPreferences.kimiAPIKeyStore))
  private let displayPreferences = DisplayPreferences()
  private let contentPreferences = ContentPreferences()
  private let attachmentState = WindowAttachmentState()
  private var panel: NSPanel?
  private var displayModeObserver: AnyCancellable?
  private var contentModeObserver: AnyCancellable?
  private var workspaceObserver: NSObjectProtocol?
  private var visibilityTimer: Timer?
  private var attachmentTimer: Timer?
  private var attachmentObserver: AXObserver?
  private var attachmentObserverSource: CFRunLoopSource?
  private var activeBundleIdentifier: String?
  private var activeAppHasVisibleWindow = false
  private var isRestoringFrame = false
  private var isFollowingAttachedWindow = false
  private var hasRequestedAccessibilityPermissionThisSession = false
  private var attachedWindow: AttachedWindow?
  private var currentContentDesignSize: NSSize?

  func applicationDidFinishLaunching(_ notification: Notification) {
    _ = notification
    KeychainAccessGate.forceDisabledForProcess(
      reason: "QuotaFloat uses file-based credentials and CLI fallback")

    if CommandLine.arguments.contains("--self-test") {
      do {
        try QuotaFloatSelfTest.run()
        print("QuotaFloat self-test passed.")
        exit(EXIT_SUCCESS)
      } catch {
        FileHandle.standardError.write(Data("QuotaFloat self-test failed: \(error)\n".utf8))
        exit(EXIT_FAILURE)
      }
    }

    NSApplication.shared.setActivationPolicy(.accessory)

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 567, height: 40),
      styleMask: [.borderless, .resizable, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    panel.title = "QuotaFloat"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentAspectRatio = self.contentPreferences.designSize
    panel.contentMinSize = self.contentPreferences.minimumSize
    panel.minSize = self.contentPreferences.minimumSize
    panel.contentMaxSize = NSSize(width: 5670, height: 400)
    panel.maxSize = NSSize(width: 5670, height: 400)
    panel.delegate = self
    panel.contentView = NSHostingView(
      rootView: FloatingQuotaView(
        store: self.store,
        displayPreferences: self.displayPreferences,
        contentPreferences: self.contentPreferences,
        credentialPreferences: self.credentialPreferences,
        attachmentState: self.attachmentState,
        onToggleWindowAttachment: { [weak self] in
          self?.toggleWindowAttachment()
        }))
    panel.setFrameAutosaveName("QuotaFloatProportional557")

    if !panel.setFrameUsingName("QuotaFloatProportional557") {
      self.positionAtTopRight(panel)
    }
    self.enforceAllowedSize(panel)
    self.currentContentDesignSize = self.contentPreferences.designSize

    self.panel = panel
    self.startApplicationVisibilityTracking()
    self.updatePanelVisibility()
    self.store.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    _ = notification
    if let workspaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
    }
    self.visibilityTimer?.invalidate()
    self.saveAttachmentForActiveContext()
    self.clearAttachmentRuntime(savePreference: false)
    self.displayModeObserver?.cancel()
    self.contentModeObserver?.cancel()
    self.store.stop()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    _ = sender
    self.detachWindow(savePreference: true)
    self.contentPreferences.collapse()
    return false
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    if self.attachedWindow != nil {
      return sender.frame.size
    }
    let designSize = self.contentPreferences.designSize
    let minimumWidth = self.contentPreferences.minimumSize.width
    let maximumWidth = designSize.width * 10
    let aspectRatio = designSize.width / designSize.height
    let width = min(max(frameSize.width, minimumWidth), maximumWidth)
    return NSSize(width: width, height: width / aspectRatio)
  }

  func windowDidResize(_ notification: Notification) {
    guard let panel = notification.object as? NSPanel else { return }
    self.enforceAllowedSize(panel)
    self.saveFrameForActiveApp()
  }

  func windowDidMove(_ notification: Notification) {
    guard notification.object is NSPanel else { return }
    if self.attachedWindow == nil {
      self.saveFrameForActiveApp()
    } else if !self.isFollowingAttachedWindow {
      self.refreshAttachmentOffset()
    }
  }

  private func positionAtTopRight(_ panel: NSPanel) {
    guard let frame = NSScreen.main?.visibleFrame else {
      panel.center()
      return
    }
    let origin = NSPoint(
      x: frame.maxX - panel.frame.width - 24,
      y: frame.maxY - panel.frame.height - 24)
    panel.setFrameOrigin(origin)
  }

  private func enforceAllowedSize(_ panel: NSPanel) {
    let designSize = self.contentPreferences.designSize
    let width = max(panel.frame.width, self.contentPreferences.minimumSize.width)
    let correctedSize = NSSize(
      width: width,
      height: width / (designSize.width / designSize.height))
    guard
      abs(panel.frame.width - correctedSize.width) > 0.5
        || abs(panel.frame.height - correctedSize.height) > 0.5
    else {
      return
    }
    panel.setContentSize(correctedSize)
  }

  private func startApplicationVisibilityTracking() {
    self.refreshActiveApplication()

    self.workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let application =
          notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      else {
        return
      }

      Task { @MainActor [weak self] in
        guard let self else { return }
        if application.bundleIdentifier == Bundle.main.bundleIdentifier {
          return
        }
        self.handleActivatedApplication(application)
        self.updateVisibilityPolling()
        self.refreshAttachability()
        self.updatePanelVisibility()
      }
    }

    self.displayModeObserver = Publishers.CombineLatest(
      self.displayPreferences.$alwaysDisplay,
      self.displayPreferences.$selectedApps
    )
    .removeDuplicates { previous, current in
      previous.0 == current.0 && previous.1 == current.1
    }
    .sink { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.handleActivatedApplication(NSWorkspace.shared.frontmostApplication)
        self.updateVisibilityPolling()
        self.refreshAttachability()
        self.updatePanelVisibility()
      }
    }

    self.contentModeObserver = Publishers.CombineLatest4(
      self.contentPreferences.$selectedProviders,
      self.contentPreferences.$singleResetPinned,
      self.contentPreferences.$multiResetPinned,
      self.contentPreferences.$isCollapsed
    )
    .removeDuplicates { previous, current in
      previous.0 == current.0
        && previous.1 == current.1
        && previous.2 == current.2
        && previous.3 == current.3
    }
    .dropFirst()
    .sink { [weak self] _ in
      guard let self, !self.isRestoringFrame else { return }
      Task { @MainActor [weak self] in
        self?.contentConfigurationDidChange()
      }
    }

    self.updateVisibilityPolling()
    self.refreshAttachability()
  }

  private func updatePanelVisibility() {
    guard let panel else { return }
    if self.attachedWindow != nil, !self.attachedWindowIsVisible {
      panel.orderOut(nil)
      return
    }

    let isSelectedApp =
      self.activeBundleIdentifier.map(self.displayPreferences.isEnabled) ?? false
    let shouldShow =
      self.contentPreferences.isCollapsed
      || self.displayPreferences.alwaysDisplay
      || (isSelectedApp && self.activeAppHasVisibleWindow)

    if shouldShow {
      panel.orderFrontRegardless()
    } else {
      panel.orderOut(nil)
    }
  }

  private func refreshActiveApplication() {
    let frontmostApplication = NSWorkspace.shared.frontmostApplication
    if frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
      self.handleActivatedApplication(frontmostApplication)
    }
  }

  private func refreshActiveAppVisibility() {
    guard let bundleIdentifier = self.activeBundleIdentifier else { return }
    let hasVisibleWindow =
      self.displayPreferences.isEnabled(bundleIdentifier)
      && self.applicationWindowIsVisible(bundleIdentifier: bundleIdentifier)
    guard hasVisibleWindow != self.activeAppHasVisibleWindow else { return }
    self.activeAppHasVisibleWindow = hasVisibleWindow
    self.updatePanelVisibility()
  }

  private func updateVisibilityPolling() {
    let shouldPoll =
      !self.contentPreferences.isCollapsed
      && !self.displayPreferences.alwaysDisplay
      && self.activeBundleIdentifier.map(self.displayPreferences.isEnabled) == true

    if shouldPoll {
      guard self.visibilityTimer == nil else { return }
      self.visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
        [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshActiveAppVisibility()
        }
      }
    } else {
      self.visibilityTimer?.invalidate()
      self.visibilityTimer = nil
    }
  }

  private func handleActivatedApplication(_ application: NSRunningApplication?) {
    let bundleIdentifier = application?.bundleIdentifier
    guard bundleIdentifier != self.activeBundleIdentifier else {
      if let bundleIdentifier {
        self.activeAppHasVisibleWindow =
          Self.isSupportedApp(bundleIdentifier)
          && self.applicationWindowIsVisible(bundleIdentifier: bundleIdentifier)
      }
      return
    }

    if self.contentPreferences.isCollapsed {
      self.detachWindow(savePreference: true)
      self.activeBundleIdentifier = bundleIdentifier
      self.activeAppHasVisibleWindow = false
      return
    }

    self.saveFrameForActiveApp()
    self.saveAttachmentForActiveContext()
    self.clearAttachmentRuntime(savePreference: false)
    self.activeBundleIdentifier = bundleIdentifier
    self.restoreContentSelectionForActiveContext()
    self.store.setActiveProviders(self.contentPreferences.activeProviders)

    self.restoreFrameForActiveContext()
    self.refreshAttachability()
    self.restoreAttachmentForActiveContext()

    if let bundleIdentifier {
      self.activeAppHasVisibleWindow =
        self.displayPreferences.isEnabled(bundleIdentifier)
        && self.applicationWindowIsVisible(bundleIdentifier: bundleIdentifier)
    } else {
      self.activeAppHasVisibleWindow = false
    }
  }

  private func applicationWindowIsVisible(bundleIdentifier: String) -> Bool {
    guard
      let targetApplication = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleIdentifier
      }),
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID) as? [[String: Any]]
    else {
      return false
    }

    return windows.contains { window in
      guard
        let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
        ownerPID == targetApplication.processIdentifier,
        let layer = window[kCGWindowLayer as String] as? Int,
        layer == 0,
        let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
      else {
        return false
      }

      return bounds.width >= 200 && bounds.height >= 100
    }
  }

  private func saveFrameForActiveApp() {
    guard
      !self.isRestoringFrame,
      !self.contentPreferences.isCollapsed,
      let panel,
      let contextKey = self.activeContextKey
    else {
      return
    }

    UserDefaults.standard.set(
      NSStringFromRect(panel.frame),
      forKey: Self.frameStorageKey(
        contextKey: contextKey,
        selectionKey: self.contentPreferences.selectionKey))
  }

  private func restoreFrameForActiveContext() {
    guard let contextKey = self.activeContextKey else { return }
    self.restoreFrame(contextKey: contextKey)
  }

  private func restoreFrame(contextKey: String) {
    guard let panel else { return }
    self.isRestoringFrame = true
    defer {
      self.currentContentDesignSize = self.contentPreferences.designSize
      self.isRestoringFrame = false
    }

    if let frameString = UserDefaults.standard.string(
      forKey: Self.frameStorageKey(
        contextKey: contextKey,
        selectionKey: self.contentPreferences.selectionKey))
    {
      let savedFrame = NSRectFromString(frameString)
      let designSize = self.contentPreferences.designSize
      let minimumScale = self.contentPreferences.minimumSize.height / designSize.height
      let scale = max(minimumScale, savedFrame.height / designSize.height)
      let restoredSize = NSSize(
        width: designSize.width * scale,
        height: designSize.height * scale)
      let restoredOrigin = NSPoint(
        x: savedFrame.maxX - restoredSize.width,
        y: savedFrame.origin.y)
      panel.setFrame(
        NSRect(origin: restoredOrigin, size: restoredSize),
        display: true)
    } else {
      panel.setContentSize(self.contentPreferences.designSize)
      self.positionAtTopRight(panel)
    }
  }

  private func contentConfigurationDidChange() {
    if self.contentPreferences.isCollapsed {
      self.detachWindow(savePreference: true)
    }
    self.store.setActiveProviders(self.contentPreferences.activeProviders)
    guard !self.isRestoringFrame, let panel else { return }

    let designSize = self.contentPreferences.designSize
    let previousDesignSize = self.currentContentDesignSize ?? designSize
    let oldFrame = panel.frame
    let minimumScale = self.contentPreferences.minimumSize.height / designSize.height
    let scale = max(minimumScale, oldFrame.height / previousDesignSize.height)
    let newSize = NSSize(
      width: designSize.width * scale,
      height: designSize.height * scale)
    let newOrigin = NSPoint(
      x: oldFrame.maxX - newSize.width,
      y: oldFrame.origin.y)

    self.isRestoringFrame = true
    self.applyWindowConstraints(panel)
    panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    self.currentContentDesignSize = designSize
    self.isRestoringFrame = false

    self.saveContentSelectionForActiveContext()
    self.saveFrameForActiveApp()
    self.updateVisibilityPolling()
    self.refreshAttachability()
    self.updatePanelVisibility()
  }

  private func toggleWindowAttachment() {
    if self.attachedWindow != nil {
      self.detachWindow(savePreference: true)
    } else {
      self.attachToFrontmostWindow(promptForAccessibility: true)
    }
  }

  private func attachToFrontmostWindow(
    placement preferredPlacement: AttachedWindowPlacement? = nil,
    promptForAccessibility: Bool
  ) {
    guard
      !self.contentPreferences.isCollapsed,
      let panel,
      let application = NSWorkspace.shared.frontmostApplication,
      application.bundleIdentifier != Bundle.main.bundleIdentifier,
      let targetWindow = Self.frontmostWindow(for: application)
    else {
      NSSound.beep()
      self.refreshAttachability()
      return
    }

    let placement = preferredPlacement ?? AttachedWindowPlacement(
      panelFrame: panel.frame,
      targetFrame: targetWindow.frame)
    let accessibilityWindow = Self.accessibilityWindow(
      for: application,
      promptIfNeeded: self.shouldPromptForAccessibilityPermission(promptForAccessibility))
    self.attachedWindow = AttachedWindow(
      processIdentifier: application.processIdentifier,
      windowNumber: targetWindow.windowNumber,
      placement: placement,
      accessibilityWindow: accessibilityWindow)
    self.attachmentState.isAttached = true
    self.saveAttachmentForActiveContext()
    self.applyAttachmentConstraints()
    if let accessibilityWindow {
      self.startAccessibilityAttachmentObserver(
        processIdentifier: application.processIdentifier,
        window: accessibilityWindow)
    } else {
      self.startAttachmentPolling()
    }
    self.followAttachedWindow()
  }

  private func detachWindow(savePreference: Bool) {
    guard self.attachedWindow != nil || self.attachmentState.isAttached else { return }
    self.clearAttachmentRuntime(savePreference: savePreference)
    self.updatePanelVisibility()
  }

  private func shouldPromptForAccessibilityPermission(_ requested: Bool) -> Bool {
    guard requested, !AXIsProcessTrusted() else { return false }
    let key = Self.accessibilityPromptedStorageKey()
    guard
      !self.hasRequestedAccessibilityPermissionThisSession,
      !UserDefaults.standard.bool(forKey: key)
    else {
      return false
    }
    self.hasRequestedAccessibilityPermissionThisSession = true
    UserDefaults.standard.set(true, forKey: key)
    return true
  }

  private func clearAttachmentRuntime(savePreference: Bool) {
    if savePreference {
      self.saveAttachmentEnabledForActiveContext(false)
    }
    self.attachedWindow = nil
    self.attachmentState.isAttached = false
    self.attachmentTimer?.invalidate()
    self.attachmentTimer = nil
    if let observerSource = self.attachmentObserverSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), observerSource, .commonModes)
    }
    self.attachmentObserverSource = nil
    self.attachmentObserver = nil
    self.applyAttachmentConstraints()
  }

  private func applyAttachmentConstraints() {
    guard let panel else { return }
    let isAttached = self.attachedWindow != nil
    panel.isMovableByWindowBackground = !isAttached
    if isAttached {
      panel.styleMask.remove(.resizable)
    } else {
      panel.styleMask.insert(.resizable)
    }
    self.applyWindowConstraints(panel)
  }

  private func startAttachmentPolling() {
    guard self.attachmentTimer == nil else { return }
    self.attachmentTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        self?.followAttachedWindow()
      }
    }
  }

  private func followAttachedWindow() {
    guard
      let panel,
      let attachedWindow,
      let targetFrame = self.targetFrame(for: attachedWindow)
    else {
      self.updatePanelVisibility()
      return
    }

    let newOrigin = attachedWindow.placement.origin(
      forPanelSize: panel.frame.size,
      targetFrame: targetFrame)
    guard
      abs(panel.frame.origin.x - newOrigin.x) > 0.5
        || abs(panel.frame.origin.y - newOrigin.y) > 0.5
    else {
      self.updatePanelVisibility()
      return
    }

    self.isFollowingAttachedWindow = true
    panel.setFrameOrigin(newOrigin)
    self.isFollowingAttachedWindow = false
    self.updatePanelVisibility()
  }

  private func refreshAttachmentOffset() {
    guard
      let panel,
      var attachedWindow = self.attachedWindow,
      let targetFrame = self.targetFrame(for: attachedWindow)
    else {
      return
    }
    attachedWindow.placement = AttachedWindowPlacement(
      panelFrame: panel.frame,
      targetFrame: targetFrame)
    self.attachedWindow = attachedWindow
    self.saveAttachmentForActiveContext()
  }

  private func refreshAttachability() {
    guard
      !self.contentPreferences.isCollapsed,
      let application = NSWorkspace.shared.frontmostApplication,
      application.bundleIdentifier != Bundle.main.bundleIdentifier
    else {
      self.attachmentState.canAttachToFrontmostWindow = false
      return
    }
    self.attachmentState.canAttachToFrontmostWindow =
      Self.frontmostWindow(for: application) != nil
  }

  private var attachedWindowIsVisible: Bool {
    guard let attachedWindow else { return true }
    return self.targetFrame(for: attachedWindow) != nil
  }

  private func targetFrame(for attachedWindow: AttachedWindow) -> NSRect? {
    if let accessibilityWindow = attachedWindow.accessibilityWindow,
      let frame = Self.accessibilityFrame(for: accessibilityWindow)
    {
      return frame
    }
    return Self.window(
      processIdentifier: attachedWindow.processIdentifier,
      windowNumber: attachedWindow.windowNumber)?.frame
  }

  private func startAccessibilityAttachmentObserver(
    processIdentifier: pid_t,
    window: AXUIElement
  ) {
    self.attachmentTimer?.invalidate()
    self.attachmentTimer = nil
    if let observerSource = self.attachmentObserverSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), observerSource, .commonModes)
    }
    self.attachmentObserverSource = nil
    self.attachmentObserver = nil

    var observer: AXObserver?
    let error = AXObserverCreate(processIdentifier, quotaFloatAXObserverCallback, &observer)
    guard error == .success, let observer else {
      self.startAttachmentPolling()
      return
    }

    let refcon = Unmanaged.passUnretained(self).toOpaque()
    AXObserverAddNotification(observer, window, kAXMovedNotification as CFString, refcon)
    AXObserverAddNotification(observer, window, kAXResizedNotification as CFString, refcon)
    AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)

    let source = AXObserverGetRunLoopSource(observer)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    self.attachmentObserver = observer
    self.attachmentObserverSource = source
  }

  fileprivate func accessibilityObservedWindowDidChange() {
    self.followAttachedWindow()
  }

  private func saveAttachmentForActiveContext() {
    guard let contextKey = self.activeContextKey else { return }
    let defaults = UserDefaults.standard
    if let attachedWindow {
      defaults.set(true, forKey: Self.attachmentEnabledStorageKey(contextKey: contextKey))
      defaults.set(
        attachedWindow.placement.storageString,
        forKey: Self.attachmentPlacementStorageKey(contextKey: contextKey))
    } else {
      defaults.set(false, forKey: Self.attachmentEnabledStorageKey(contextKey: contextKey))
    }
  }

  private func saveAttachmentEnabledForActiveContext(_ enabled: Bool) {
    guard let contextKey = self.activeContextKey else { return }
    UserDefaults.standard.set(
      enabled,
      forKey: Self.attachmentEnabledStorageKey(contextKey: contextKey))
  }

  private func restoreAttachmentForActiveContext() {
    guard
      !self.contentPreferences.isCollapsed,
      let contextKey = self.activeContextKey,
      UserDefaults.standard.bool(forKey: Self.attachmentEnabledStorageKey(contextKey: contextKey))
    else {
      return
    }

    let placement = UserDefaults.standard.string(
      forKey: Self.attachmentPlacementStorageKey(contextKey: contextKey)
    ).flatMap(AttachedWindowPlacement.init(storageString:))
    self.attachToFrontmostWindow(placement: placement, promptForAccessibility: false)
  }

  private func restoreContentSelectionForActiveContext() {
    guard let contextKey = self.activeContextKey else { return }
    let defaults = UserDefaults.standard
    let storedProviders = defaults.stringArray(
      forKey: Self.contentSelectionStorageKey(contextKey: contextKey))?
      .compactMap(QuotaProvider.init(rawValue:))
    let selectedProviders: Set<QuotaProvider>
    if let storedProviders, !storedProviders.isEmpty {
      selectedProviders = Set(storedProviders)
    } else {
      let legacyMode = defaults.string(
        forKey: Self.legacyContentModeStorageKey(contextKey: contextKey))
      switch legacyMode {
      case "codex": selectedProviders = [.codex]
      case "claude": selectedProviders = [.claude]
      default: selectedProviders = Set(QuotaProviderCatalog.orderedProviders)
      }
    }
    let pinned =
      defaults.object(
        forKey: Self.singleResetPinnedStorageKey(contextKey: contextKey)) as? Bool ?? true
    let multiPinned =
      defaults.object(
        forKey: Self.multiResetPinnedStorageKey(contextKey: contextKey)) as? Bool ?? false
    self.isRestoringFrame = true
    self.contentPreferences.setSelectedProviders(selectedProviders)
    self.contentPreferences.setSingleResetPinned(pinned)
    self.contentPreferences.setMultiResetPinned(multiPinned)
    if let panel {
      self.applyWindowConstraints(panel)
    }
    self.isRestoringFrame = false
  }

  private func saveContentSelectionForActiveContext() {
    guard let contextKey = self.activeContextKey else { return }
    UserDefaults.standard.set(
      self.contentPreferences.orderedSelectedProviders.map(\.rawValue),
      forKey: Self.contentSelectionStorageKey(contextKey: contextKey))
    UserDefaults.standard.set(
      self.contentPreferences.singleResetPinned,
      forKey: Self.singleResetPinnedStorageKey(contextKey: contextKey))
    UserDefaults.standard.set(
      self.contentPreferences.multiResetPinned,
      forKey: Self.multiResetPinnedStorageKey(contextKey: contextKey))
  }

  private func applyWindowConstraints(_ panel: NSPanel) {
    let designSize = self.contentPreferences.designSize
    panel.contentAspectRatio = designSize
    panel.contentMinSize = self.contentPreferences.minimumSize
    panel.minSize = self.contentPreferences.minimumSize
    panel.contentMaxSize = NSSize(
      width: designSize.width * 10,
      height: designSize.height * 10)
    panel.maxSize = panel.contentMaxSize
  }

  private var activeContextKey: String? {
    guard let bundleIdentifier = self.activeBundleIdentifier else {
      return "general"
    }
    return Self.isSupportedApp(bundleIdentifier) ? bundleIdentifier : "general"
  }

  private static func isSupportedApp(_ bundleIdentifier: String) -> Bool {
    Self.supportedBundleIdentifiers.contains(bundleIdentifier)
  }

  private static func frameStorageKey(
    contextKey: String,
    selectionKey: String
  ) -> String {
    "QuotaFloatFrame.\(contextKey).\(selectionKey)"
  }

  private static func contentSelectionStorageKey(contextKey: String) -> String {
    "QuotaFloatContentProviders.\(contextKey)"
  }

  private static func legacyContentModeStorageKey(contextKey: String) -> String {
    "QuotaFloatContentMode.\(contextKey)"
  }

  private static func singleResetPinnedStorageKey(contextKey: String) -> String {
    "QuotaFloatSingleResetPinned.\(contextKey)"
  }

  private static func multiResetPinnedStorageKey(contextKey: String) -> String {
    "QuotaFloatMultiResetPinned.\(contextKey)"
  }

  private static func attachmentEnabledStorageKey(contextKey: String) -> String {
    "QuotaFloatWindowAttachmentEnabled.\(contextKey)"
  }

  private static func attachmentPlacementStorageKey(contextKey: String) -> String {
    "QuotaFloatWindowAttachmentPlacement.\(contextKey)"
  }

  private static func accessibilityPromptedStorageKey() -> String {
    let executablePath = Bundle.main.executablePath ?? Bundle.main.bundlePath
    return "QuotaFloatAccessibilityPrompted.\(executablePath)"
  }
}

private struct AttachedWindow {
  let processIdentifier: pid_t
  let windowNumber: Int
  var placement: AttachedWindowPlacement
  let accessibilityWindow: AXUIElement?
}

private struct AttachedWindowPlacement {
  enum HorizontalAnchor {
    case left
    case right
  }

  enum VerticalAnchor {
    case bottom
    case top
  }

  let horizontalAnchor: HorizontalAnchor
  let verticalAnchor: VerticalAnchor
  let horizontalInset: CGFloat
  let verticalInset: CGFloat

  var storageString: String {
    [
      self.horizontalAnchor.storageValue,
      self.verticalAnchor.storageValue,
      String(Double(self.horizontalInset)),
      String(Double(self.verticalInset)),
    ].joined(separator: ",")
  }

  init?(storageString: String) {
    let parts = storageString.split(separator: ",").map(String.init)
    guard
      parts.count == 4,
      let horizontalAnchor = HorizontalAnchor(storageValue: parts[0]),
      let verticalAnchor = VerticalAnchor(storageValue: parts[1]),
      let horizontalInset = Double(parts[2]),
      let verticalInset = Double(parts[3])
    else {
      return nil
    }
    self.horizontalAnchor = horizontalAnchor
    self.verticalAnchor = verticalAnchor
    self.horizontalInset = CGFloat(horizontalInset)
    self.verticalInset = CGFloat(verticalInset)
  }

  init(panelFrame: NSRect, targetFrame: NSRect) {
    let leftInset = panelFrame.minX - targetFrame.minX
    let rightInset = targetFrame.maxX - panelFrame.maxX
    if abs(leftInset) <= abs(rightInset) {
      self.horizontalAnchor = .left
      self.horizontalInset = leftInset
    } else {
      self.horizontalAnchor = .right
      self.horizontalInset = rightInset
    }

    let bottomInset = panelFrame.minY - targetFrame.minY
    let topInset = targetFrame.maxY - panelFrame.maxY
    if abs(bottomInset) <= abs(topInset) {
      self.verticalAnchor = .bottom
      self.verticalInset = bottomInset
    } else {
      self.verticalAnchor = .top
      self.verticalInset = topInset
    }
  }

  func origin(forPanelSize panelSize: NSSize, targetFrame: NSRect) -> NSPoint {
    let x =
      switch self.horizontalAnchor {
      case .left:
        targetFrame.minX + self.horizontalInset
      case .right:
        targetFrame.maxX - self.horizontalInset - panelSize.width
      }
    let y =
      switch self.verticalAnchor {
      case .bottom:
        targetFrame.minY + self.verticalInset
      case .top:
        targetFrame.maxY - self.verticalInset - panelSize.height
      }
    return NSPoint(x: x, y: y)
  }
}

extension AttachedWindowPlacement.HorizontalAnchor {
  fileprivate var storageValue: String {
    switch self {
    case .left: "left"
    case .right: "right"
    }
  }

  fileprivate init?(storageValue: String) {
    switch storageValue {
    case "left": self = .left
    case "right": self = .right
    default: return nil
    }
  }
}

extension AttachedWindowPlacement.VerticalAnchor {
  fileprivate var storageValue: String {
    switch self {
    case .bottom: "bottom"
    case .top: "top"
    }
  }

  fileprivate init?(storageValue: String) {
    switch storageValue {
    case "bottom": self = .bottom
    case "top": self = .top
    default: return nil
    }
  }
}

private struct TrackedWindow {
  let windowNumber: Int
  let frame: NSRect
}

extension AppDelegate {
  private static func frontmostWindow(for application: NSRunningApplication) -> TrackedWindow? {
    self.windows(processIdentifier: application.processIdentifier).first
  }

  private static func window(
    processIdentifier: pid_t,
    windowNumber: Int
  ) -> TrackedWindow? {
    self.windows(processIdentifier: processIdentifier).first {
      $0.windowNumber == windowNumber
    }
  }

  private static func windows(processIdentifier: pid_t) -> [TrackedWindow] {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID) as? [[String: Any]]
    else {
      return []
    }

    return windows.compactMap { window in
      guard
        let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
        ownerPID == processIdentifier,
        let layer = window[kCGWindowLayer as String] as? Int,
        layer == 0,
        let windowNumber = window[kCGWindowNumber as String] as? Int,
        let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
        let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary)
      else {
        return nil
      }

      let frame = self.convertQuartzWindowFrameToAppKit(quartzFrame)
      guard frame.width >= 200, frame.height >= 100 else { return nil }
      return TrackedWindow(windowNumber: windowNumber, frame: frame)
    }
  }

  private static func convertQuartzWindowFrameToAppKit(_ quartzFrame: CGRect) -> NSRect {
    let midpoint = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)
    guard
      let screen = NSScreen.screens.first(where: { screen in
        guard
          let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber
        else {
          return false
        }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        return displayBounds.contains(midpoint)
      }),
      let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
    else {
      return NSRect(origin: quartzFrame.origin, size: quartzFrame.size)
    }

    let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
    let localX = quartzFrame.minX - displayBounds.minX
    let localYFromTop = quartzFrame.minY - displayBounds.minY
    return NSRect(
      x: screen.frame.minX + localX,
      y: screen.frame.maxY - localYFromTop - quartzFrame.height,
      width: quartzFrame.width,
      height: quartzFrame.height)
  }

  private static func accessibilityWindow(
    for application: NSRunningApplication,
    promptIfNeeded: Bool
  ) -> AXUIElement? {
    let options =
      promptIfNeeded
      ? ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      : nil
    guard AXIsProcessTrustedWithOptions(options) else { return nil }

    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    var focusedWindow: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindow) == .success,
      let focusedWindow
    {
      return (focusedWindow as! AXUIElement)
    }

    var windows: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windows) == .success,
      let windowArray = windows as? [AXUIElement]
    else {
      return nil
    }
    return windowArray.first { self.accessibilityFrame(for: $0) != nil }
  }

  private static func accessibilityFrame(for window: AXUIElement) -> NSRect? {
    guard
      let position = self.accessibilityCGPoint(
        for: window,
        attribute: kAXPositionAttribute as CFString),
      let size = self.accessibilityCGSize(
        for: window,
        attribute: kAXSizeAttribute as CFString)
    else {
      return nil
    }
    return self.convertQuartzWindowFrameToAppKit(CGRect(origin: position, size: size))
  }

  private static func accessibilityCGPoint(
    for element: AXUIElement,
    attribute: CFString
  ) -> CGPoint? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
      let axValue = value,
      CFGetTypeID(axValue) == AXValueGetTypeID()
    else {
      return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue((axValue as! AXValue), .cgPoint, &point) else {
      return nil
    }
    return point
  }

  private static func accessibilityCGSize(
    for element: AXUIElement,
    attribute: CFString
  ) -> CGSize? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
      let axValue = value,
      CFGetTypeID(axValue) == AXValueGetTypeID()
    else {
      return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue((axValue as! AXValue), .cgSize, &size) else {
      return nil
    }
    return size
  }
}

private let quotaFloatAXObserverCallback: AXObserverCallback = {
  _,
  _,
  _,
  refcon in
  guard let refcon else { return }
  let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
  Task { @MainActor in
    appDelegate.accessibilityObservedWindowDidChange()
  }
}

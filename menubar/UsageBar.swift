// UsageBar — Claude와 Codex의 5시간·주간 사용 한도를 macOS 메뉴 막대 두 줄에 보여 준다.
// 채팅(데스크톱 앱 Chat 탭, 웹)에서 쓴 양도 같은 한도에 잡히므로 Claude Code 밖에서도 보이게 한다.
//
// 수치는 usage-pane mod 가 Claude Code 응답마다 남기는 마지막 측정값(~/.claude/plugins/store)을 읽는다.
// 채팅에서만 쓴 양은 다음에 Claude Code 세션이 응답을 받을 때 반영된다.

import AppKit

struct UsageWindow {
  let kind: String
  let percentUsed: Double
  let resetsAt: Date?
}

struct Limits {
  let windows: [UsageWindow]
  let measuredAt: Date
}

let STORE_DIR = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/store")
// usage-pane 이 $.store 에 남기는 파일 이름 앞부분
let STORE_PREFIX = "usage-pane_"

// 저장값을 다시 읽는 주기(분). 메뉴 → 갱신 주기에서 고르거나 직접 입력하면 UserDefaults 에 남는다.
// 기본 1분은 usage-pane 이 다른 세션의 측정값을 가져오는 주기와 같다.
let INTERVAL_KEY = "refreshMinutes"
let DEFAULT_MINUTES = 1
// 분 단위로 받고, 하루보다 긴 주기는 쓸 일이 없어 막는다.
let MIN_MINUTES = 1
let MAX_MINUTES = 1440
let MINUTE_CHOICES = [1, 3, 5, 10, 30]
// 리셋 여부와 흐리게 그리기는 읽기 주기와 상관없이 1분마다 다시 계산한다.
let RENDER_INTERVAL: TimeInterval = 60
// 이보다 오래된 측정값은 메뉴 막대에서 흐리게 그린다.
let STALE_AFTER: TimeInterval = 15 * 60

// 한국어 사용자를 위한 도구라 리셋 시각은 KST 로 고정해 보여 준다 (usage-pane 과 같다).
let KST = TimeZone(identifier: "Asia/Seoul")!
let DAYS = ["일", "월", "화", "수", "목", "금", "토"]
let LABELS = [
  "five_hour": "5시간 사용량",
  "seven_day": "주간 사용량",
  "spend_limit": "지출 한도 사용량",
]
// 메뉴 막대에는 이 두 창만 그린다.
let SHORT_LABELS = ["five_hour": "5시간", "seven_day": "주간"]
let ORDER = ["five_hour", "seven_day"]

// MARK: - 수치 읽기

func parseDate(_ s: String?) -> Date? {
  guard let s else { return nil }
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let d = f.date(from: s) { return d }
  f.formatOptions = [.withInternetDateTime]
  return f.date(from: s)
}

func number(_ v: Any?) -> Double? {
  (v as? NSNumber)?.doubleValue
}

// usage-pane 저장 파일 형식: { limits: { windows: [{ kind, percentUsed: 0~100, resetsAt: ISO }], measuredAt: ms } }
func parseStore(_ obj: [String: Any]) -> Limits? {
  guard let limits = obj["limits"] as? [String: Any],
        let at = number(limits["measuredAt"]),
        let windows = limits["windows"] as? [[String: Any]] else { return nil }
  let parsed = windows.compactMap { w -> UsageWindow? in
    guard let kind = w["kind"] as? String, let used = number(w["percentUsed"]) else { return nil }
    return UsageWindow(kind: kind, percentUsed: used, resetsAt: parseDate(w["resetsAt"] as? String))
  }
  return Limits(windows: parsed, measuredAt: Date(timeIntervalSince1970: at / 1000))
}

// usage-pane 저장 파일이 여럿이면(설치 경로가 바뀐 경우) 가장 최근 측정값을 쓴다.
func readStore() -> Limits? {
  guard let names = try? FileManager.default.contentsOfDirectory(atPath: STORE_DIR.path) else { return nil }
  var best: Limits?
  for name in names where name.hasPrefix(STORE_PREFIX) && name.hasSuffix(".json") {
    guard let data = FileManager.default.contents(atPath: STORE_DIR.appendingPathComponent(name).path),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let held = parseStore(obj) else { continue }
    if best == nil || held.measuredAt > best!.measuredAt { best = held }
  }
  return best
}

// 저장값이 없거나(0) 범위를 벗어나면 기본값·경계값으로 맞춘다.
func clampMinutes(_ saved: Int) -> Int {
  saved > 0 ? min(MAX_MINUTES, max(MIN_MINUTES, saved)) : DEFAULT_MINUTES
}

func refreshMinutes() -> Int {
  clampMinutes(UserDefaults.standard.integer(forKey: INTERVAL_KEY))
}

// 직접 입력 값: "15", "15분" 은 받고 소수·범위 밖은 거른다.
func parseMinutes(_ input: String) -> Int? {
  var s = input.trimmingCharacters(in: .whitespaces)
  if s.hasSuffix("분") { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
  guard let m = Int(s), (MIN_MINUTES...MAX_MINUTES).contains(m) else { return nil }
  return m
}

// MARK: - 글자 만들기

func kstCalendar() -> Calendar {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = KST
  return c
}

func clockText(_ d: Date) -> String {
  let c = kstCalendar().dateComponents([.hour, .minute], from: d)
  return String(format: "%02d:%02d", c.hour!, c.minute!)
}

func whenText(_ d: Date, now: Date) -> String {
  let cal = kstCalendar()
  if cal.isDate(d, inSameDayAs: now) { return clockText(d) }
  let c = cal.dateComponents([.month, .day, .weekday], from: d)
  return "\(c.month!)/\(c.day!)(\(DAYS[c.weekday! - 1])) \(clockText(d))"
}

func spanText(_ seconds: TimeInterval) -> String {
  let minutes = Int((seconds / 60).rounded(.up))
  let d = minutes / 1440
  let h = (minutes % 1440) / 60
  let m = minutes % 60
  return d > 0 ? "\(d)일 \(h)시간" : h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
}

func minutesText(_ m: Int) -> String {
  spanText(Double(m) * 60)
}

// 리셋 시각이 지난 창은 새 측정 전까지 0% 로 본다.
func usedOf(_ w: UsageWindow, now: Date) -> Double {
  if let r = w.resetsAt, r <= now { return 0 }
  return w.percentUsed
}

func percentText(_ p: Double) -> String {
  let r = (p * 10).rounded() / 10
  return r == r.rounded() ? "\(Int(r))%" : String(format: "%.1f%%", r)
}

func detailText(_ w: UsageWindow, now: Date) -> String? {
  guard let at = w.resetsAt else { return nil }
  if at <= now { return "\(whenText(at, now: now)) 리셋됨 · 다음 측정 뒤 갱신" }
  return "\(spanText(at.timeIntervalSince(now))) 후 리셋 · \(whenText(at, now: now))"
}

func agoText(_ at: Date, now: Date) -> String {
  let minutes = Int(now.timeIntervalSince(at) / 60)
  if minutes < 1 { return "\(whenText(at, now: now)) 측정" }
  return "\(whenText(at, now: now)) 측정 (\(spanText(Double(minutes) * 60)) 전)"
}

func sortWindows(_ windows: [UsageWindow]) -> [UsageWindow] {
  let rank = { (kind: String) in ORDER.firstIndex(of: kind) ?? ORDER.count }
  return windows.enumerated()
    .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
    .map(\.element)
}

func toneColor(_ used: Double) -> NSColor? {
  if used >= 90 { return .systemRed }
  if used >= 70 { return .systemOrange }
  return nil
}

// 없는 창은 0%가 아니라 —. Codex는 리셋이 지난 값도 재조회 전까지 —로 표시한다.
func barParts(_ limits: Limits?, now: Date, codex: Bool = false) -> [(label: String, used: Double?)] {
  ORDER.map { kind in
    let window = limits?.windows.first { $0.kind == kind }
    let used = window.flatMap { w -> Double? in
      if codex, let reset = w.resetsAt, reset <= now { return nil }
      return usedOf(w, now: now)
    }
    return (SHORT_LABELS[kind]!, used)
  }
}

func barText(_ provider: String, limits: Limits?, now: Date, codex: Bool = false) -> String {
  provider + "  " + barParts(limits, now: now, codex: codex)
    .map { "\($0.label) \($0.used.map(percentText) ?? "—")" }.joined(separator: " · ")
}

struct MenuLine {
  let text: String
  let indent: Int
}

func menuLines(_ limits: Limits?, now: Date, codex: Bool = false) -> [MenuLine] {
  guard let limits, !limits.windows.isEmpty else {
    return [
      MenuLine(text: "아직 측정한 한도 값이 없습니다", indent: 0),
      MenuLine(text: codex ? "계정에서 5시간·주간 한도가 제공되지 않았습니다" : "Claude Code 세션이 응답을 한 번 받으면 표시됩니다", indent: 1),
    ]
  }
  var lines: [MenuLine] = []
  if codex {
    for kind in ORDER where !limits.windows.contains(where: { $0.kind == kind }) {
      lines.append(MenuLine(text: "\(LABELS[kind]!) — (계정에서 제공하지 않음)", indent: 0))
    }
  }
  for w in sortWindows(limits.windows) {
    let expired = codex && w.resetsAt.map { $0 <= now } == true
    lines.append(MenuLine(text: "\(LABELS[w.kind] ?? w.kind) \(expired ? "— (갱신 대기)" : percentText(usedOf(w, now: now)))", indent: 0))
    if let detail = detailText(w, now: now) { lines.append(MenuLine(text: detail, indent: 1)) }
  }
  lines.append(MenuLine(text: agoText(limits.measuredAt, now: now), indent: 0))
  return lines
}

// MARK: - 메뉴 막대

// NSStatusBarButton의 기본 제목은 한 줄 기준이므로, 클릭은 버튼에 전달하고 두 줄만 직접 그린다.
func drawStatusRows(_ rows: [NSAttributedString], in bounds: NSRect) {
  let lineHeight: CGFloat = 11
  let top = (bounds.height - lineHeight * CGFloat(rows.count)) / 2
  for (index, row) in rows.enumerated() {
    row.draw(at: NSPoint(x: 6, y: top + CGFloat(index) * lineHeight))
  }
}

final class UsageStatusView: NSView {
  var rows: [NSAttributedString] = [] { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    drawStatusRows(rows, in: bounds)
  }
}

func statusRow(_ provider: String, limits: Limits?, now: Date, codex: Bool = false, failed: Bool = false) -> NSAttributedString {
  let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
  let stale = failed || (limits.map { now.timeIntervalSince($0.measuredAt) > STALE_AFTER } ?? true)
  let plain: NSColor = stale ? .secondaryLabelColor : .labelColor
  let title = NSMutableAttributedString(string: provider.padding(toLength: 7, withPad: " ", startingAt: 0), attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium), .foregroundColor: plain,
  ])
  // 5시간 값이 —, 27%, 99.9%여도 주간 열은 같은 위치에서 시작한다.
  let paragraph = NSMutableParagraphStyle()
  let firstColumnWidth = NSAttributedString(string: "5시간 99.9%", attributes: [.font: font]).size().width
  paragraph.tabStops = [NSTextTab(textAlignment: .left, location: ceil(title.size().width + firstColumnWidth) + 1)]
  for (index, part) in barParts(limits, now: now, codex: codex).enumerated() {
    if index > 0 { title.append(NSAttributedString(string: "\t· ", attributes: [.font: font, .foregroundColor: plain])) }
    title.append(NSAttributedString(string: "\(part.label) ", attributes: [.font: font, .foregroundColor: plain]))
    let color = stale ? plain : part.used.flatMap(toneColor) ?? plain
    title.append(NSAttributedString(string: part.used.map(percentText) ?? "—", attributes: [.font: font, .foregroundColor: color]))
  }
  if failed { title.append(NSAttributedString(string: " !", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])) }
  title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
  return title
}

@MainActor
final class UsageBar: NSObject, NSApplicationDelegate, NSMenuDelegate {
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  let statusView = UsageStatusView()
  var limits: Limits?
  var codexLimits: Limits?
  var codexError: CodexReadError?
  var codexRefreshing = false
  var menuOpen = false
  var readTimer: Timer?
  var renderTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    if let button = item.button {
      statusView.frame = button.bounds
      statusView.autoresizingMask = [.width, .height]
      button.addSubview(statusView)
    }
    refresh()
    schedule()
    renderTimer = Timer.scheduledTimer(withTimeInterval: RENDER_INTERVAL, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    // 잠자기에서 깨면 그동안 바뀐 값을 바로 가져온다.
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
  }

  @objc func refresh() {
    limits = readStore()
    render()
    guard !codexRefreshing else { return }
    codexRefreshing = true
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let result = readCodex()
      DispatchQueue.main.async {
        guard let self else { return }
        self.codexRefreshing = false
        switch result {
        case .success(let fresh): self.codexLimits = fresh; self.codexError = nil
        case .failure(let error): self.codexError = error
        }
        self.render()
        if self.menuOpen, let menu = self.item.menu { self.populateMenu(menu) }
      }
    }
  }

  func schedule() {
    readTimer?.invalidate()
    readTimer = Timer.scheduledTimer(withTimeInterval: Double(refreshMinutes()) * 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
  }

  // 주기를 바꾸면 바로 한 번 읽고 그 시점부터 새 주기로 센다.
  func setMinutes(_ minutes: Int) {
    UserDefaults.standard.set(minutes, forKey: INTERVAL_KEY)
    schedule()
    refresh()
  }

  @objc func chooseInterval(_ sender: NSMenuItem) {
    setMinutes(sender.tag)
  }

  @objc func askInterval() {
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
    field.stringValue = String(refreshMinutes())
    let alert = NSAlert()
    alert.messageText = "갱신 주기 (분)"
    alert.accessoryView = field
    alert.addButton(withTitle: "저장")
    alert.addButton(withTitle: "취소")
    alert.window.initialFirstResponder = field
    var hint = "\(MIN_MINUTES)~\(MAX_MINUTES) 사이의 정수를 입력하세요."
    // 메뉴 막대 앱은 앞으로 나와 있지 않아 입력 창이 뒤에 깔리지 않게 먼저 활성화한다.
    if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    while true {
      alert.informativeText = hint
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      if let minutes = parseMinutes(field.stringValue) {
        setMinutes(minutes)
        return
      }
      hint = "'\(field.stringValue)' 은(는) 쓸 수 없습니다. \(MIN_MINUTES)~\(MAX_MINUTES) 사이의 정수를 입력하세요."
    }
  }

  func render() {
    let now = Date()
    guard let button = item.button else { return }
    let rows = [
      statusRow("Claude", limits: limits, now: now),
      statusRow("Codex", limits: codexLimits, now: now, codex: true, failed: codexError != nil),
    ]
    item.length = ceil(rows.map { $0.size().width }.max() ?? 170) + 12
    button.title = ""
    statusView.rows = rows
    let description = [barText("Claude Code", limits: limits, now: now),
      barText("Codex", limits: codexLimits, now: now, codex: true)].joined(separator: "\n")
    button.toolTip = description + "\n사용한 비율 · 클릭하면 리셋 시각과 측정 상태를 볼 수 있습니다"
    button.setAccessibilityLabel(description)
  }

  // 메뉴를 열 때마다 저장값을 다시 읽고 남은 시간을 새로 계산한다.
  func menuNeedsUpdate(_ menu: NSMenu) {
    refresh()
    populateMenu(menu)
  }

  func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
  func menuDidClose(_ menu: NSMenu) { menuOpen = false }

  func populateMenu(_ menu: NSMenu) {
    menu.removeAllItems()
    let now = Date()
    for (provider, held, isCodex) in [("Claude Code", limits, false), ("Codex", codexLimits, true)] {
      if isCodex { menu.addItem(.separator()) }
      let header = NSMenuItem(title: provider, action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      var lines = menuLines(held, now: now, codex: isCodex)
      if isCodex, let error = codexError {
        if held == nil { lines = [] }
        lines.append(MenuLine(text: error.description, indent: 0))
        if held != nil { lines.append(MenuLine(text: "마지막으로 조회한 값을 표시 중입니다", indent: 1)) }
      } else if isCodex && codexRefreshing {
        if held == nil { lines = [] }
        lines.append(MenuLine(text: "사용량 조회 중…", indent: 0))
      }
      for line in lines {
        let entry = NSMenuItem(title: line.text, action: nil, keyEquivalent: "")
        entry.indentationLevel = line.indent + 1
        entry.isEnabled = false
        menu.addItem(entry)
      }
    }
    menu.addItem(.separator())
    let current = refreshMinutes()
    let intervals = NSMenu()
    for minutes in MINUTE_CHOICES {
      let choice = NSMenuItem(title: minutesText(minutes), action: #selector(chooseInterval(_:)), keyEquivalent: "")
      choice.target = self
      choice.tag = minutes
      choice.state = minutes == current ? .on : .off
      intervals.addItem(choice)
    }
    intervals.addItem(.separator())
    let custom = !MINUTE_CHOICES.contains(current)
    let ask = NSMenuItem(title: custom ? "직접 입력… (지금 \(minutesText(current)))" : "직접 입력…", action: #selector(askInterval), keyEquivalent: "")
    ask.target = self
    ask.state = custom ? .on : .off
    intervals.addItem(ask)
    let interval = NSMenuItem(title: "갱신 주기: \(minutesText(current))", action: nil, keyEquivalent: "")
    interval.submenu = intervals
    menu.addItem(interval)
    let refreshNow = NSMenuItem(title: "지금 새로고침", action: #selector(refresh), keyEquivalent: "r")
    refreshNow.target = self
    menu.addItem(refreshNow)
    menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
  }
}

// MARK: - 시작

// --once: 메뉴 막대를 띄우지 않고 한 번 읽어 메뉴 막대 글자와 메뉴 내용을 출력한다 (로컬 확인용).
func printOnce() {
  let now = Date()
  let limits = readStore()
  let codex = readCodex()
  let codexLimits = try? codex.get()
  print("[메뉴 막대]\n\(barText("Claude", limits: limits, now: now))\n\(barText("Codex", limits: codexLimits, now: now, codex: true))")
  print("[Claude Code]")
  for line in menuLines(limits, now: now) {
    print(String(repeating: "  ", count: line.indent + 1) + line.text)
  }
  print("[Codex]")
  if case .failure(let error) = codex { print("  \(error.description)") }
  else {
    for line in menuLines(codexLimits, now: now, codex: true) {
      print(String(repeating: "  ", count: line.indent + 1) + line.text)
    }
  }
  print("[갱신 주기] \(minutesText(refreshMinutes()))")
}

// test.sh 는 Tests.swift 의 @main 으로 빌드한다.
#if !USAGEBAR_TESTS
@main
struct Main {
  static func main() {
    if CommandLine.arguments.contains("--once") {
      printOnce()
      return
    }

    MainActor.assumeIsolated {
      let app = NSApplication.shared
      let delegate = UsageBar()
      app.delegate = delegate
      // Dock 아이콘 없이 메뉴 막대에만 둔다.
      app.setActivationPolicy(.accessory)
      app.run()
    }
  }
}
#endif

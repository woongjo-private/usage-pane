// UsageBar 의 순수 함수(저장값 읽기·글자 만들기·주기 입력)를 확인한다. 실행: ./menubar/test.sh
import AppKit

func json(_ s: String) -> [String: Any] {
  try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
}

@main
struct Tests {
  static func main() {
    var failed = 0
    func check(_ ok: Bool, _ name: String) {
      print(ok ? "ok   \(name)" : "FAIL \(name)")
      if !ok { failed += 1 }
    }

    // 직접 입력
    check(parseMinutes("15") == 15, "parseMinutes: 정수")
    check(parseMinutes(" 15분 ") == 15, "parseMinutes: 공백과 '분' 은 받는다")
    check(parseMinutes("1") == 1 && parseMinutes("1440") == 1440, "parseMinutes: 경계값")
    check(parseMinutes("0") == nil && parseMinutes("1441") == nil, "parseMinutes: 범위 밖은 거른다")
    check(parseMinutes("1.5") == nil && parseMinutes("abc") == nil && parseMinutes("") == nil, "parseMinutes: 소수·글자·빈칸은 거른다")

    // 저장된 주기
    check(clampMinutes(0) == DEFAULT_MINUTES, "clampMinutes: 저장값 없으면 기본값")
    check(clampMinutes(-5) == DEFAULT_MINUTES, "clampMinutes: 음수는 기본값")
    check(clampMinutes(45) == 45, "clampMinutes: 범위 안은 그대로")
    check(clampMinutes(99_999) == MAX_MINUTES, "clampMinutes: 너무 길면 하루로")
    check(minutesText(45) == "45분" && minutesText(90) == "1시간 30분", "minutesText")

    // usage-pane 저장 파일 (2026-10-29 실제 파일과 같은 모양)
    let held = parseStore(json("""
    {"limits": {"windows": [
      {"kind": "five_hour", "percentUsed": 27, "resetsAt": "2026-10-29T09:50:00.000Z"},
      {"kind": "seven_day", "percentUsed": 71.5, "resetsAt": "2026-11-02T00:00:00.000Z"},
      {"kind": "spend_limit", "percentUsed": 10}
    ], "measuredAt": 1793263295755}}
    """))
    check(held?.windows.map(\.kind) == ["five_hour", "seven_day", "spend_limit"], "parseStore: 창 목록")
    check(held?.windows[1].percentUsed == 71.5 && held?.windows[2].resetsAt == nil, "parseStore: 사용 %·리셋 시각 없는 창")
    check(held.map { abs($0.measuredAt.timeIntervalSince1970 - 1_793_263_295.755) < 0.001 } ?? false, "parseStore: measuredAt 은 ms")
    check(parseStore(json(#"{"other": 1}"#)) == nil, "parseStore: limits 없으면 nil")

    // 메뉴 막대 글자
    let now = parseDate("2026-10-29T09:00:00Z")!
    let bar = barParts(held, now: now).map { "\($0.label) \($0.used.map(percentText) ?? "—")" }
    check(bar == ["5시간 27%", "주간 72%"], "barParts: 5시간·주간만, 정수로 순서대로")

    // 리셋이 지난 창은 0%
    let later = parseDate("2026-10-29T10:00:00Z")!
    check(usedOf(held!.windows[0], now: later) == 0, "usedOf: 리셋 지나면 0%")
    check(percentText(43.5) == "44%" && percentText(27.0) == "27%" && percentText(100) == "100%", "percentText: 정수로 반올림")

    // Codex 창의 기간과 버킷을 기준으로 구분한다. primary/secondary 위치로 추측하지 않는다.
    let both = parseCodexLimits(json("""
    {"rateLimitsByLimitId":{"codex":{
      "primary":{"usedPercent":12.5,"windowDurationMins":300,"resetsAt":1793278800},
      "secondary":{"usedPercent":43,"windowDurationMins":10080,"resetsAt":1793577600}
    }},"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}}}
    """), measuredAt: now)!
    check(both.windows.map(\.kind) == ["five_hour", "seven_day"], "Codex: 300분·10080분 창")
    check(both.windows[0].percentUsed == 12.5, "Codex: 여러 버킷 응답을 레거시보다 우선")
    check(both.windows[0].resetsAt?.timeIntervalSince1970 == 1_793_278_800, "Codex: 리셋 시각은 초")
    let weekly = parseCodexLimits(json("""
    {"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":4,"windowDurationMins":10080},"secondary":null}}}
    """), measuredAt: now)!
    check(weekly.windows.map(\.kind) == ["seven_day"], "Codex: primary에 주간만 제공하는 계정")
    check(barText("Codex", limits: weekly, now: now, codex: true) == "Codex  5시간 — · 주간 4%", "Codex: 없는 5시간 창을 0%로 표시하지 않는다")
    check(barText("Claude", limits: nil, now: now) == "Claude  5시간 — · 주간 —", "두 창 모두 없을 때도 줄을 유지")
    let swapped = parseCodexLimits(json("""
    {"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":10080},"secondary":{"usedPercent":20,"windowDurationMins":300}}}
    """), measuredAt: now)
    check(barText("Codex", limits: swapped, now: now, codex: true) == "Codex  5시간 20% · 주간 40%", "Codex: 레거시 응답·창 순서가 바뀌어도 정상")
    check(parseCodexLimits(json(#"{"rateLimitsByLimitId":{"codex_other":{}},"rateLimits":{}}"#), measuredAt: now) == nil,
      "Codex: 다른 모델 버킷을 일반 한도로 쓰지 않는다")
    check(parseCodexLimits(json(#"{"rateLimits":{"limitId":"codex_other"}}"#), measuredAt: now) == nil,
      "Codex: 레거시 다른 버킷도 거른다")
    check(parseCodexLimits(json(#"{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":15}}}"#), measuredAt: now)?.windows.isEmpty == true,
      "Codex: 15분 창을 5시간으로 표시하지 않는다")
    check(parseCodexLimits(json(#"{"rateLimits":{"primary":{"usedPercent":-1,"windowDurationMins":300}}}"#), measuredAt: now)?.windows.isEmpty == true,
      "Codex: 잘못된 비율은 없는 값으로 처리")
    let expired = Limits(windows: [UsageWindow(kind: "five_hour", percentUsed: 90, resetsAt: now)], measuredAt: now)
    check(barParts(expired, now: later, codex: true)[0].used == nil, "Codex: 리셋 뒤 새 조회 전에는 미확인")
    check(menuLines(weekly, now: now, codex: true).contains { $0.text.contains("계정에서 제공하지 않음") }, "Codex: 없는 창은 메뉴에서 설명")

    // 실제 파이프 통신 검증: 가짜 CLI는 initialize → initialized → account/rateLimits/read만 허용한다.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("usagebar-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func server(_ name: String, _ script: String) -> URL {
      let url = directory.appendingPathComponent(name)
      try! ("#!/bin/sh\n" + script).write(to: url, atomically: true, encoding: .utf8)
      try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
      return url
    }
    let ok = server("ok", #"""
    IFS= read -r line
    case "$line" in *'"method":"initialize"'*) ;; *) exit 1 ;; esac
    printf '%s\n' '{"method":"notice","params":{}}' '{"id":1,"result":{}}'
    IFS= read -r line
    case "$line" in *'"method":"initialized"'*) ;; *) exit 2 ;; esac
    IFS= read -r line
    case "$line" in *'account\/rateLimits\/read'*|*'account/rateLimits/read'*) ;; *) exit 3 ;; esac
    printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":4,"windowDurationMins":10080}}}}'
    """#)
    switch readCodex(executable: ok, timeout: 3) {
    case .success(let result): check(result.windows.first?.percentUsed == 4, "Codex 파이프: 초기화·알림 무시·조회·종료")
    case .failure(let error): check(false, "Codex 파이프: \(error)")
    }
    let denied = server("denied", #"""
    IFS= read -r line
    printf '%s\n' '{"id":1,"error":{"code":-1,"message":"denied"}}'
    """#)
    if case .failure(.queryFailed) = readCodex(executable: denied) { check(true, "Codex 파이프: 서버 오류") }
    else { check(false, "Codex 파이프: 서버 오류") }
    let sleeping = server("timeout", "exec /bin/sleep 30\n")
    let start = ProcessInfo.processInfo.systemUptime
    if case .failure(.timedOut) = readCodex(executable: sleeping, timeout: 0.2) { check(true, "Codex 파이프: 응답 없는 서버 시간 제한") }
    else { check(false, "Codex 파이프: 시간 제한") }
    check(ProcessInfo.processInfo.systemUptime - start < 3, "Codex 파이프: 자식 프로세스 종료까지 제한")
    if case .failure(.cliNotFound) = readCodex(executable: nil) { check(true, "Codex CLI 없는 환경") }
    else { check(false, "Codex CLI 없는 환경") }

    if CommandLine.arguments.contains("--preview") {
      _ = NSApplication.shared
      for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
          let rows = [statusRow("Claude", limits: held, now: now), statusRow("Codex", limits: weekly, now: now, codex: true)]
          let width = ceil(rows.map { $0.size().width }.max()!) + 12
          let image = NSImage(size: NSSize(width: width, height: 22))
          image.lockFocusFlipped(true)
          let bounds = NSRect(x: 0, y: 0, width: width, height: 22)
          NSColor.windowBackgroundColor.setFill()
          bounds.fill()
          drawStatusRows(rows, in: bounds)
          image.unlockFocus()
          let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
          try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/preview-\(name).png"))
          check(rows.allSatisfy { $0.size().height <= 11 }, "두 줄 22pt 메뉴 막대 높이: \(name)")
        }
      }
    }

    print(failed == 0 ? "모두 통과" : "\(failed)개 실패")
    exit(failed == 0 ? 0 : 1)
  }
}

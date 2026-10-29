// UsageBar 의 순수 함수(저장값 읽기·글자 만들기·주기 입력)를 확인한다. 실행: ./menubar/test.sh
import Foundation

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
    let bar = barParts(held, now: now).map { "\($0.label) \(percentText($0.used))" }
    check(bar == ["5시간 27%", "주간 71.5%"], "barParts: 5시간·주간만, 순서대로")

    // 리셋이 지난 창은 0%
    let later = parseDate("2026-10-29T10:00:00Z")!
    check(usedOf(held!.windows[0], now: later) == 0, "usedOf: 리셋 지나면 0%")
    check(percentText(43.5) == "43.5%" && percentText(27.0) == "27%", "percentText")

    print(failed == 0 ? "모두 통과" : "\(failed)개 실패")
    exit(failed == 0 ? 0 : 1)
  }
}

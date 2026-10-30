// Codex의 기존 로그인을 쓰는 읽기 전용 app-server 클라이언트.
// thread/start·turn/start를 호출하지 않으며 토큰/인증 파일을 직접 읽지 않는다.
import Foundation
import Darwin

enum CodexReadError: Error, CustomStringConvertible {
  case cliNotFound, launchFailed, timedOut, invalidResponse, queryFailed

  var description: String {
    switch self {
    case .cliNotFound: return "Codex CLI를 찾지 못했습니다. Codex 또는 ChatGPT 앱을 설치하세요"
    case .launchFailed: return "Codex 사용량 조회를 시작하지 못했습니다"
    case .timedOut: return "Codex 사용량 조회 시간 초과 — 다음 갱신 때 재시도합니다"
    case .invalidResponse: return "Codex 사용량 응답을 읽지 못했습니다"
    case .queryFailed: return "Codex 사용량 조회 실패 — Codex 로그인과 네트워크를 확인하세요"
    }
  }
}

// primary가 반드시 5시간인 것은 아니다. 주간 창만 primary에 오는 계정도 있다.
func parseCodexLimits(_ result: [String: Any], measuredAt: Date) -> Limits? {
  let bucket: [String: Any]
  if let buckets = result["rateLimitsByLimitId"] as? [String: Any], !buckets.isEmpty {
    guard let codex = buckets["codex"] as? [String: Any] else { return nil }
    bucket = codex
  } else {
    guard let legacy = result["rateLimits"] as? [String: Any],
          legacy["limitId"] == nil || legacy["limitId"] is NSNull || legacy["limitId"] as? String == "codex"
    else { return nil }
    bucket = legacy
  }
  var seen = Set<String>()
  let windows = ["primary", "secondary"].compactMap { key -> UsageWindow? in
    guard let window = bucket[key] as? [String: Any],
          let minutes = number(window["windowDurationMins"]),
          let used = number(window["usedPercent"]), used.isFinite, used >= 0, used <= 100
    else { return nil }
    let kind: String
    switch minutes {
    case 300: kind = "five_hour"
    case 10080: kind = "seven_day"
    default: return nil
    }
    guard seen.insert(kind).inserted else { return nil }
    let reset = number(window["resetsAt"]).flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
    return UsageWindow(kind: kind, percentUsed: used, resetsAt: reset)
  }
  return Limits(windows: windows, measuredAt: measuredAt)
}

func findCodexExecutable() -> URL? {
  let env = ProcessInfo.processInfo.environment
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  var candidates: [String] = []
  if let override = env["CODEX_CLI_PATH"], override.hasPrefix("/") { candidates.append(override) }
  // Finder에서 실행할 때는 셸의 PATH가 전달되지 않는다.
  for root in ["/Applications", "\(home)/Applications"] {
    candidates += [
      "\(root)/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
      "\(root)/Codex.app/Contents/Resources/codex",
      "\(root)/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
    ]
  }
  candidates += (env["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { "\($0)/codex" }
  candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"]
  return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
}

// 백그라운드 큐에서 호출한다. 조회 한 번마다 연결을 닫아 사용하지 않는 서버를 남기지 않는다.
func readCodex(executable: URL? = findCodexExecutable(), timeout: TimeInterval = 15) -> Result<Limits, CodexReadError> {
  guard let executable else { return .failure(.cliNotFound) }
  let process = Process()
  let input = Pipe(), output = Pipe()
  process.executableURL = executable
  process.arguments = ["app-server"]
  process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
  process.standardInput = input
  process.standardOutput = output
  process.standardError = FileHandle.nullDevice
  // 서버가 먼저 종료해도 파이프 쓰기가 메뉴 막대 앱을 SIGPIPE로 종료시키지 않게 한다.
  _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
  do { try process.run() } catch { return .failure(.launchFailed) }

  let started = ProcessInfo.processInfo.systemUptime
  let deadline = DispatchWorkItem {
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
  }
  DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
  defer {
    try? input.fileHandleForWriting.close()
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
    deadline.cancel()
    try? output.fileHandleForReading.close()
  }

  var buffer = Data()
  func send(_ message: [String: Any]) throws {
    var data = try JSONSerialization.data(withJSONObject: message)
    data.append(0x0a)
    try input.fileHandleForWriting.write(contentsOf: data)
  }
  func receive(id: Int) throws -> [String: Any] {
    while true {
      while let newline = buffer.firstIndex(of: 0x0a) {
        let line = buffer.prefix(upTo: newline)
        buffer.removeSubrange(...newline)
        guard !line.isEmpty else { continue }
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { throw CodexReadError.invalidResponse }
        guard number(message["id"]) == Double(id) else { continue }
        if message["error"] != nil { throw CodexReadError.queryFailed }
        guard let result = message["result"] as? [String: Any] else { throw CodexReadError.invalidResponse }
        return result
      }
      let chunk = output.fileHandleForReading.availableData
      guard !chunk.isEmpty else {
        throw ProcessInfo.processInfo.systemUptime - started >= timeout ? CodexReadError.timedOut : .invalidResponse
      }
      buffer.append(chunk)
      guard buffer.count <= 1_048_576 else { throw CodexReadError.invalidResponse }
    }
  }

  do {
    try send(["id": 1, "method": "initialize", "params": [
      "clientInfo": ["name": "usage_bar", "title": "UsageBar", "version": "0.2.0"],
    ]])
    _ = try receive(id: 1)
    try send(["method": "initialized", "params": [:]])
    try send(["id": 2, "method": "account/rateLimits/read"])
    guard let limits = parseCodexLimits(try receive(id: 2), measuredAt: Date())
    else { return .failure(.invalidResponse) }
    return .success(limits)
  } catch let error as CodexReadError {
    return .failure(error)
  } catch {
    return .failure(.invalidResponse)
  }
}

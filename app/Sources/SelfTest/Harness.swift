import Foundation

/// A tiny assertion harness so the project keeps runnable tests under Command
/// Line Tools (XCTest and swift-testing both require full Xcode). Each `check`
/// records a pass/fail; `Harness.finish()` exits non-zero if anything failed.
final class Harness {
    private var passed = 0
    private var failures: [String] = []

    func check(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
        } else {
            failures.append(name)
            FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
        }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ name: String) {
        check(a == b, "\(name) (\(a) != \(b))")
    }

    /// Prints a summary and terminates the process. Bounded: no loops here.
    func finish() -> Never {
        let total = passed + failures.count
        print("\(passed)/\(total) checks passed")
        exit(failures.isEmpty ? 0 : 1)
    }
}

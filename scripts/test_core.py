#!/usr/bin/env python3
"""Runs the unchanged XCTest test bodies with a tiny assertion shim when Xcode is absent.
No dependency installation. `swift test` remains the standard path on a full Xcode host.
"""
from pathlib import Path
import os, re, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'Tests/LedgerCoreTests/LedgerCoreTests.swift').read_text()
methods = re.findall(r'    func (test\w+)\(\)', source)
shim = '''import Foundation
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) rethrows { let lhs = try a(); let rhs = try b(); if lhs != rhs { fatalError("Equal failed: \\(lhs) != \\(rhs) \\(message)", file: file, line: line) } }
func XCTAssertTrue(_ a: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) rethrows { if try !a() { fatalError("True failed \\(message)", file: file, line: line) } }
func XCTAssertFalse(_ a: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) rethrows { if try a() { fatalError("False failed \\(message)", file: file, line: line) } }
func XCTAssertNil<T>(_ a: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) rethrows { if try a() != nil { fatalError("Nil failed \\(message)", file: file, line: line) } }
func XCTAssertNotNil<T>(_ a: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) rethrows { if try a() == nil { fatalError("NotNil failed \\(message)", file: file, line: line) } }
func XCTAssertThrowsError<T>(_ a: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { _ = try a() } catch { return }; fatalError("Expected error", file: file, line: line) }
'''
# XCTest assertions accept throwing autoclosures without a caller-level try.
# This shim uses rethrows, so insert `try` for the few assertions containing one.
body = source.replace('import XCTest\n', '').replace('@testable import LedgerCore\n', '')
body = re.sub(r'(?<!func )\b(XCTAssert(?:Equal|True|False|Nil|NotNil))\(([^\n;]*?\btry\b[^\n;]*)', r'try \1(\2', body)
with tempfile.TemporaryDirectory(prefix='localledger-test-') as temp:
    d=Path(temp); (d/'Tests.swift').write_text(shim + body)
    calls='\n'.join(('try ' if re.search(r'func '+m+r'\(\) throws', source) else '') + 'suite.'+m+'(); print("PASS '+m+'")' for m in methods)
    (d/'Run.swift').write_text('@main struct Run { static func main() throws { let suite = LedgerCoreTests()\n'+calls+'\nprint("TOTAL '+str(len(methods))+' test groups passed")\n} }')
    env=dict(os.environ, CLANG_MODULE_CACHE_PATH=str(Path(tempfile.gettempdir())/'localledger-clang-cache'))
    cmd=['swiftc','-module-cache-path',str(Path(tempfile.gettempdir())/'localledger-swift-cache'),'-o',str(d/'tests')]+[str(p) for p in sorted((root/'Sources/LedgerCore').glob('*.swift'))]+[str(d/'Tests.swift'),str(d/'Run.swift')]
    subprocess.run(cmd,env=env,check=True)
    subprocess.run([str(d/'tests')],check=True)

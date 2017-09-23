//
//  ShellTests.swift
//  ShellT
//
//  Created by Bernardo Breder on 09/01/17.
//
//

import XCTest
@testable import Shell

class ShellTests: XCTestCase {
    
    func testEcho() throws {
        XCTAssertEqual("A", try Shell("echo", ["A"]).start().output.first)
        XCTAssertEqual("/bin/echo", try Shell("/usr/bin/which", ["echo"]).start().output.first)
        XCTAssertEqual("A B", try Shell("/bin/echo", ["A","B"]).start().output.first)
        XCTAssertEqual("A", try Shell("echo", ["A"]).start().output.first)
        XCTAssertEqual(2, try Shell("swift", ["-version"]).start().output.count)
        _ = try? Shell("/none").start()
        _ = try? Shell("none").start()
    }
    
}

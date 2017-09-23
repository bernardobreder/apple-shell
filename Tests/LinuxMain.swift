//
//  ShellTests.swift
//  Shell
//
//  Created by Bernardo Breder.
//
//

import XCTest
@testable import ShellTests

extension ShellTests {

	static var allTests : [(String, (ShellTests) -> () throws -> Void)] {
		return [
			("testEcho", testEcho),
		]
	}

}

XCTMain([
	testCase(ShellTests.allTests),
])


import XCTest

let suite = MacInspectionStateTests.defaultTestSuite
suite.run()
guard let result = suite.testRun, result.executionCount >= 5, result.hasSucceeded else { fatalError("Inspection state checks failed") }

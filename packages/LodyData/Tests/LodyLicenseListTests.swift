import XCTest
import LodyData

final class LodyLicenseListTests: XCTestCase {
  func testTheGeneratedCatalogDecodesWithSharedTexts() throws {
    let json = #"""
    {"packages":[
      {"name":"Lody for Mac","license":"AGPL-3.0-only","url":"https://github.com/Innei/lody-ios","firstParty":true,"text":0},
      {"name":"Litext","license":"MIT","text":1},
      {"name":"zod","version":"3.25.76","license":"MIT","text":1},
      {"name":"broken","license":"MIT","text":9}
    ],"texts":["AGPL text","MIT text"]}
    """#
    let list = try LodyLicenseList.decode(Data(json.utf8))
    XCTAssertEqual(list.packages.map(\.name), ["Lody for Mac", "Litext", "zod", "broken"])
    XCTAssertEqual(list.packages.first?.firstParty, true)
    XCTAssertEqual(list.packages[2].version, "3.25.76")
    XCTAssertEqual(list.text(list.packages[2]), "MIT text")
    XCTAssertEqual(list.text(list.packages[3]), "")
    XCTAssertEqual(list.entry("Litext")?.license, "MIT")
  }

  func testAMissingResourceIsAnEmptyList() {
    XCTAssertTrue(LodyLicenseList.load(from: nil).packages.isEmpty)
  }
}

import Foundation

let base = HTMLPreviewResource.url(path: "docs/intro page.html", host: "preview")
assert(base.absoluteString == "lody-preview://preview/__lody_files/docs/intro%20page.html")
assert(!URL(string: "/assets/app.js", relativeTo: base)!.absoluteURL.path.hasPrefix(HTMLPreviewResource.filePrefix))
let relative = URL(string: "../assets/app.js?v=1", relativeTo: base)!.absoluteURL
assert(HTMLPreviewResource.path(relative, documentPath: "docs/intro page.html") == "assets/app.js")
let absolute = HTMLPreviewResource.url(path: "/Users/example/project/demo.html", host: "preview")
let image = URL(string: "./image.png", relativeTo: absolute)!.absoluteURL
assert(HTMLPreviewResource.path(image, documentPath: "/Users/example/project/demo.html") == "/Users/example/project/image.png")
for value in ["http://localhost:5173/a", "http://127.0.0.1/a", "http://[::1]/a", "https://test.localhost/a"] {
  assert(HTMLPreviewResource.code(URL(string: value)!) == "local_service_unavailable")
}
assert(HTMLPreviewResource.code(URL(string: "https://cdn.example.com/app.js")!) == "resource_failed")
assert(HTMLPreviewResource.code(URL(string: "file:///Users/example/a.png")!) == "local_file_unavailable")
assert(HTMLPreviewResource.safeReference("https://user:secret@example.com/a?token=secret#secret") == "https://example.com/a")
assert(HTMLPreviewResource.safeReference("./a.png?token=secret") == "./a.png")
print("PASS: relative/absolute paths, loopback service classification and diagnostic credential redaction")

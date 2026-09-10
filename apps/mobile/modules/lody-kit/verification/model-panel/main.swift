import UIKit
import MetalKit

let shaderURL = Bundle.main.url(forResource: "LodyKitShaders", withExtension: "bundle")!
let shaderBundle = Bundle(url: shaderURL)!
let device = MTLCreateSystemDefaultDevice()!
let library = try device.makeDefaultLibrary(bundle: shaderBundle)
precondition(library.makeFunction(name: "particleVertex") != nil && library.makeFunction(name: "particleFragment") != nil, "Packaged Metal library must expose the renderer entry points")
let panel = ChatComposerModelPanel()
panel.loadViewIfNeeded()
let options = try JSONDecoder().decode(ChatComposerOptions.self, from: Data(#"{"modelId":"gpt","models":[{"id":"gpt","title":"GPT"}],"effort":"medium","efforts":[{"id":"medium","title":"Medium"},{"id":"ultra","title":"Ultra"}]}"#.utf8))
panel.render(options)
let slider = panel.view.subviews.first { $0.accessibilityIdentifier == "composer-effort-slider" } as! UIControl
let model = panel.view.subviews.first { $0.accessibilityIdentifier == "composer-model-menu" } as! UIButton
precondition(model.configuration?.subtitle == "GPT" && model.configuration?.title == "Medium ›")
panel.render(ChatComposerOptions())
precondition(slider.isHidden, "Models without effort choices must hide the slider")
precondition(model.menu?.children.count == 1, "Replacing options must clear stale model choices")
print("PASS: extracted model panel renders choices and clears unavailable controls")
let fast = panel.view.subviews.first { $0.accessibilityIdentifier == "composer-fast" } as! UIButton
precondition(fast.isHidden, "Unsupported agents must not show Fast")
var fastOptions = options
fastOptions.fast = false
panel.render(fastOptions)
precondition(!fast.isHidden && !fast.accessibilityTraits.contains(.selected))
var fastChanged: Bool?
panel.onFast = { fastChanged = $0 }
panel.perform(NSSelectorFromString("toggleFast"))
precondition(fastChanged == true, "Fast must report the next value without changing effort")
fastOptions.fast = true
panel.render(fastOptions)
precondition(fast.accessibilityTraits.contains(.selected))
precondition(fast.configuration?.image != nil, "Fast must use a button configuration so symbol replace can run")
if #available(iOS 26.0, *) {
  precondition(fast.configuration?.symbolContentTransition != nil, "Fast must replace bolt and bolt.fill")
}
panel.render(ChatComposerOptions())
fastChanged = nil
panel.perform(NSSelectorFromString("toggleFast"))
precondition(fastChanged == nil, "Unavailable Fast must not emit a choice")
print("PASS: Fast availability, toggle callback and selected state")

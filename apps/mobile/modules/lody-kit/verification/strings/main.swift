import Foundation

let single = LodyStrings.substitute("{a} and {b} and {a}", ["a": "1", "b": 2])
assert(single == "1 and 2 and 1", single)

let missing = LodyStrings.substitute("hi {name}", ["other": "x"])
assert(missing == "hi {name}", missing)

let noRescan = LodyStrings.substitute("{outer}", ["outer": "{inner}", "inner": "no"])
assert(noRescan == "{inner}", noRescan)

let selfValue = LodyStrings.substitute("hi {name}", ["name": "{name}"])
assert(selfValue == "hi {name}", selfValue)

let extra = LodyStrings.substitute("plain", ["unused": "x"])
assert(extra == "plain", extra)

let unbalanced = LodyStrings.substitute("a {b c", ["b": "x"])
assert(unbalanced == "a {b c", unbalanced)

// Foundation resolves the plural variation and the numeric substitution; the
// remaining named placeholders stay for the single substitution pass.
let one = LodyStrings.plural("Add %lld item to {target}", 1, ["target": "chat"])
assert(one == "Add 1 item to chat", one)
let other = LodyStrings.plural("Add %lld items to {target}", 12, ["target": "chat"])
assert(other == "Add 12 items to chat", other)

print("PASS: single-pass substitution, missing and extra variables, plural numbers")

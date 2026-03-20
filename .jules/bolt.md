## 2024-03-17 - Cached String Regex Matching in Hot Paths
**Learning:** In Lua, calling string pattern matching (e.g. `name:match("^([^%-]+)")`) inside loops and highly accessed lookup pathways, like `StripRealmName` which gets called hundreds of times during UI rendering and comparisons, incurs significant overhead. Caching the result for immutable entities (like player names) yields ~3x speedup.
**Action:** When performing regex on frequent string identifiers that never mutate, introduce a simple table-based local cache instead of evaluating the pattern each time.

## 2026-03-20 - Plain String Matching Bypass
**Learning:** In Lua, calling `string:find` to check for substrings containing magic characters like `-` invokes the pattern matching engine, causing unnecessary pattern compilation overhead. This is especially impactful in hot paths like `NamesMatch` and string normalizations.
**Action:** When performing simple substring presence checks without regex intent, pass `1, true` as the third and fourth arguments to `string:find` to bypass pattern compilation entirely, e.g. `string:find("-", 1, true)`.

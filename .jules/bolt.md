## 2024-03-17 - Cached String Regex Matching in Hot Paths
**Learning:** In Lua, calling string pattern matching (e.g. `name:match("^([^%-]+)")`) inside loops and highly accessed lookup pathways, like `StripRealmName` which gets called hundreds of times during UI rendering and comparisons, incurs significant overhead. Caching the result for immutable entities (like player names) yields ~3x speedup.
**Action:** When performing regex on frequent string identifiers that never mutate, introduce a simple table-based local cache instead of evaluating the pattern each time.

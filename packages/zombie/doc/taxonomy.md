# `pkg:zombie`: Phase 1 Taxonomy (Top-Level Declarations)

> [!NOTE]
> This document defines the **Phase 1 (MVP)** scope of `pkg:zombie`, focusing strictly on **Top-Level Declarations**.
> For the future Phase 2/3 taxonomy covering internal class members, constructors, and enum constants, see [taxonomy_phase2.md](taxonomy_phase2.md).

---

## 1. Phase 1 Core Scope & Invariants

Phase 1 operates at the **Top-Level AST Declaration** granularity (`CompilationUnit.declarations`):

* **Covered Top-Level Nodes**:
  * Classes (`ClassDeclaration`)
  * Top-level functions (`FunctionDeclaration`)
  * Whole enums (`EnumDeclaration`)
  * Mixins (`MixinDeclaration`)
  * Extensions (`ExtensionDeclaration`)
  * Extension types (`ExtensionTypeDeclaration`)
  * Type aliases / typedefs (`TypeAlias`)
  * Top-level variables (`TopLevelVariableDeclaration`)
* **Explicitly Deferred to Phase 2/3**:
  * Internal methods, fields, and constructors inside reachable classes.
  * Individual enum constants (`EnumConstantDeclaration`) inside reachable enums.

---

## 2. Phase 1 Classification Matrix

<!-- mdformat off(prevent table wrapping) -->
| Scenario / Code Pattern | Location | Exported in `lib/*.dart`? | Reachable from `lib/`, `bin/`, `tool/`, `example/`? | Reachable from `test/`? | Classification | Recommended Action |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **Unexported Top-Level Declaration** (class, function, enum, mixin, typedef) | `lib/src/` | ❌ No | ❌ No | ❌ No | **Pure Zombie** | Delete entire declaration |
| **Tested Zombie (Zero Production Uses, Test-Only)** | `lib/src/` | ❌ No | ❌ No | ✅ Yes | **Tested Zombie** | **Delete declaration AND remove orphan test blocks** |
| **Exported Top-Level Declaration** | `lib/` or `lib/src/` | ✅ Yes | ❌ No | ❌ No | **Public API** (Not Zombie) | Preserve (external consumer contract) |
| **Tool / Example Only Usage** | `lib/src/` | ❌ No | ✅ Yes | N/A | **Tool/Example Live** | Preserve |
| **Unused Top-Level Declaration in `tool/` or `example/`** | `tool/` or `example/` | ❌ No | ❌ No | ❌ No | **Zombie** | Delete entire declaration |
| **Annotated Entrypoint** (`@pragma('vm:entry-point')`, `@Preview`, `@JS`) | Any | ❌ No | ❌ No | ❌ No | **Exempt / Alive** | Preserve |
| **Suppressed via Custom Comment** | Any | ❌ No | ❌ No | ❌ No | **Ignored** | Skip |
<!-- mdformat on -->

---

## 3. Dual-Pass Reachability Engine

```mermaid
flowchart TD
    subgraph Pass1 ["Pass 1: Production Reachability Graph"]
        P_Roots["Roots: lib/*.dart exports, bin/*.dart, tool/*.dart, example/*.dart"]
        P_BFS["BFS Graph Traversal"]
        P_Live["Set<Declaration> PRODUCTION_LIVE"]
    end

    subgraph Pass2 ["Pass 2: Test Reachability Graph"]
        T_Roots["Roots: test/**/*_test.dart main()"]
        T_BFS["BFS Graph Traversal"]
        T_Live["Set<Declaration> TEST_REACHABLE"]
    end

    subgraph Classification ["Phase 1 Top-Level Classification"]
        D1{"In PRODUCTION_LIVE?"}
        D1 -->|Yes| Live["ALIVE (Production Code)"]
        D1 -->|No| D2{"In TEST_REACHABLE?"}
        D2 -->|No| PureZombie["🧟 PURE ZOMBIE (Delete declaration)"]
        D2 -->|Yes| TestedZombie["🧟 TESTED ZOMBIE (Delete declaration + Delete orphan tests)"]
    end

    Pass1 --> D1
    Pass2 --> D2
```

---

## 4. Phase 1 Concrete Examples & Test Cases

### Example 1: Dead Unexported Top-Level Function (Pure Zombie)
```dart
// lib/src/utils.dart (NOT exported in lib/my_package.dart)
String calculateLegacyHash(String input) => input.trim(); // 🧟 PURE ZOMBIE
```
* **Analysis**: `calculateLegacyHash` is not in `lib/*.dart` export namespace and has 0 inbound reference edges anywhere in the package.
* **Remediation**: Delete `calculateLegacyHash`.

---

### Example 2: Dead Unexported Top-Level Class (Pure Zombie)
```dart
// lib/src/internal_cache.dart (NOT exported in lib/my_package.dart)
class InternalCache {
  final Map<String, dynamic> _store = {};
  void put(String k, dynamic v) => _store[k] = v;
}
```
* **Analysis**: `InternalCache` has 0 type, constructor, or identifier references across all files.
* **Remediation**: Delete the entire `InternalCache` class.

---

### Example 3: Tested Zombie (Dead Top-Level Class + Dead Unit Test)
```dart
// lib/src/old_parser.dart (NOT exported in lib/my_package.dart)
class OldParser {
  String parse(String raw) => raw.toLowerCase(); // 🧟 TESTED ZOMBIE: 0 production callers!
}

// test/old_parser_test.dart
void main() {
  test('OldParser parses correctly', () {
    final parser = OldParser();
    expect(parser.parse('FOO'), 'foo'); // ⚠️ ORPHAN TEST
  });
}
```
* **Analysis**: `OldParser` is unexported and has 0 callers in `lib/`, `bin/`, `tool/`, `example/`. It is invoked only in `test/old_parser_test.dart`.
* **Remediation**:
  1. Flag `OldParser` as `tested_zombie`.
  2. Identify orphan test call site: `test/old_parser_test.dart:3:3` (`test('OldParser parses correctly', ...)`).
  3. Delete `OldParser` from `lib/src/old_parser.dart` AND delete the corresponding `test(...)` block from `test/old_parser_test.dart`.

---

### Example 4: Exported Top-Level Class (Protected Public API)
```dart
// lib/src/client.dart (Exported via `export 'src/client.dart'` in lib/my_package.dart)
class MyClient {
  void connect() {}
}
```
* **Analysis**: In an open package, `MyClient` is re-exported at `lib/my_package.dart`.
* **Remediation**: Do NOT flag as Zombie.

---

### Example 5: Tool / Example Only Usage (Tool-Live)
```dart
// lib/src/generator_config.dart (NOT exported in lib/my_package.dart)
class GeneratorConfig {
  static const defaultOutputDir = 'build/generated'; // Used ONLY in tool/generate.dart
}
```
* **Analysis**: Unexported, but referenced by a script in `tool/generate.dart`.
* **Remediation**: Preserve (Tool-Live).

---

## 5. Custom Comment Suppression Syntax

> [!IMPORTANT]
> **Anti-Collision Rule**: We must **NOT** co-opt Dart's standard `// ignore: ...` or `// ignore_for_file: ...` syntax.
> The Dart analyzer treats unrecognized lint codes in `// ignore:` as diagnostic errors (`unrecognized_error_code`).

<!-- mdformat off(prevent table wrapping) -->
| Directive | Scope | Example Usage |
| :--- | :--- | :--- |
| `// zombie:ignore` | Suppresses the immediately following top-level declaration | `// zombie:ignore`<br>`class DynamicPluginTarget { ... }` |
| `// zombie:ignore_for_file` | Suppresses all zombie findings within the current `.dart` file | Top of file:<br>`// zombie:ignore_for_file` |
<!-- mdformat on -->

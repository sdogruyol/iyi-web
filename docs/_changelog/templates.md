### Changed

- **Breaking:** `<%= expr %>` in a template rendered with `render` prints
  `expr.to_s` HTML-escaped (`&`, `<`, `>`, `"`, `'`, as `HTML.escape`). The
  template's own text is printed as written. Migration: drop
  `HTML.escape(...)` inside `<%= %>` (it would escape twice), and wrap every
  `<%= %>` that prints markup on purpose in `raw(...)`: HTML the program
  built, `csrf_tag(env)`, or a page a helper rendered in iyi code.
- **Breaking:** a layout's `content` and `yield_content` answer `SafeHTML`
  instead of `String`; `<%= content %>` and `<%= yield_content "key" %>`
  print as before, String methods on them need `.to_s` first.
- `render` written inside a template answers `SafeHTML`, so
  `<%= render "_partial.eiy" %>` is not escaped a second time; written in iyi
  code it still answers `String`.
- Templates are translated by iyi-web's own compile-time program,
  `iyi_web/templates/process.iyi`, instead of std/eiy's `eiy/process`; tags,
  `<%- -%>` trimming, comments and error positions are unchanged.

### Added

- `raw(value)` (in `iyi_web/dsl` and `iyi_web/templates`): `value.to_s` as
  `SafeHTML`, printed by `<%= %>` without escaping.
- `SafeHTML` and `HTMLBuffer` in `iyi_web/templates`.
- `docs/templates.md`, with autoescape and the migration from 0.5.
- `examples/templates.iyi` has a `/search` page that prints the visitor's
  query in an attribute and a heading, and a `raw` rating.

### Removed

- **Breaking:** `iyi_web/templates` (and through it `iyi_web/dsl`) no longer
  re-exports `std/eiy`; a program that names `Eiy` imports `std/eiy` itself.
  `ContentBlocks#capture` yields an `HTMLBuffer`, not an `Eiy::Buffer`.

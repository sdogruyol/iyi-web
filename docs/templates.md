# Templates

```iyi
import web/iyi_web/dsl::*

get "/profile" do |env|
  name = env.params.query["name"]? || "stranger"
  render "views/profile.eiy", "views/layout.eiy"
end
```

`views/profile.eiy`:

```erb
<% content_for "title" do %>Profile of <%= name %><% end -%>
<h1>Hello, <%= name %></h1>
```

`views/layout.eiy`:

```erb
<!DOCTYPE html>
<html>
<head><title><%= yield_content "title" %></title></head>
<body><%= content %></body>
</html>
```

`curl -G localhost:3000/profile --data-urlencode 'name=<script>alert(1)</script>'`
prints

```html
<!DOCTYPE html>
<html>
<head><title>Profile of &lt;script&gt;alert(1)&lt;/script&gt;</title></head>
<body><h1>Hello, &lt;script&gt;alert(1)&lt;/script&gt;</h1>
</body>
</html>
```

Templates use iyi's `.eiy` format: `<%= expr %>` prints a value and
`<% code %>` runs iyi code. They are compiled into the program, and see the
local variables where `render` is written: a route block, or a method, as a
controller's `def show(name : String) : String` with `render` inside.

- `render "view.eiy"` returns the rendered text. `render "view.eiy",
  "layout.eiy"` renders the view, then the layout with the view as `content`.
- `content_for "key" do ... end` captures markup in the view, and
  `yield_content "key"` prints it in the layout; a key never captured prints
  nothing.
- A template path is relative to the file that calls `render`, or, for a
  template rendered inside another template, to that template.
- A missing template, a tag that is never closed, or an error in a tag's
  code stops the build, naming the template's line and column:

  ```
  views/_note.eiy: unterminated <%= tag at line 2, column 3
  ```

## Autoescape

`<%= expr %>` prints `expr.to_s` HTML-escaped: `&`, `<`, `>`, `"` and `'`
become `&amp;`, `&lt;`, `&gt;`, `&quot;` and `&#39;`, exactly what
`HTML.escape` from `std/html` does. A value from a request, a database or a
file prints as text in an element's content and in a quoted attribute
value, and only there (see [Where escaping is not enough](#where-escaping-is-not-enough)):

```erb
<input name="q" value="<%= query %>">
<h1>Books matching <%= query %></h1>
```

```sh
$ curl -G localhost:3000/search --data-urlencode 'q=<script>alert(1)</script>'
<form action="/search"><input name="q" value="&lt;script&gt;alert(1)&lt;/script&gt;"><button>Search</button></form>
<h1>Books matching &lt;script&gt;alert(1)&lt;/script&gt;</h1>
```

The template's own text is never escaped: `<b>Hello</b>` in a view is
printed as written. So is the text of `<%% ... %>`.

### Where escaping is not enough

HTML-escaping keeps a value from closing the element or the quoted
attribute it is printed in. It says nothing about what the value means
once it is there, and these places mean something:

- **A URL attribute** (`href`, `src`, `action`, `formaction`, ...):
  `<a href="<%= url %>">` with `url` = `javascript:alert(1)` runs script
  on a click, and none of its characters needs escaping. Check a URL
  from outside against an allow-list of schemes (`https:`, `http:`,
  `mailto:`) or build it yourself from a path you own, and print the
  checked value.
- **An unquoted attribute**: `<input value=<%= query %>>` with
  `query` = `x onfocus=alert(1) autofocus` adds attributes, because a
  space, `=` or a backtick are not escaped. Always quote attribute values,
  with `"` or `'`.
- **An event-handler attribute** (`onclick`, `onload`, any `on*`):
  the browser decodes the attribute's entities before it runs the code,
  so in `onclick="greet('<%= name %>')"` the `&#39;` is a `'` again
  and `name` = `');alert(1);('` breaks out of the string. Never print a
  value into one.
- **Inside `<script>` or `<style>`**: their text is not HTML, entities are
  not decoded, and `var n = <%= count %>;` with `count` =
  `1;alert(1)` needs no quote at all to run. Never print a value into
  either.

To hand data to script, print it as JSON in a quoted `data-` attribute,
where autoescape is the right escaping, and read it from the element:

```erb
<div id="chart" data-points="<%= JSON.to_json(points) %>"></div>
<script>
  const points = JSON.parse(document.getElementById("chart").dataset.points)
</script>
```

A `<script type="application/json">` block works too, but not through
`<%= %>`: entities are not decoded there, so it needs `raw` and JSON with
every `<` written as `\u003c`, so the data can never contain `</script>`.

### Markup that is already HTML: `raw` and `SafeHTML`

Escaping is decided by the value's type. A `String` is text and is always
escaped. A `SafeHTML` is markup and is printed as is. `raw(value)` turns any
value's `to_s` into one:

```iyi
# Built by the program from nothing a request sent.
def stars(rating : Int32) : String
  "<p class=\"stars\">" + "&#9733;" * rating + "&#9734;" * (5 - rating) + "</p>"
end
```

```erb
<%= raw(stars(book.rating)) %>
```

`raw` is the one way past autoescape, so give it markup your program built
or trusts, never a request's text. It comes with `import iyi_web/dsl::*`;
a file that imports `iyi_web/templates` by name lists it there:
`import iyi_web/templates::{render, raw}`.

When a value is either, the choice is made per value:

```erb
<%= trusted ? raw(html) : html %>
```

### What is markup already

Everything a render hands a template is `SafeHTML`, so markup is escaped
once, where its values were printed, and never again:

- a layout's `content`, the rendered view;
- `yield_content "key"`, what a `content_for` block printed;
- `render` written inside a template, as `<%= render "_row.eiy" %>`.

`render` written in iyi code, a route or a method, still answers a `String`:
the page a route returns. That String is text to any template that prints
it, like every other String. Prefer rendering a partial from the template
itself; when a helper renders one, print its result with `raw`:

```iyi
def card(book : Book) : String
  render "views/_card.eiy"
end
```

```erb
<%= raw(card(book)) %>
```

`SafeHTML` lives in `iyi_web/templates` (`to_s`, `empty?`, `==`), for a
helper that wants to say in its signature that it answers markup.

### Moving from 0.5

Before autoescape, `<%= %>` printed `to_s` as is and templates escaped with
`HTML.escape`. Now:

- Drop `HTML.escape(...)` inside `<%= %>`: the value would be escaped twice
  and `&` would print as `&amp;amp;`.
- Wrap in `raw(...)` every `<%= %>` that prints markup on purpose: HTML your
  program built, `csrf_tag(env)`, or a page a helper rendered in iyi code.
- A layout's `content` and `yield_content` are `SafeHTML` now, not `String`.
  Printing them with `<%= %>` is unchanged; code that called String methods on
  them calls `.to_s` first.

## How it works

`render` is a macro. At compile time it runs `iyi_web/templates/process.iyi`,
a small iyi program shipped with iyi-web that reads the template with
`std/eiy`'s lexer and writes the iyi source that renders it, which the macro
splices where `render` is written. Text becomes `print("...")` and each
`<%= expr %>` becomes `output(expr)` on an `HTMLBuffer`, whose `output`
escapes unless the value is `SafeHTML`. `std/eiy`'s own processor prints both
through one `print`, so nothing after it could tell the two apart; the tags,
`<%- -%>` trimming, comments and error positions are otherwise `std/eiy`'s.

The helper is compiled once and cached with the compiler's other macro
programs, in this repository and when iyi-web is a dependency fetched with
`iyi get`. It replaces `std/eiy`'s processor, so a program that renders
through iyi-web runs one compile-time program, as before.

# Installation

## Requirements

[iyi](https://iyi-lang.com) 0.21.0 or later: `spawn(unit: :new)`, the pool
every connection is served on (0.20 spelled it `spawn_parallel`, which 0.21.0
removed), the `@[Share(serial: workers, crossing: ...)]` mark every
registration carries, so a refusal is made on your line and names both ways
past it, and `@[Unsafe("...")]` above a `module` header (SPEC.md III.13),
which every iyi-web module that handles raw memory carries and 0.20.x
refuses.
TLS (`std/tls`'s server), the streaming compressor (`std/compress`'s
`Deflater`) and the media-type table (`std/mime`) arrived in 0.18.0.

## Adding iyi-web to a project

iyi-web is an iyi module. Add it to your project's `iyi.mod`:

```sh
iyi get github.com/sdogruyol/iyi-web
```

This fetches the latest release, records it in `iyi.sum` and writes one line to
`iyi.mod`:

```
require github.com/sdogruyol/iyi-web v0.6.0
```

Files then name iyi-web's modules by their full path. One `import` line loads
a module and brings its names into scope:

```iyi
import github.com/sdogruyol/iyi-web/iyi_web/dsl::*
```

### A short name

The examples in these docs write the path once, in `iyi.mod`, under the short
name `web`. Pass `--as web` when adding iyi-web, or run the same command in a
project that already requires it:

```sh
iyi get github.com/sdogruyol/iyi-web --as web
```

or add ` as web` to the `require` line by hand:

```
require github.com/sdogruyol/iyi-web v0.6.0 as web
```

`web/iyi_web/...` then means `github.com/sdogruyol/iyi-web/iyi_web/...`:

```iyi
import web/iyi_web/dsl::*
import web/iyi_web/router::{Router}
```

### Versions

`iyi get -u` moves to the latest release and
`iyi get github.com/sdogruyol/iyi-web@v0.6.0` to a given one; both keep the
short name. `iyi get -u --check` says whether a newer release exists without
changing anything.

iyi reads `iyi.mod` from the directory of the file being built, so keep the
entry file, and every `*_test.iyi` that uses iyi-web, beside it. Modules of
your own can live in subdirectories.

## Quick start

The quickest start is the `iyi-web` command ([installing it](cli.md#installing)),
which writes a project whose test passes out of the box and serves it,
rebuilding on every save:

```sh
iyi-web new app           # --api for a JSON API, --full for pages and assets
cd app
iyi test
iyi-web dev
```

By hand, start a project, add iyi-web, and save this program as `app.iyi`:

```iyi
module app

import web/iyi_web/dsl::*

get "/" do |env|
  "Hello, world!"
end

run
```

```sh
mkdir app && cd app
iyi init app
iyi get github.com/sdogruyol/iyi-web --as web
iyi run app.iyi
```

`iyi init` writes `iyi.mod` together with a starter `main.iyi`, `greet.iyi`
and `main_test.iyi`, which can be deleted.

The server listens on http://localhost:3000. Pass `-p 8080` or set `PORT` to
use another port.

The examples in the guide extend this program. Each goes between the
`import` line and `run`, and any `import` lines it shows go at the top of
the file. The [tutorial](tutorial.md) builds a whole API step by step.

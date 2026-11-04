# The `iyi-web` command

`iyi-web` starts a project and runs it while you work on it. Everything else
stays `iyi`'s: `iyi test`, `iyi build --release`, `iyi get -u`.

```sh
iyi-web new shop               # write a new application into ./shop
cd shop
iyi test                       # its test passes out of the box
iyi-web dev                    # serve it, rebuild and restart on every save
```

## Installing

The command lives in this repository, in `cmd/`. Build it once and put it
on your `PATH`:

```sh
git clone https://github.com/sdogruyol/iyi-web
cd iyi-web
iyi build --release cmd/iyi_web.iyi -o bin/iyi-web
```

`bin/iyi-web` (`bin\iyi-web.exe` on Windows) is the whole program. It needs
`iyi` on the `PATH` for `dev`, or the compiler named by the `IYI`
environment variable.

## `iyi-web new`

```sh
iyi-web new DIR [--api | --full] [--web-path PATH]
```

Writes a new application into `DIR`, creating it. A directory that already
holds anything is refused before a single file is written. The last segment
of `DIR` is the project's name and has to be a module path: a lower-case
letter, then lower-case letters, digits, `_` and `-` (`my-shop` yes, `My
Shop` no).

Every project has the same shape, the one [Testing](testing.md)
describes: the routes are in their own module, as a function that builds a
`Router`; `app.iyi` mounts it and serves it, and `app_test.iyi` sends it
requests in-process, without opening a port.

```
shop/
  iyi.mod            requires iyi-web as `web`
  app.iyi            the program: mounts the routes and runs
  routes/home.iyi    the routes
  app_test.iyi       in-process tests
  README.md
  .gitignore         build products and .iyi-web/
```

`iyi.mod` requires the current iyi-web release under the short name `web`:

```
module shop

require github.com/sdogruyol/iyi-web v0.5.1 as web
```

The first `iyi test` or `iyi build` fetches it and writes `iyi.sum`.
`iyi get -u` moves it to the latest release later.

### Kinds

| Flag | What `routes/` holds | Extra files |
|---|---|---|
| (none) | `home.iyi`: `GET /` and `GET /hello/:name` | |
| `--api` | `notes.iyi`: a JSON CRUD over an in-memory store, as [typed routes](typed-routes.md). `path: Int32` reads the `:id` capture (a word there is a `422`), `body:` reads the JSON body into a type checked by `Validate` (`400`, `415` and `422` answers that name the field), `response:` writes `derive serializable` types, missing notes are a JSON `404`. The notes are in a [`Store`](state.md), so it serves on every core. | |
| `--full` | `pages.iyi`: `GET /` and `GET /about`, rendered from views inside a layout | `views/layout.eiy`, `views/index.eiy`, `views/about.eiy`, `public/css/app.css`, `public/robots.txt`; `app.iyi` sets `public_folder "public"` |

Each kind's `app_test.iyi` covers its own routes: the `--api` one creates a
note, refuses a blank title, a wrong type and a body that does not parse,
deletes it twice to get `204` then `404`, and gets `422` for `/notes/abc`.

### Building against a local iyi-web

`--web-path PATH` adds a `replace` line, so the project builds against the
iyi-web checkout at `PATH` instead of the release:

```sh
iyi-web new shop --web-path ~/src/iyi-web
```

```
replace github.com/sdogruyol/iyi-web => /home/me/src/iyi-web
```

That is how to try an unreleased iyi-web in a real project, or work on
iyi-web and an application side by side. `PATH` must hold iyi-web
(`iyi_web/dsl.iyi`); it is written absolute. Delete the line to go back to
the release.

## `iyi-web dev`

```sh
iyi-web dev [ENTRY] [--watch DIR]... [--interval MS] [-- ARGS...]
```

Builds `ENTRY` (`app.iyi` unless named), runs it, and watches the project.
When you save a change it builds again; when the build succeeds it stops
the running program and starts the new one.

A session on Windows: an edit to the greeting, a syntax error, its fix, and
a file dropped into `public/` (the requests between were `curl`s):

```
> iyi-web dev -- -p 3912
[dev] watching C:\Users\dogru\tmp-tooling\devdemo every 500 ms
[dev] building app.iyi
[dev] built in 4804 ms
[dev] started app.iyi (pid 9956)
[development] iyi-web is ready to lead at http://localhost:3912
GET / 200 0.1139ms
[dev] changed routes\home.iyi
[dev] building app.iyi
[dev] built in 3385 ms
[dev] started app.iyi (pid 15400)
[development] iyi-web is ready to lead at http://localhost:3912
GET / 200 0.1056ms
[dev] changed routes\home.iyi
[dev] building app.iyi
In routes\home.iyi:23:1
Error: expecting 'end' to close the def that began at line 9, not the end of the file
[dev] build failed; the previous build keeps running
GET / 200 0.0675ms
GET /hello/ada 200 0.1309ms
[dev] changed routes\home.iyi
[dev] building app.iyi
[dev] built in 4443 ms
[dev] started app.iyi (pid 736)
[development] iyi-web is ready to lead at http://localhost:3912
GET / 200 0.1626ms
[dev] changed public\a.txt
[dev] public files are served from disk: nothing to rebuild
GET /a.txt 200 0.6178ms
```

Ctrl-C then ends both, the program first:

```
[development] iyi-web is going to take a rest!
[dev] stopping
```

- **A failed build keeps the last good one running.** The compiler's
  message is printed and the server goes on answering with the previous
  build until the next save compiles.
- **What is watched.** Under the entry's directory: `*.iyi`, `*.eiy`,
  `*.ecr` and `iyi.mod` - a change rebuilds - and everything under
  `public/`, which is reported and nothing more, since static files are read
  from disk on every request. Directories whose names start with `.` (`.git`,
  `.iyi-web`) are not walked. `--watch DIR` adds another directory, such as
  a local iyi-web checkout used through `replace`.
- **Arguments.** Everything after `--` goes to the program untouched:
  `iyi-web dev -- -p 8080 -b 127.0.0.1`.
- **Where it runs.** The program runs in the entry's directory, on the same
  terminal, so its log lines are interleaved with `[dev]`'s.
- **Stopping.** Ctrl-C (or `TERM`) stops the program, then `dev`. The
  program sees Ctrl-C itself too and stops the way `run` always does,
  draining its requests.
- **Builds** go to `.iyi-web/dev/` beside the entry (the scaffold's
  `.gitignore` lists it). They alternate between two executables, because
  Windows will not overwrite a program that is running; the new one is
  written while the old one still serves.

### How changes are noticed

std has no file-change notification, so `dev` walks the project every
`--interval` milliseconds (500) and compares modification times and sizes.
File times are whole seconds, so two saves within one second that keep the
size - fixing a typo, say - would look like no change; `dev` therefore also
keeps the text of every file modified within the last second and compares
that. A walk over a project of a few hundred files costs well under a
millisecond per hundred.

Debug builds are what `dev` makes: an incremental build of a small
application takes a few seconds. Build for release with `iyi build
--release` when you deploy.

### When the program stops by itself

A program that exits - a panic at startup, a port already in use - is
reported with its exit code, and `dev` waits for the next save to build and
start it again.

## `iyi-web version`, `iyi-web help`

`version` prints the iyi-web release the command scaffolds against; `help`
prints the usage above. A usage error prints its reason and exits with
status 2.

# Static files

Files under `./public` are served for `GET` and `HEAD` requests before
routing, so a file takes precedence over a route with the same path:

- The content type follows the extension. `ETag` and `Last-Modified` are
  sent, and a matching `If-None-Match` or `If-Modified-Since` gets
  `304 Not Modified`.
- With the `gzip` option, a textual file of 860 bytes or more is sent gzip- or
  deflate-compressed to a client that accepts it, compressed as it is read
  from disk whatever its size. A compressed body gets a weak `ETag` naming its
  coding. A `Range` request gets `206` or `416` from the uncompressed file.
- A `<file>.gz` next to a file, no older than it, is sent as it is, with
  `Content-Encoding: gzip` and the original's content type, to a client that
  accepts gzip, whether or not the `gzip` option is on. A `Range` request is
  always served from the original.
- Content types come from `std/mime`'s table.
- A directory serves its `index.html`, after redirecting to the path with a
  trailing slash. Paths containing `..` are never served.

`public_folder "/srv/app/public"` changes the folder, resolving relative
paths against the working directory, and `serve_static false` turns static
files off. `serve_static({"gzip" => true, "dir_listing" => true})` sets the
options; a key left out counts as false, and `dir_index` controls the
`index.html` lookup. `static_headers` runs for every served file:

```iyi
static_headers do |env, path, info|
  env.response.headers["Cache-Control"] = "public, max-age=3600"
end
```

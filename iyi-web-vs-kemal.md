# iyi-web ve Kemal karşılaştırması

Karşılaştırılan sürümler: iyi-web `main` (iyi 0.14.0 ile) ve Kemal 1.14.0.
Kemal kaynakları: `src/kemal/*.cr`. iyi hakkındaki bilgiler kurulu araç
zincirinden (`iyi` 0.14.0, `~/.local/share/iyi`) okundu.

## Özet

Routing, DSL ve middleware omurgası büyük ölçüde aynı. Eksikler iki grupta:

1. iyi-web'de Kemal'den farklı ve hatalı davranan beş durum. Hepsi çalıştırılıp
   doğrulandı.
2. Eksik özellikler. Bir kısmı önce iyi'nin kendisinde değişiklik gerektiriyor.

## 1. Doğrulanmış hatalı davranışlar

| Durum | iyi-web | Kemal |
|---|---|---|
| Handler'da panic | Bağlantı yanıtsız kapanıyor; o anda açık **diğer tüm bağlantılar da** kapanıyor | 500 dönüyor, diğer isteklere dokunmuyor (`exception_handler.cr`) |
| İstemci yanıt yazılırken bağlantıyı kesiyor | `panic: cannot write to socket`; diğer bağlantılar da kapanıyor | Yalnızca o istek etkileniyor |
| Header'da CR/LF (`env.redirect(query)` ile `%0d%0a`) | Yanıta sahte `Set-Cookie: injected=1` başlığı ekleniyor: header enjeksiyonu | `HTTP::Headers` geçersiz karakteri reddediyor |
| `/users/:id` ile `/users/:user_id/posts` birlikte | İkinci route parametreyi `id` adıyla alıyor, `user_id` boş | Kayıtta `Radix::Tree::SharedKeyError` |
| Aynı route iki kez | İkincisi sessizce birincinin yerine geçiyor | Kayıtta `Radix::Tree::DuplicateError` |
| `/about/` isteği | 404 | `/about` ile eşleşiyor (radix sondaki `/`'ı tolere ediyor) |

**Nedenler:**
- **Panic ve kopan istemci:** Her bağlantı aynı `group` içinde çalışıyor ve
  iyi'nin grup kuralı ilk hatada tüm kardeş görevleri iptal ediyor
  (`concurrency.iyi`, `child_finished`). Panic'lenen görev grup listesinde
  kalıyor ve sunucu durdurulurken `a task panicked` olarak yeniden fırlatılıyor.
- **İptal sırasında görülen ikinci panic:** iyi çalışma zamanı ayrıca
  `panic: two fibers waiting on one fd` verdi.
- **Header enjeksiyonu:** iyi-web'in `Headers` tipi değerleri denetlemeden
  yazıyor.
- **Parametre adı:** Parametre adı route yerine ağaç düğümünde tutuluyor, bu
  yüzden ilk tanımlanan ad kazanıyor.
- **Sondaki `/`:** Yol parçalara bölünürken sondaki boş parça bir segment
  sayılıyor.

## 2. Eksik özellikler

Boyut: S küçük, M orta, L büyük iş.

| Alan | Kemal'de olan | Boyut | iyi tarafında önce gereken |
|---|---|---|---|
| Hata sayfaları | `error 500`; geliştirme ortamında ayrıntılı hata sayfası, production'da sade sayfa (`show_exceptions`); `error 404 do \|env, ex\|`; `error HTTP::Status`; `error MyException`; çok büyük gövdeye 413 | M | Panic mesajı `Panicked#text` içinden okunabiliyor; exception sınıfına göre `error` yazmanın iyi'de doğrudan karşılığı yok |
| JSON parametreleri | `env.params.json`: `application/json` ve `application/*+json`; dizi `_json` anahtarında; bozuk JSON'a 400 | S | Yok; `JSON.parse?` hazır |
| Dosya yükleme | `params.files`, `all_files` (`ad[]`), `FileUpload` (path, filename, headers, size); geçici dosyaya yazma ve istek sonunda silme; `max_file_uploads` (128), `max_multipart_form_field_size` (8 MiB), 413 | M | Multipart ayrıştırıcı std'de yok; `File.tempfile` var |
| Parametre detayları | Aynı anahtarın birden çok değeri (`fetch_all`), `raw_body`, ihtiyaç anında ayrıştırma | S | `std/uri` Params hatalı `%` görünce panic veriyor, doğrudan kullanılamaz |
| Parça parça yanıt | `response.flush`, `headers_sent?`, `discard_unsent_body` | M | Yok. iyi-web tüm yanıtı tek String olarak yazıyor |
| SSE | `sse "/x" do \|stream, env\|`; `send(data, event:, id:, retry:)`, `comment`, `flush`, `close`; HEAD kısa devresi; `event`/`id` içinde CR/LF reddi | S (akış varsa) | Parça parça yanıt |
| WebSocket | `ws` DSL ve `Router#ws`; el sıkışma (101/400/426); yalnız GET (405); Origin denetimi (`websocket_allowed_origins`, 403); `on_message`, `on_binary`, `on_ping`, `on_pong`, `on_close`, `send`, `ping`, `close` | L | **Aynı socket'te aynı anda iki fiber bekleyemiyor** (`two fibers waiting on one fd`): bir fiber okumada beklerken başka bir fiber'ın yazması (broadcast) panic veriyor. Runtime'da okuma ve yazma beklemelerinin ayrılması gerekiyor. SHA-1 ve base64 hazır |
| Statik dosyalar | gzip (`Accept-Encoding` uzlaşması, `Vary`), önceden sıkıştırılmış `.gz`, ETag/Last-Modified ile 304, Range (206/416/multipart), `dir_listing`, `dir_index`, dizin için sonda `/` yönlendirmesi, `static_headers` kancası, `nosniff` ve `Accept-Ranges`, sistem MIME tablosu | M | gzip tek seferde sıkıştırıyor, akış yok; dosyada konuma atlama (`seek`) yok |
| `send_file` | Range, gzip, `disposition:`, RFC 6266/8187 dosya adı kodlaması, `Slice` verisi, dosyayı okumadan HEAD | S–M | iyi-web dosya adını kaçışsız yazıyor: header enjeksiyonu riski |
| Şablonlar | `render "v"`, `render "v", "layout"` ve `content`, `content_for`/`yield_content` | S–M | `Eiy.render` iç içe çağrılarda sabit `__buf__` adıyla çakışıyor |
| Context | Tipli veri saklama `env.set/get/get?` (Nil, String, Int32, Int64, Float64, Bool), `add_context_storage_type`, `env.route`, `route_found?` | S | Yok |
| Yardımcılar | `redirect(url, status, body:, close:)`, `status(HTTP::Status)`, her türü alan `json(data)`, `content_type:` parametresi, `halt env, status_code:, response:`, `headers(env, hash)`, `gzip true` | S | Yok |
| Middleware | `only`/`exclude` ile `only_match?`/`exclude_match?`, `use(handler, position)`, `use(path, [handlers])` | S | Yok |
| Filtreler | 404/405'te de `before_all` çalışıyor; yolda `:id` ve `*` desenleri; bir filtreye birden çok yol; before filtrelerinden sonra hata sayfası | S | Yok |
| Cookie | `HTTP::Cookie`: `Domain`, `Expires`, geçmiş tarihle silme | S | Yok |
| Loglama | Crystal `Log` ile `200 GET / 1.2ms`, değiştirilebilir logger | S | `std/log` hazır |
| Kapanış | SIGINT/SIGTERM yakalama, kapanış mesajı, yarıdaki istekleri `shutdown_timeout` (30 sn) boyunca bitirme | M | **std'de sinyal yakalama yok**. iyi-web'de `shutdown_message` ayarı var ama kullanılmıyor; `in_flight` sayacı panic olunca azalmıyor |
| Komut satırı | `-b`, `-p`, `-s`, `--ssl-key-file`, `--ssl-cert-file`, `-h`, `extra_options` | S | `std/option_parser` var ama hatada panic veriyor |
| TLS | `config.ssl`, `bind_tls` | L | iyi'nin kendi kütüphanesinde TLS yok; `--crystal` moduyla karıştırılamıyor. OpenSSL bağlaması ya da reverse proxy gerekiyor |
| Dinleme ayarları | `Kemal.run do \|config\|` ile `reuse_port` ve unix socket | M | std/socket'te SO_REUSEPORT, unix socket ve IPv6 yok |

Kemal çekirdeğinde olmayan ama örneklerinde görülenler:
- **JSON modelleri:** Kullanıcı tiplerini JSON'dan okuma (`JSON::Serializable`
  benzeri) `std/json`'da yok; iyi'deki `derive` ile yazılabilir.
- **Örnekler:** Kemal 16 örnekle geliyor, iyi-web'de yalnızca `hello` var.
- **Oturum ve basic auth:** Kemal'de de ayrı kütüphaneler (kemal-session,
  kemal-basic-auth).
- **Route önbelleği:** Kemal'in LRU route önbelleği bir performans özelliği;
  iyi-web'in route arama yapısı zaten ucuz olduğu için gerekmiyor.

## 3. iyi-web'de olup Kemal'de olmayanlar

- `head` route tanımı.
- Hazır `CORSHandler`.
- Tüm kaynaklarda sırayla arayan `env.params["x"]`.
- `PORT` ortam değişkeni ve keep-alive ayarları (`keepalive`,
  `max_keepalive_requests`).
- Route dönüş tipinin derleme sırasında denetlenmesi (`IntoBody`). Kemal String
  dışındaki dönüşleri sessizce `""` yapıyor.
- İsteği socket olmadan test etmek için `iyi_web/harness`.

## 4. Yol haritası

1. **Güvenlik ve sağlamlık:** header'larda CR/LF engelleme; her bağlantıyı
   ayrı çalıştırıp panic'e 500 dönme; tekrarlanan route'ta hata; aynı konumda
   farklı parametre adları; sondaki `/` desteği.
2. **Kolay eşitlemeler:** `params.json`, 413, yardımcı metot imzaları, tipli
   veri saklama, `only`/`exclude`, `use` sıra ve liste biçimleri, gzip
   middleware'i, filtre davranışı, cookie alanları, statik dosyalarda ETag ve
   304, layout'lu `render`.
3. **Yapısal:** parça parça yanıt gönderme; SSE; dosya yükleme; Range.
4. **Önce iyi'de yapılması gerekenler:**
   - socket başına ayrı okuma ve yazma beklemesi (WebSocket bunu bekliyor)
   - socket hatalarının panic yerine değer olarak dönmesi
   - sinyal yakalama
   - TLS
   - SO_REUSEPORT, unix socket, IPv6

   Bunlardan sonra: WebSocket, düzgün kapanış, `-s` bayrağı.

## 5. Durum

Bu bölüm iş ilerledikçe güncellenir.

# iyi-web roadmap

Hazırlandı: 2026-11-04, iyi-web 0.5.1, iyi 0.20.1.
Hedef: FastAPI ile kapışmak, Express'ten iyi olmak, Kemal'in sadeliğini
korumak (ama o kadar da sade olmamak).

## Kısa hüküm

Kemal'in yaptığı her şeyi yapıyor, birkaç yerde onu geçiyor. FastAPI'yi
FastAPI yapan iki şey eksik: **tipli handler** ve **otomatik OpenAPI
dokümanı**. Express'in önündeki asıl engel kod değil, ekosistem.

İnceleme sırasındaki durum:

- `iyi test iyi_web`: 42 dosyanın 42'si geçti (134 sn).
- `iyi_web/`: 18.340 satır, yaklaşık yarısı test.
- Benchmark yeniden çalıştırılmadı (`bench/cores.sh` yalnızca Linux'ta
  çalışıyor ve `wrk` istiyor); aşağıdaki sayılar eski `bench/results.json`
  dosyasından.

## Ne var (güçlü taraflar)

| Alan | Durum |
|---|---|
| Routing | Radix ağacı, `:id` ve `*path`, otomatik 404/405, aynı route iki kez yazılırsa açılışta hata, trailing `/` toleransı |
| Tip güvenliği | Route'un döndürdüğü tip derlenirken kontrol ediliyor (`IntoBody`); Kemal'de böyle bir şey yok |
| Çok çekirdek | `spawn_parallel` ile her çekirdek kullanılıyor; data race yazmak derleme hatası ve hata mesajı iki çıkış yolu gösteriyor. Express'te de FastAPI'de de yok: en güçlü koz |
| JSON | `json_as(T)` + `Validate`: 400/415/422 cevapları ve `tags[1]` gibi alan yolları; FastAPI/Pydantic'e en yakın parça |
| Güvenlik | Header injection engeli, CSRF, şifreli cookie session, rate limit, basic auth, security headers, Windows'ta `%5C` path traversal düzeltmesi |
| Protokoller | WebSocket, SSE, streaming, TLS, IPv6, unix socket, graceful shutdown, timeout'lar |
| Statik dosya | ETag, 304, Range/206, gzip, önceden sıkıştırılmış `.gz` |
| Test | `harness` ile soket açmadan test; CI'da benchmark regresyon kapısı |

## Ne yok, ne zayıf

1. **Parametreler hep string.** `env.params.url["id"].to_i? || 0` yazmak
   gerekiyor; `[]` anahtar yoksa panic atıyor. FastAPI'de `id: int` yetiyor.
2. **OpenAPI ve Swagger UI yok.** FastAPI'nin en büyük satış noktası.
3. **Dependency injection yok.** "Bu route'tan önce kullanıcıyı bul, DB
   bağlantısını ver" gibi işler için tekrar kullanılabilir bir yapı yok;
   `env.set/get` sadece ilkel bir başlangıç.
4. **Template'ler otomatik escape etmiyor** (README "Templates" bölümü
   bunu açıkça söylüyor). Bir yerde `HTML.escape` unutulursa XSS açığı
   oluşuyor.
5. **Kendi HTTP sunucunu yazıyorsun, ama std artık bunun ötesine geçti.**
   `server.iyi` + `intake.iyi` + `websocket.iyi` yaklaşık 1.900 satır.
   Kurulu `std/http` şunları zaten yapıyor (std/http.iyi başındaki yorum):
   - HTTP/2 (h2c ve ALPN),
   - `stream_bodies: true`,
   - zstd,
   - TLS 1.2 ve mTLS,
   - `std/autocert` ile Let's Encrypt.

   iyi-web bunların hiçbirini kullanmıyor. *(Faz 4'te giderildi: transport
   artık `std/http`; `intake.iyi` silindi.)*
6. **Gelen istek ayrıştırması pahalı.** Eski ölçümde `intake.get` istek
   başına ~5 µs, radix lookup ~0,28 µs. Başlık önce framing için taranıyor,
   string'e kopyalanıyor, sonra `std/http` aynı başlığı baştan bir daha
   ayrıştırıyor. Body bütünüyle bellekte tutuluyor; 64 MB'lık istek bellekte
   bunun birkaç katına çıkıyor. *(Faz 4'te giderildi: başlık bir kez
   ayrıştırılıyor, `wire.get` 3397 ns; gövde akıtılabiliyor.)*
7. **Performans sayıları eski ve kıyas yok.** `results.json` iyi 0.18 ile,
   tek thread'de, Windows'ta alınmış: hello için 27,6k req/s, p99 ~3 ms.
   FastAPI, Express veya Kemal ile yan yana ölçüm yok.
8. **Paylaşılan state yazmak zahmetli.** `Mutex.new { }`, `.get { }.or_panic`,
   kilitten çıkarken `List.new(...)` gerekiyor. `examples/typed_json.iyi`
   bile bu yüzden `workers: 1`'e kaçıyor.
9. **Eksik özellikler:** startup/shutdown hook'ları, JWT/OAuth2/API key,
   background task, metrics/tracing, `reuse_port` (std/socket'te hâlâ yok),
   proje iskeleti üreten komut, hot reload. (Veritabanı tarafı hazır:
   `iyilang/db`, `iyilang/pg`, `iyilang/mysql`; iyi-web'de yeni sürücü
   yazılmayacak.)
10. **Dokümanların bir kısmı eskimiş.** README "TLS 1.3 only" diyor ama
    std/tls artık 1.2'yi de konuşuyor. `iyi-web-vs-kemal.md` "33 test
    dosyası" diyor, şu an 42. README `@v0.5.0` örneği veriyor, son sürüm
    0.5.1. Bütün doküman tek bir 1.600 satırlık README. *(Faz 0 ve Faz 5'te
    giderildi.)*

## Rakiplerle yan yana

| | FastAPI | Express | Kemal | iyi-web (inceleme anı) | iyi-web (roadmap sonrası) |
|---|---|---|---|---|---|
| 3 satırda hello | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tipli parametre | ✅ | ❌ | ❌ | ⚠️ sadece JSON body | ✅ `path:`/`query:`/`headers:`/`body:` |
| Validasyon | ✅ Pydantic | ❌ (paketle) | ❌ | ✅ | ✅ |
| OpenAPI + UI | ✅ | ❌ (paketle) | ❌ | ❌ | ✅ derleme anında, `/docs` |
| DI | ✅ `Depends` | ❌ | ❌ | ❌ | ✅ `deps:` + `Dep` |
| Çok çekirdek | ⚠️ worker process'leri | ⚠️ cluster | ✅ | ✅ + derleme anında race kontrolü | ✅ + `Store(T)` |
| HTTP/2 | ⚠️ sunucuya bağlı | ⚠️ | ❌ | ❌ (std'de var) | ✅ h2c + ALPN h2 |
| WebSocket/SSE | ✅ | ⚠️ paketle | ✅ | ✅ | ✅ |
| Session/CSRF dahili | ❌ | ❌ | ⚠️ ayrı shard | ✅ | ✅ |
| Ekosistem | 🟢 dev | 🟢 dev | 🟡 | 🔴 | 🟡 CLI, DB örneği, metrics/tracing; topluluk hâlâ küçük |

## ELI5 roadmap

Benzetme: iyi-web bir **lokanta mutfağı**. Mutfak sağlam, ocaklar çok,
yangın alarmı bile var. Eksik olanlar **menü** (OpenAPI), **garsonun
siparişi doğru yazması** (tipli parametre) ve **müşterinin kapıyı bulması**
(ekosistem ve doküman).

```mermaid
flowchart LR
  F0[Faz 0<br/>Temizlik] --> F1[Faz 1<br/>Tipli handler]
  F1 --> F2[Faz 2<br/>OpenAPI + Docs UI]
  F1 --> F3[Faz 3<br/>Depends]
  F0 --> F4[Faz 4<br/>std/http'ye geçiş]
  F2 --> F5[Faz 5<br/>Ekosistem + DX]
  F3 --> F5
  F4 --> F6[Faz 6<br/>Herkese açık benchmark]
  F5 --> F6
```

### Faz 0: Mutfağı topla (küçük, hızlı)

**ELI5:** Bıçaklar açıkta duruyor, tabelada yanlış saat yazıyor.

- [x] Template'lerde otomatik escape varsayılan olsun, ham çıktı için `raw`
      gibi açık bir kaçış olsun. Breaking change: CHANGELOG'da duyurulmalı.
- [x] README'deki TLS ve sürüm bilgisini düzelt, `iyi-web-vs-kemal.md`'yi
      güncelle.
- [x] `env.params.url.int("id")` gibi `Int32 | ParamError` döndüren küçük
      yardımcılar.
- [x] `on_start` / `on_stop` hook'ları (FastAPI'deki `lifespan`).

**Bitti sayılır:** escape unutulduğunda XSS çıkmıyor; dokümandaki her iddia
koddaki davranışla uyuşuyor.

**Durum:** tamam. Autoescape (`raw`, `SafeHTML`), `env.params.int(...)` ve
benzerleri, `on_start`/`on_stop` yerinde. README'deki `@v0.5.0` örnekleri ve
`iyi-web-vs-kemal.md`'nin durum bölümü güncellendi; TLS/HTTP sürümü
iddiaları Faz 4'ün transport işiyle düzeltildi (README,
`docs/configuration.md`, `iyi-web-vs-kemal.md`: TLS 1.3 ve 1.2, HTTP/2).

### Faz 1: Garson siparişi doğru yazsın (FastAPI'yi asıl yenecek kısım)

**ELI5:** Müşteri "2 çay" diyor, garson "iki çay" diye not alıyor, sonra
mutfak bunun sayı olup olmadığını tahmin etmeye çalışıyor. Bunun yerine
sipariş fişinde kutucuklar olsun.

Taslak API (sözdizimi kesin değil; iyi'nin macro'larıyla bu şekilde
kurulabileceği bir çıkarım):

```iyi
struct NoteQuery
  getter page : Int32 = 1
  getter q : String? = nil
  derive params            # query/path/header'dan okunur, hatada 422
end

get "/notes/:id", path: NoteId, query: NoteQuery do |env, id, q|
  ...
end

post "/notes", body: NoteInput do |env, input|   # BodyError'ı framework kendisi döndürür
  env.status(201).json(save(input))
end
```

- [x] `json_as` ve `Validate` zaten var; bu faz onları route imzasına
      taşımak demek.
- [x] Response tipi de bildirilebilmeli (FastAPI'deki `response_model`);
      Faz 2 için gerekiyor.
- **Sadelik kuralı:** `get "/" do |env|` aynen çalışmaya devam eder. Tipli
  biçim isteğe bağlı bir üst katman olur.

**Bitti sayılır:** `examples/typed_json.iyi` ve `examples/json_api.iyi`
içinde elle yazılmış hiçbir `to_i?` veya `case ... in BodyError` kalmıyor.

**Durum:** tamam. `path:`, `query:`, `headers:`, `body:`, `response:` ve
`status:` her route metodunda; iki örnekte de elle `to_i?` ya da
`BodyError` eşleşmesi kalmadı (bkz. `docs/typed-routes.md`).

### Faz 2: Menü (OpenAPI 3.1 + Swagger UI/Scalar)

**ELI5:** Müşteri mutfağa girmeden menüden ne sipariş edebileceğini görsün.

- [x] Route kayıtları + Faz 1'in tipleri → `/openapi.json`.
- [x] `/docs` adresinde gömülü bir UI (tek bir statik HTML yeterli).
- Doküman derleme anında üretilir; FastAPI'ye karşı koz, orada şema
  çalışma anında üretiliyor.

**Bitti sayılır:** `/openapi.json` bir OpenAPI validator'ından geçiyor ve
oradan üretilen bir client (ör. openapi-generator) gerçek API'yi
çağırabiliyor.

**Durum:** tamam. `openapi(...)` `/openapi.json` ve Swagger UI'lı `/docs`
sunuyor; `examples/openapi_auth.iyi`'nin dokümanı openapi-spec-validator'dan
geçiyor (bkz. `docs/openapi.md`).

### Faz 3: Yardımcı aşçılar (`Depends` karşılığı)

**ELI5:** Her yemekten önce "elleri yıka, tabağı ısıt" adımı tekrar tekrar
yazılmasın. Bir kere tanımla, istediğin yemeğe bağla.

- [x] `def current_user(env) : User | HttpError` gibi bir fonksiyon
      `deps: {user: current_user}` ile route'a bağlanır, block'a tipli gelir.
- [x] Hazır parçalar: Bearer/JWT, API key, OAuth2 password flow (iyi std'de
      `password`, `otp` gibi parçalar mevcut).
- [x] Bunlar OpenAPI'ye `securitySchemes` olarak yansır.

**Durum:** tamam. `Dep.new { |env| ... }` ve `deps:`; `bearer_auth`,
`api_key_auth`, `jwt_auth`, OAuth2 password flow (bkz.
`docs/dependencies-and-auth.md`).

### Faz 4: Mutfağı yeni binaya taşı (std/http'nin üstüne geç)

**ELI5:** Belediye yeni ve daha iyi bir mutfak yapmış: HTTP/2 ocağı, akan su
(stream), otomatik sertifika kapıcısı. Sen eski binada her şeyi kendi
elinle yapıyorsun.

- [x] Transport katmanını `std/http`'ye devret: her bağlantı
      `Server.handle`'a gidiyor (`Server.serve`'ün bağlantı yarısı). Accept
      döngüsü, worker havuzu, drain ve timeout'lar ile 408/413/414/431
      iyi-web'in ince soket katmanında kaldı; Router, Context ve middleware
      olduğu gibi.
- [x] HTTP/2: h2c (prior knowledge) ve TLS üstünde ALPN ile h2; `-s` ve
      protokol vermeyen TLS config'i `["h2", "http/1.1"]` sunuyor.
- [x] `stream_bodies` (`env.request.body_io`, `body_failure`); multipart
      upload'lar her zaman diske akıyor.
- [x] zstd (ve gzip): `config.compress`.
- [x] TLS 1.2 ve mTLS: `min_version` / `--ssl-min-version 1.2`,
      `client_roots` / `--ssl-client-ca FILE`,
      `env.request.peer_certificates`.
- [x] `std/autocert` ile Let's Encrypt: `config.autocert`.
- **Risk:** iyi-web'in kendi garantileri std'de birebir aynı olmayabilir:
  414/431 sınırları, `read/write/idle_timeout`, shutdown drain, unix socket.
  Önce bunları kapsayan testler std üzerinde de geçmeli; geçmeyenler std'ye
  PR olarak gitmeli ya da ince bir adapter ile kapatılmalı. *(Sonuç: ince
  katmanla kapatıldı. Kalan farklar CHANGELOG'da: TLS/HTTP/2'de süresi
  dolan başlık 408 yerine kapatılıyor, HTTP/1.0'a HTTP/1.1 durum satırı.)*
- [ ] `reuse_port` için std/socket'e PR. Engel: std/socket yalnızca
      `SO_REUSEADDR` koyuyor; iyi-web tarafında yapılacak iş yok.
- [ ] 64 MiB gövde sınırı: std/http her gövdeyi 64 MiB'da kesiyor
      (`Server::MAX_BODY`), `max_request_body_size` daha büyük olsa da.
      Engel: std/http'de ayarlanabilir bir sınır gerekiyor.

**Bitti sayılır:** 42 test dosyası yeni transport üzerinde geçiyor ve
`curl --http2` çalışıyor.

**Durum:** tamam; iki madde std'yi bekliyor. Transport `std/http`
üstünde, 52 test dosyası onunla geçiyor; HTTP/2, akan gövdeler, TLS
1.2/mTLS, autocert ve zstd yerinde (bkz. `docs/transport.md`). İstek
ayrıştırma GET'te 5966 → 3397 ns, form POST'ta 2267 → 1688 ns. `reuse_port`
std/socket'i, 64 MiB'ın üstü std/http'yi bekliyor.

### Faz 5: Ekosistem ve geliştirici deneyimi (Express'i geçmek için)

**ELI5:** En iyi mutfak bile kimse yolu bilmezse boş kalır.

- [x] **Veritabanı:** yeni sürücü yazılmayacak; mevcut
      [iyilang/db](https://github.com/iyilang/db),
      [iyilang/pg](https://github.com/iyilang/pg) ve
      [iyilang/mysql](https://github.com/iyilang/mysql) kullanılacak.
      iyi-web tarafındaki iş: bunlarla bir örnek uygulama, README/doküman
      bölümü ve Faz 3'teki `deps:` ile route'a bağlantı vermenin kalıbı.
- [x] `iyi-web new myapp` ile proje iskeleti, `iyi-web dev` ile hot reload.
- [x] Doküman sitesi: tutorial + referans (FastAPI'nin dokümanı model);
      1.600 satırlık README bölünür.
- [x] Paylaşılan state ergonomisi: `Mutex` + `List` dansını saklayan küçük
      bir `Store(T)` yardımcısı; örnekler `workers: 1`'e kaçmak zorunda
      kalmaz.
- [x] `/metrics` (Prometheus), OpenTelemetry trace middleware'i, background
      task'lar.
- [x] Topluluk middleware'lerinin nasıl yazılacağını anlatan plugin rehberi.

**Durum:** tamam. `examples/postgres`, `iyi-web new`/`dev`, `mkdocs.yml` ile
`docs/` sitesi ve `docs/tutorial.md`, `Store(T)`, metrics/tracing/background
ve `docs/plugins.md` yerinde; README giriş sayfasına indi.

### Faz 6: Yarışa çık (herkese açık benchmark)

**ELI5:** "En hızlıyız" demek yetmez; aynı pistte koşup kronometreyi
göstermek lazım.

- [x] Aynı makinede, aynı 3 endpoint (hello, JSON, DB query) için iyi-web,
      FastAPI (uvicorn workers), Express, Kemal ve Go net/http; sonuçlar ve
      script'ler repoda.
- [x] Hedef sıcak nokta `intake.get` (~5 µs); Faz 4 sonrasında yeniden
      ölçüldü: artık `wire.get`, 5966 → 3397 ns.
- [ ] TechEmpower'a başvuru. Açık, çünkü TechEmpower'ın kendi deposuna
      yapılacak dış bir başvuru; bu repodaki işin parçası değil.

**Durum:** `bench/compare/` beş framework'ü aynı makinede dört endpoint'te
ölçüyor: hello, JSON, path ve query parametreli bir endpoint ve DB query
(`/db`: TechEmpower'ın single query'si, PostgreSQL 16 ve her framework'te
bağlantı havuzu). Sonuçlar `docs/benchmarks.md`'de; Express o ölçümde
makinede `node` olmadığı için atlandı. Faz 4'ten sonra `wire.get` (eski
`intake.get`) 5966 → 3397 ns'ye indi, öncesi/sonrası tablosu
`docs/benchmarks.md`'de. TechEmpower başvurusu sonraya kaldı.

## Sadelik çizgisi (Kemal'den ne kadar uzaklaşmalı)

- **Katman 1 (Kemal sadeliği):** `get "/" do |env| "hi" end`. Asla
  bozulmamalı.
- **Katman 2 (FastAPI gücü):** `body:` / `query:` / `deps:` ile tipli
  route'lar. İsteğe bağlı.
- **Katman 3 (Rails değil):** ORM, admin paneli, asset pipeline core'a
  girmesin; ayrı modül olarak dursun.

Bu üç katman korunursa "Kemal kadar sade ama o kadar da değil" dengesi
kendiliğinden kurulur.

## Önerilen başlangıç

En hızlı kazanç Faz 0 (template autoescape + doküman güncellemesi). Ya da
doğrudan Faz 1'in API tasarımı: `body:` / `query:` imzası için bir prototip.

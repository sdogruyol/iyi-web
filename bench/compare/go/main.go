// Go's side of bench/compare: the endpoints on net/http and its ServeMux
// (method and wildcard patterns, Go 1.22+). net/http serves every
// connection on its own goroutine across GOMAXPROCS threads, every core by
// default.
//
// `/db` is there when DATABASE_URL is: one pgx/v5 pool (pgxpool) shared by
// every goroutine, at most DB_POOL_SIZE connections (default 48), all of
// them opened at start.
package main

import (
	"context"
	"encoding/json"
	"math/rand/v2"
	"net/http"
	"os"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
)

type user struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	Fields string `json:"fields"`
}

type world struct {
	ID           int32 `json:"id"`
	RandomNumber int32 `json:"randomNumber"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /plaintext", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.Write([]byte("Hello, World!"))
	})
	mux.HandleFunc("GET /json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"message": "Hello, World!"})
	})
	mux.HandleFunc("GET /users/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(user{ID: id, Name: "user-" + strconv.FormatInt(id, 10), Fields: r.URL.Query().Get("fields")})
	})
	if url := os.Getenv("DATABASE_URL"); url != "" {
		pool := openPool(url)
		mux.HandleFunc("GET /db", func(w http.ResponseWriter, r *http.Request) {
			var row world
			err := pool.QueryRow(r.Context(), "SELECT id, randomnumber FROM world WHERE id = $1", rand.IntN(10000)+1).Scan(&row.ID, &row.RandomNumber)
			if err != nil {
				http.Error(w, "database unavailable", http.StatusServiceUnavailable)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(row)
		})
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		panic(err)
	}
}

func openPool(url string) *pgxpool.Pool {
	config, err := pgxpool.ParseConfig(url)
	if err != nil {
		panic(err)
	}
	size := int32(48)
	if n, err := strconv.Atoi(os.Getenv("DB_POOL_SIZE")); err == nil && n > 0 {
		size = int32(n)
	}
	config.MaxConns = size
	config.MinConns = size
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		panic(err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		panic(err)
	}
	return pool
}

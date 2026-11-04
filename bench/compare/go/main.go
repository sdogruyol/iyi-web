// Go's side of bench/compare: the three endpoints on net/http and its
// ServeMux (method and wildcard patterns, Go 1.22+). net/http serves every
// connection on its own goroutine across GOMAXPROCS threads, every core by
// default.
package main

import (
	"encoding/json"
	"net/http"
	"os"
	"strconv"
)

type user struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	Fields string `json:"fields"`
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
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		panic(err)
	}
}

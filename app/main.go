package main

import (
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"time"
)

const indexTmpl = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Demo Corp Internal Portal</title>
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #f0f2f5;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    margin: 0;
  }
  .card {
    background: white;
    border-radius: 8px;
    padding: 2rem 3rem;
    box-shadow: 0 2px 8px rgba(0,0,0,0.12);
    max-width: 480px;
    width: 100%;
  }
  h1 { color: #1a1a2e; margin-top: 0; }
  .badge {
    display: inline-block;
    background: #4caf50;
    color: white;
    font-size: 0.75rem;
    padding: 2px 8px;
    border-radius: 4px;
    margin-left: 8px;
    vertical-align: middle;
  }
  table { width: 100%; border-collapse: collapse; margin-top: 1.5rem; }
  td { padding: 0.5rem 0; border-bottom: 1px solid #f0f0f0; }
  td:first-child { font-weight: 600; color: #555; width: 40%; }
  td:last-child { color: #222; font-family: monospace; font-size: 0.9rem; }
</style>
</head>
<body>
<div class="card">
  <h1>Welcome to Demo Corp <span class="badge">SECURE</span></h1>
  <p>Internal infrastructure portal. Connection is encrypted via enterprise PKI.</p>
  <table>
    <tr>
      <td>Hostname</td>
      <td>{{.Hostname}}</td>
    </tr>
    <tr>
      <td>Pod</td>
      <td>{{.PodName}}</td>
    </tr>
    <tr>
      <td>Namespace</td>
      <td>{{.Namespace}}</td>
    </tr>
    <tr>
      <td>Node</td>
      <td>{{.NodeName}}</td>
    </tr>
    <tr>
      <td>Timestamp</td>
      <td>{{.Timestamp}}</td>
    </tr>
  </table>
</div>
</body>
</html>`

type pageData struct {
	Hostname  string
	PodName   string
	Namespace string
	NodeName  string
	Timestamp string
}

var tmpl = template.Must(template.New("index").Parse(indexTmpl))

func indexHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	hostname, _ := os.Hostname()
	data := pageData{
		Hostname:  hostname,
		PodName:   envOrDefault("POD_NAME", hostname),
		Namespace: envOrDefault("POD_NAMESPACE", "unknown"),
		NodeName:  envOrDefault("NODE_NAME", "unknown"),
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Frame-Options", "DENY")

	if err := tmpl.Execute(w, data); err != nil {
		log.Printf("template error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
	}
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, `{"status":"ok"}`)
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	port := envOrDefault("PORT", "8080")

	mux := http.NewServeMux()
	mux.HandleFunc("/", indexHandler)
	mux.HandleFunc("/healthz", healthzHandler)

	addr := fmt.Sprintf(":%s", port)
	log.Printf("demo-app starting on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

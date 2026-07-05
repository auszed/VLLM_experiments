// Load tester for a vLLM OpenAI-compatible endpoint.
// Ramps concurrency and reports throughput + latency percentiles per step,
// then finds the saturation point. Writes results.json for MLflow logging.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type reqResult struct {
	ttftMs, e2eMs float64
	tokens        int
	ok            bool
	text          string
	finish        string
}

// One captured request/response for per-call tracing. Captured in memory during the
// run (cheap); traces are created afterward from results.json, so this does not skew
// the measured timings.
type callRecord struct {
	Concurrency  int     `json:"concurrency"`
	OK           bool    `json:"ok"`
	Response     string  `json:"response"`
	Tokens       int     `json:"tokens"`
	FinishReason string  `json:"finish_reason"`
	TTFTms       float64 `json:"ttft_ms"`
	E2Ems        float64 `json:"e2e_ms"`
}

type stepResult struct {
	Concurrency    int     `json:"concurrency"`
	Requests       int     `json:"requests"`
	Successes      int     `json:"successes"`
	Errors         int     `json:"errors"`
	SuccessRate    float64 `json:"success_rate"`
	WallSeconds    float64 `json:"wall_seconds"`
	RequestsPerSec float64 `json:"requests_per_sec"`
	OutputTokens   int     `json:"output_tokens"`
	TokensPerSec   float64 `json:"tokens_per_sec"`
	TTFTp50        float64 `json:"ttft_p50_ms"`
	TTFTp95        float64 `json:"ttft_p95_ms"`
	TTFTp99        float64 `json:"ttft_p99_ms"`
	E2Ep50         float64 `json:"e2e_p50_ms"`
	E2Ep95         float64 `json:"e2e_p95_ms"`
	E2Ep99         float64 `json:"e2e_p99_ms"`
}

type report struct {
	Model                 string       `json:"model"`
	URL                   string       `json:"url"`
	MaxTokens             int          `json:"max_tokens"`
	Temperature           float64      `json:"temperature"`
	Prompt                string       `json:"prompt"`
	SLOms                 float64      `json:"slo_ms"`
	SaturationConcurrency int          `json:"saturation_concurrency"`
	MaxSustainedRPS       float64      `json:"max_sustained_rps"`
	Steps                 []stepResult `json:"steps"`
	Calls                 []callRecord `json:"calls,omitempty"`
	Timestamp             string       `json:"timestamp"`
}

var client = &http.Client{
	Transport: &http.Transport{
		MaxIdleConns:        512,
		MaxIdleConnsPerHost: 512,
	},
}

func resolveModel(url, key string) string {
	req, _ := http.NewRequest("GET", url+"/models", nil)
	req.Header.Set("Authorization", "Bearer "+key)
	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	var out struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&out)
	if len(out.Data) > 0 {
		return out.Data[0].ID
	}
	return ""
}

func doRequest(url, key, model, prompt string, maxTokens int, temperature float64) reqResult {
	body, _ := json.Marshal(map[string]any{
		"model":          model,
		"prompt":         prompt,
		"max_tokens":     maxTokens,
		"temperature":    temperature,
		"ignore_eos":     true, // force exactly max_tokens of work per request
		"stream":         true,
		"stream_options": map[string]bool{"include_usage": true},
	})
	req, _ := http.NewRequest("POST", url+"/completions", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+key)

	start := time.Now()
	resp, err := client.Do(req)
	if err != nil || resp.StatusCode != 200 {
		if resp != nil {
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
		}
		return reqResult{ok: false}
	}
	defer resp.Body.Close()

	r := reqResult{ok: true}
	var firstAt time.Time
	var sb strings.Builder
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(line[5:])
		if data == "[DONE]" {
			continue
		}
		var chunk struct {
			Choices []struct {
				Text         string `json:"text"`
				FinishReason string `json:"finish_reason"`
			} `json:"choices"`
			Usage *struct {
				CompletionTokens int `json:"completion_tokens"`
			} `json:"usage"`
		}
		if json.Unmarshal([]byte(data), &chunk) != nil {
			continue
		}
		if len(chunk.Choices) > 0 {
			if chunk.Choices[0].Text != "" && firstAt.IsZero() {
				firstAt = time.Now()
				r.ttftMs = float64(firstAt.Sub(start).Microseconds()) / 1000
			}
			sb.WriteString(chunk.Choices[0].Text)
			if chunk.Choices[0].FinishReason != "" {
				r.finish = chunk.Choices[0].FinishReason
			}
		}
		if chunk.Usage != nil {
			r.tokens = chunk.Usage.CompletionTokens
		}
	}
	r.e2eMs = float64(time.Since(start).Microseconds()) / 1000
	r.text = sb.String()
	return r
}

func runStep(url, key, model, prompt string, maxTokens int, temperature float64, concurrency, requests int, capture bool) (stepResult, []callRecord) {
	tasks := make(chan int, requests)
	for i := 0; i < requests; i++ {
		tasks <- i
	}
	close(tasks)

	results := make([]reqResult, 0, requests)
	var mu sync.Mutex
	var wg sync.WaitGroup
	start := time.Now()
	for w := 0; w < concurrency; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range tasks {
				res := doRequest(url, key, model, prompt, maxTokens, temperature)
				mu.Lock()
				results = append(results, res)
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	wall := time.Since(start).Seconds()

	var ttfts, e2es []float64
	tokens, ok := 0, 0
	for _, r := range results {
		if r.ok {
			ok++
			tokens += r.tokens
			ttfts = append(ttfts, r.ttftMs)
			e2es = append(e2es, r.e2eMs)
		}
	}
	sort.Float64s(ttfts)
	sort.Float64s(e2es)

	var calls []callRecord
	if capture {
		calls = make([]callRecord, 0, len(results))
		for _, r := range results {
			calls = append(calls, callRecord{
				Concurrency: concurrency, OK: r.ok, Response: r.text, Tokens: r.tokens,
				FinishReason: r.finish, TTFTms: r.ttftMs, E2Ems: r.e2eMs,
			})
		}
	}
	return stepResult{
		Concurrency:    concurrency,
		Requests:       requests,
		Successes:      ok,
		Errors:         requests - ok,
		SuccessRate:    float64(ok) / float64(requests),
		WallSeconds:    wall,
		RequestsPerSec: float64(ok) / wall,
		OutputTokens:   tokens,
		TokensPerSec:   float64(tokens) / wall,
		TTFTp50:        pct(ttfts, 50), TTFTp95: pct(ttfts, 95), TTFTp99: pct(ttfts, 99),
		E2Ep50: pct(e2es, 50), E2Ep95: pct(e2es, 95), E2Ep99: pct(e2es, 99),
	}, calls
}

func pct(sorted []float64, p int) float64 {
	if len(sorted) == 0 {
		return 0
	}
	i := (p * len(sorted)) / 100
	if i >= len(sorted) {
		i = len(sorted) - 1
	}
	return sorted[i]
}

func main() {
	url := flag.String("url", "http://localhost:8000/v1", "vLLM base URL")
	key := flag.String("key", "change-me", "API key")
	model := flag.String("model", "", "model id (default: auto from /v1/models)")
	ramp := flag.String("concurrency", "1,4,8,16", "comma-separated concurrency ramp")
	requests := flag.Int("requests", 40, "requests per concurrency step")
	maxTokens := flag.Int("max-tokens", 64, "max_tokens per request")
	prompt := flag.String("prompt", "Write one sentence about the sea.", "prompt")
	slo := flag.Float64("slo-ms", 5000, "p95 e2e latency SLO (ms) marking saturation")
	temperature := flag.Float64("temperature", 0, "sampling temperature (>0 varies answers; 0 = deterministic)")
	trace := flag.Bool("trace", false, "capture every request/response into results.json for per-call tracing")
	out := flag.String("out", "results.json", "output JSON path")
	flag.Parse()

	if *model == "" {
		*model = resolveModel(*url, *key)
		if *model == "" {
			fmt.Fprintln(os.Stderr, "could not resolve model from /v1/models")
			os.Exit(1)
		}
	}
	fmt.Printf("Target %s  model=%s  requests/step=%d  slo=%.0fms\n", *url, *model, *requests, *slo)

	rep := report{
		Model: *model, URL: *url, MaxTokens: *maxTokens, Temperature: *temperature, Prompt: *prompt,
		SLOms: *slo, Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	fmt.Printf("%-6s %8s %8s %10s %8s %8s\n", "conc", "req/s", "tok/s", "e2e_p95", "ttft_p95", "ok%")
	for _, s := range strings.Split(*ramp, ",") {
		c, err := strconv.Atoi(strings.TrimSpace(s))
		if err != nil || c <= 0 {
			continue
		}
		res, calls := runStep(*url, *key, *model, *prompt, *maxTokens, *temperature, c, *requests, *trace)
		rep.Steps = append(rep.Steps, res)
		rep.Calls = append(rep.Calls, calls...)
		fmt.Printf("%-6d %8.1f %8.1f %10.0f %8.0f %7.0f\n",
			res.Concurrency, res.RequestsPerSec, res.TokensPerSec, res.E2Ep95, res.TTFTp95, res.SuccessRate*100)
		saturated := res.E2Ep95 > *slo || res.SuccessRate < 0.99
		if saturated && rep.SaturationConcurrency == 0 {
			rep.SaturationConcurrency = c
		}
		if !saturated && res.RequestsPerSec > rep.MaxSustainedRPS {
			rep.MaxSustainedRPS = res.RequestsPerSec
		}
	}

	b, _ := json.MarshalIndent(rep, "", "  ")
	os.WriteFile(*out, b, 0644)
	fmt.Printf("\nsaturation_concurrency=%d  max_sustained_rps=%.1f  -> %s\n",
		rep.SaturationConcurrency, rep.MaxSustainedRPS, *out)
}

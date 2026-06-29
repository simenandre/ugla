// Command babymonitor-web serves a local RTSP camera feed as HLS in the browser.
//
// It supervises an ffmpeg process that pulls the RTSP stream produced by the
// avent-webrtc-bridge and repackages it as HLS (H.264 copied, audio to AAC),
// then serves a small player page. Designed for viewing a Philips Baby
// Monitor+ feed on a Mac.
package main

import (
	"context"
	"embed"
	"flag"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

//go:embed index.html hls.min.js
var assets embed.FS

// assetDir, if set, makes the server read index.html / hls.min.js fresh from
// disk on each request (handy for tweaking the player without rebuilding).
var assetDir string

func readAsset(name string) []byte {
	if assetDir != "" {
		if b, err := os.ReadFile(filepath.Join(assetDir, name)); err == nil {
			return b
		}
	}
	b, _ := assets.ReadFile(name)
	return b
}

func main() {
	rtsp := flag.String("rtsp", envOr("BABYMON_RTSP", ""), "Upstream RTSP URL (required)")
	addr := flag.String("addr", envOr("BABYMON_ADDR", "127.0.0.1:8080"), "HTTP listen address")
	ffmpegBin := flag.String("ffmpeg", envOr("BABYMON_FFMPEG", "ffmpeg"), "Path to ffmpeg")
	flag.StringVar(&assetDir, "assets", envOr("BABYMON_ASSETS", ""), "Serve index.html/hls.min.js from this dir instead of embedded (dev)")
	maxRetries := flag.Int("max-retries", 3, "Consecutive ffmpeg failures before exiting (feed gone)")
	flag.Parse()

	if *rtsp == "" {
		log.Fatal("missing -rtsp (or BABYMON_RTSP): the upstream RTSP URL")
	}

	hlsDir, err := os.MkdirTemp("", "babymon-hls-")
	if err != nil {
		log.Fatalf("temp dir: %v", err)
	}
	defer os.RemoveAll(hlsDir)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		superviseFFmpeg(ctx, *ffmpegBin, *rtsp, hlsDir, *maxRetries)
		stop() // feed lost (or already shutting down) -> bring the server down
	}()

	mux := http.NewServeMux()
	mux.Handle("/hls/", http.StripPrefix("/hls/", noCache(http.FileServer(http.Dir(hlsDir)))))
	mux.HandleFunc("/hls.min.js", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/javascript")
		w.Write(readAsset("hls.min.js"))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.Write(readAsset("index.html"))
	})

	srv := &http.Server{Addr: *addr, Handler: mux}
	go func() {
		<-ctx.Done()
		shutCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		srv.Shutdown(shutCtx)
	}()

	log.Printf("Baby monitor web viewer on http://%s  (streaming from %s)", *addr, *rtsp)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("http server: %v", err)
	}
}

// superviseFFmpeg runs ffmpeg and restarts it on exit to ride out brief
// reconnects. If the feed stays down for maxFailures consecutive attempts it
// returns, signalling the caller to shut the whole server down. A run that
// stayed up a while is treated as healthy and resets the failure count.
func superviseFFmpeg(ctx context.Context, bin, rtsp, dir string, maxFailures int) {
	playlist := filepath.Join(dir, "stream.m3u8")
	failures := 0
	for ctx.Err() == nil {
		args := []string{
			"-nostdin", "-loglevel", "warning",
			"-fflags", "nobuffer",
			"-rtsp_transport", "tcp",
			"-rw_timeout", "15000000", // 15s: detect a stalled/stopped feed
			"-i", rtsp,
			"-c:v", "copy",
			"-c:a", "aac", "-b:a", "64k",
			"-f", "hls",
			"-hls_time", "1",
			"-hls_list_size", "8",
			"-hls_segment_type", "mpegts",
			"-hls_flags", "delete_segments+append_list+independent_segments+omit_endlist",
			"-hls_segment_filename", filepath.Join(dir, "seg_%05d.ts"),
			playlist,
		}
		cmd := exec.CommandContext(ctx, bin, args...)
		cmd.Stderr = os.Stderr
		log.Printf("starting ffmpeg")
		started := time.Now()
		err := cmd.Run()
		if ctx.Err() != nil {
			return
		}
		if time.Since(started) > 30*time.Second {
			failures = 0 // it was streaming fine before it dropped
		}
		failures++
		if failures >= maxFailures {
			log.Printf("ffmpeg exited (%v); feed unavailable after %d attempts — shutting down", err, failures)
			return
		}
		log.Printf("ffmpeg exited (%v); retry %d/%d in 2s", err, failures, maxFailures)
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
	}
}

func noCache(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate")
		h.ServeHTTP(w, r)
	})
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

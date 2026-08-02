// Package summarize turns a plain-text transcript into a markdown summary via a
// user-configured provider: a keyless local CLI (claude -p / codex exec) or any
// OpenAI-compatible /chat/completions endpoint. Ported 1:1 from dsqrd's Python
// (_llm_summarize / _claude_cli / _codex_cli / _available_clis). Self-contained:
// plain text in, summary text out — no mlqs mail types.
package summarize

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"mlqs/internal/config"
	"mlqs/internal/httpx"
)

// SUMMARIZE_SYS is dsqrd's system prompt, reworded chat→email.
const SUMMARIZE_SYS = "You summarize email for someone catching up. Output " +
	"GitHub-flavored markdown in this exact shape:\n" +
	"1. One line starting with `**TL;DR:**` — a single sentence covering the whole span.\n" +
	"2. Then group the content into 2-5 thematic sections, each introduced by a `## ` " +
	"header of one or two words (e.g. Billing, Hiring, Calendar).\n" +
	"3. Under each header, a few concise bullets (`- `). Start every bullet with a " +
	"**bold lead** (the topic, sender, or thread in **bold**), then ` — ` and the detail.\n" +
	"Note who sent what and any action needed (a reply, a deadline) where it matters. " +
	"Write the summary in the SAME LANGUAGE the email is mostly in (match the messages, " +
	"not this instruction). Be concise. No preamble and no closing remarks."

// CLI is a keyless agent CLI found on this machine.
type CLI struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// pathWith prepends the user-profile bins so a Nix-packaged daemon can still
// find claude/codex installed in the user profile (dsqrd does the same).
func pathWith() string {
	home, _ := os.UserHomeDir()
	return strings.Join([]string{
		"/etc/profiles/per-user/" + os.Getenv("USER") + "/bin",
		"/run/current-system/sw/bin",
		filepath.Join(home, ".local", "bin"),
		os.Getenv("PATH"),
	}, ":")
}

// findBin resolves an absolute path for a binary against pathWith(). Go's
// exec.Command resolves against the process PATH, not cmd.Env, so we must find
// the full path ourselves for the profile bins to count.
func findBin(bin string) string {
	for _, dir := range strings.Split(pathWith(), ":") {
		if dir == "" {
			continue
		}
		p := filepath.Join(dir, bin)
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() && fi.Mode()&0111 != 0 {
			return p
		}
	}
	return ""
}

// AvailableCLIs reports which keyless agent CLIs are installed, so the setup
// guide can offer a one-click button per one (dsqrd's _available_clis).
func AvailableCLIs() []CLI {
	reg := []struct{ id, bin, label string }{
		{"claude-cli", "claude", "Claude"},
		{"codex-cli", "codex", "Codex"},
	}
	out := []CLI{}
	for _, r := range reg {
		if findBin(r.bin) != "" {
			out = append(out, CLI{ID: r.id, Label: r.label})
		}
	}
	return out
}

// Summarize dispatches to the configured provider (dsqrd's _llm_summarize).
func Summarize(ctx context.Context, cfg config.SummarizeConfig, transcript string) (string, error) {
	switch strings.ToLower(cfg.Provider) {
	case "claude-cli":
		return claudeCLI(ctx, cfg, SUMMARIZE_SYS+"\n\nEmail:\n"+transcript)
	case "codex-cli":
		return codexCLI(ctx, cfg, SUMMARIZE_SYS+"\n\nEmail:\n"+transcript)
	}
	return openAICompat(ctx, cfg, transcript)
}

func claudeCLI(ctx context.Context, cfg config.SummarizeConfig, prompt string) (string, error) {
	bin := findBin("claude")
	if bin == "" {
		return "", fmt.Errorf("claude CLI not found")
	}
	model := cfg.Model
	if model == "" {
		model = "haiku"
	}
	cctx, cancel := context.WithTimeout(ctx, 180*time.Second)
	defer cancel()
	cmd := exec.CommandContext(cctx, bin, "-p", "--model", model)
	cmd.Env = append(os.Environ(), "PATH="+pathWith())
	cmd.Dir = "/tmp"
	cmd.Stdin = strings.NewReader(prompt)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = "claude -p failed"
		}
		return "", fmt.Errorf("%s", tail(msg, 200))
	}
	return strings.TrimSpace(stdout.String()), nil
}

func codexCLI(ctx context.Context, cfg config.SummarizeConfig, prompt string) (string, error) {
	bin := findBin("codex")
	if bin == "" {
		return "", fmt.Errorf("codex CLI not found")
	}
	cctx, cancel := context.WithTimeout(ctx, 180*time.Second)
	defer cancel()
	// -o <tmpfile>: codex writes its final message there, so status output on
	// stdout doesn't pollute the summary.
	f, err := os.CreateTemp("", "mlqs-codex-*")
	if err != nil {
		return "", err
	}
	out := f.Name()
	f.Close()
	defer os.Remove(out)
	args := []string{"exec", "--skip-git-repo-check", "-s", "read-only", "-o", out}
	if cfg.Model != "" {
		args = append(args, "-m", cfg.Model)
	}
	args = append(args, "-")
	cmd := exec.CommandContext(cctx, bin, args...)
	cmd.Env = append(os.Environ(), "PATH="+pathWith())
	cmd.Dir = "/tmp"
	cmd.Stdin = strings.NewReader(prompt)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	_ = cmd.Run()
	b, _ := os.ReadFile(out)
	if text := strings.TrimSpace(string(b)); text != "" {
		return text, nil
	}
	msg := strings.TrimSpace(stderr.String())
	if msg == "" {
		msg = "codex exec failed"
	}
	return "", fmt.Errorf("%s", tail(msg, 200))
}

func openAICompat(ctx context.Context, cfg config.SummarizeConfig, transcript string) (string, error) {
	if cfg.BaseURL == "" {
		return "", fmt.Errorf("no summarize provider configured")
	}
	model := cfg.Model
	if model == "" {
		model = "gpt-4o-mini"
	}
	body, _ := json.Marshal(map[string]any{
		"model":      model,
		"max_tokens": 2048,
		"messages": []map[string]string{
			{"role": "system", "content": SUMMARIZE_SYS},
			{"role": "user", "content": "Email:\n" + transcript},
		},
	})
	cctx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()
	url := strings.TrimRight(cfg.BaseURL, "/") + "/chat/completions"
	req, err := http.NewRequestWithContext(cctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if cfg.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	}
	resp, err := httpx.Client(120 * time.Second).Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	rb, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("provider %d: %s", resp.StatusCode, tail(string(rb), 200))
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(rb, &out); err != nil {
		return "", err
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("provider returned no choices")
	}
	return strings.TrimSpace(out.Choices[0].Message.Content), nil
}

func tail(s string, n int) string {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}

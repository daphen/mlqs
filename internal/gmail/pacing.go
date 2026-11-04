package gmail

import (
	"context"
	"net/url"
	"strings"
	"time"
)

func requestCost(method, path string, query url.Values) int {
	switch {
	case path == "/profile", path == "/labels", strings.HasPrefix(path, "/labels/"):
		return 1
	case path == "/history":
		return 2
	case path == "/messages":
		return 5
	case path == "/messages/send":
		return 100
	case path == "/messages/batchModify":
		return 50
	case strings.Contains(path, "/attachments/"):
		return 20
	case strings.HasPrefix(path, "/messages/"):
		if format := query.Get("format"); format == "full" || format == "raw" || format == "html" {
			return 60
		}
		return 20
	case path == "/threads":
		return 10
	case method == "POST":
		if strings.HasSuffix(path, "/trash") {
			return 20
		}
		return 10
	}
	if query.Get("format") == "full" {
		return 120
	}
	return 40
}

func (c *Client) waitRequest(ctx context.Context, cost int) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	select {
	case c.slot <- struct{}{}:
	case <-ctx.Done():
		return ctx.Err()
	}
	defer func() { <-c.slot }()
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		c.paceMu.Lock()
		if remaining := time.Until(c.limitedUntil); remaining > 0 {
			err := *c.lastLimit
			err.retryAfter = remaining
			c.paceMu.Unlock()
			return &err
		}
		wait := time.Until(c.nextRequest)
		if wait <= 0 {
			// 4,800 units/minute leaves headroom below Gmail's 6,000-unit user limit.
			c.nextRequest = time.Now().Add(time.Duration(cost) * time.Second / 80)
			c.paceMu.Unlock()
			return nil
		}
		c.paceMu.Unlock()
		timer := time.NewTimer(wait)
		select {
		case <-timer.C:
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		}
	}
}

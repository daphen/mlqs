package gmail

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
	"testing/synctest"
	"time"
)

type quotaTransport func(*http.Request) (*http.Response, error)

func (f quotaTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func quotaClient(transport quotaTransport) *Client {
	c := New(context.Background(), nil)
	c.hc = &http.Client{Transport: transport}
	return c
}
func quotaResponse(status int, body string) *http.Response {
	return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}
}

func TestGmailPacesMetadataAndFullReadsByCost(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		var calls []time.Time
		var mu sync.Mutex
		c := quotaClient(func(r *http.Request) (*http.Response, error) {
			mu.Lock()
			calls = append(calls, time.Now())
			mu.Unlock()
			body := `{}`
			if strings.HasSuffix(r.URL.Path, "/threads") {
				body = `{"threads":[{"id":"one"},{"id":"two"}]}`
			}
			return quotaResponse(200, body), nil
		})
		if _, err := c.ListConversations(context.Background(), "INBOX", "", 2, false); err != nil {
			t.Fatal(err)
		}
		if _, err := c.GetConversation(context.Background(), "one"); err != nil {
			t.Fatal(err)
		}
		if _, _, err := c.Profile(context.Background()); err != nil {
			t.Fatal(err)
		}
		if len(calls) != 5 {
			t.Fatalf("calls=%d", len(calls))
		}
		for i, want := range []time.Duration{125 * time.Millisecond, 500 * time.Millisecond, 500 * time.Millisecond, 1500 * time.Millisecond} {
			if got := calls[i+1].Sub(calls[i]); got != want {
				t.Fatalf("request %d gap=%v want=%v", i+1, got, want)
			}
		}
	})
}

func TestGmailQuotaStopsFanoutAndCoolsDownOnlyThatAccount(t *testing.T) {
	for _, response := range []struct {
		name   string
		status int
		body   string
		retry  string
	}{
		{"observed-403", 403, `{"error":{"message":"Quota exceeded for quota metric 'Total Query Cost' and limit 'Units per minute per user'"}}`, ""},
		{"structured-403", 403, `{"error":{"message":"User-rate limit exceeded","errors":[{"reason":"userRateLimitExceeded"}]}}`, "75"},
		{"429", 429, `{"error":{"message":"Too many requests"}}`, ""},
	} {
		t.Run(response.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				calls := 0
				limited := true
				stubs := make([]string, 50)
				for i := range stubs {
					stubs[i] = fmt.Sprintf(`{"id":"thread-%d"}`, i)
				}
				c := quotaClient(func(r *http.Request) (*http.Response, error) {
					calls++
					if r.URL.Path == "/gmail/v1/users/me/threads" {
						return quotaResponse(200, `{"threads":[`+strings.Join(stubs, ",")+`]}`), nil
					}
					if !limited {
						return quotaResponse(200, `{}`), nil
					}
					resp := quotaResponse(response.status, response.body)
					resp.Header.Set("Retry-After", response.retry)
					return resp, nil
				})
				page, err := c.ListConversations(context.Background(), "INBOX", "", 50, false)
				var throttle interface {
					RateLimited() bool
					RetryAfter() time.Duration
				}
				if !errors.As(err, &throttle) || !throttle.RateLimited() || len(page.Conversations) != 0 || calls != 2 {
					t.Fatalf("err=%v rows=%d requests=%d", err, len(page.Conversations), calls)
				}
				if _, _, err := c.Profile(context.Background()); err == nil || calls != 2 {
					t.Fatalf("cooldown made another request: calls=%d err=%v", calls, err)
				}
				otherCalls := 0
				other := quotaClient(func(*http.Request) (*http.Response, error) { otherCalls++; return quotaResponse(200, `{}`), nil })
				if _, _, err := other.Profile(context.Background()); err != nil || otherCalls != 1 {
					t.Fatal("one account blocked another", err)
				}
				limited = false
				time.Sleep(throttle.RetryAfter())
				if _, _, err := c.Profile(context.Background()); err != nil || calls != 3 {
					t.Fatalf("did not resume: calls=%d err=%v", calls, err)
				}
			})
		})
	}
}

func TestGmailCancellationAndNonQuotaForbidden(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		calls := 0
		c := quotaClient(func(r *http.Request) (*http.Response, error) {
			calls++
			if strings.HasSuffix(r.URL.Path, "/threads") {
				return quotaResponse(200, `{"threads":[{"id":"one"}]}`), nil
			}
			return quotaResponse(403, `{"error":{"message":"Insufficient Permission"}}`), nil
		})
		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()
		if page, err := c.ListConversations(ctx, "INBOX", "", 1, false); !errors.Is(err, context.DeadlineExceeded) || len(page.Conversations) != 0 || calls != 1 {
			t.Fatalf("canceled scan: calls=%d page=%v err=%v", calls, page, err)
		}
		_, err := c.GetConversation(context.Background(), "one")
		var rate interface{ RateLimited() bool }
		if !errors.As(err, &rate) || rate.RateLimited() {
			t.Fatalf("permission error classified as quota: %v", err)
		}
		c.GetConversation(context.Background(), "two")
		if calls != 3 {
			t.Fatalf("permission error caused cooldown: requests=%d", calls)
		}
	})
}

func TestGmailUnreadIDsDoNotFetchMetadata(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		calls := 0
		c := quotaClient(func(r *http.Request) (*http.Response, error) {
			calls++
			if r.URL.Path != "/gmail/v1/users/me/threads" || r.URL.Query().Get("q") != "is:unread" || r.URL.Query().Get("labelIds") != "INBOX" || r.URL.Query().Get("pageToken") != "older" {
				t.Errorf("wrong ID request: %s", r.URL)
			}
			return quotaResponse(200, `{"threads":[{"id":"one"},{"id":"two"}],"nextPageToken":"next"}`), nil
		})
		ids, next, err := c.UnreadConversationIDs(context.Background(), "INBOX", "older", 100)
		if err != nil || strings.Join(ids, ",") != "one,two" || next != "next" || calls != 1 {
			t.Fatalf("ids=%v next=%s calls=%d err=%v", ids, next, calls, err)
		}
	})
}

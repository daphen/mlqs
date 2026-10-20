package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sync"
	"testing"
	"time"

	"mlqs/internal/cache"
	"mlqs/internal/config"
	"mlqs/internal/provider"
)

type unreadIDProvider struct {
	provider.Provider
	pages    int
	metadata int
}

func (p *unreadIDProvider) ListConversations(_ context.Context, folder, cursor string, _ int, unread bool) (provider.Page, error) {
	if unread {
		ids, next, err := p.UnreadConversationIDs(context.Background(), folder, cursor, 100)
		if err != nil {
			return provider.Page{}, err
		}
		var rows []provider.Conversation
		for _, id := range ids {
			row, err := p.GetConversationMeta(context.Background(), id)
			if err != nil {
				return provider.Page{}, err
			}
			rows = append(rows, row)
		}
		return provider.Page{Conversations: rows, NextCursor: next}, nil
	}
	var rows []provider.Conversation
	for i := 0; i < 50; i++ {
		rows = append(rows, provider.Conversation{ID: fmt.Sprint(i), Unread: true, FolderIDs: []string{folder}})
	}
	return provider.Page{Conversations: rows}, nil
}
func (p *unreadIDProvider) UnreadConversationIDs(_ context.Context, _, cursor string, _ int) ([]string, string, error) {
	p.pages++
	from, to, next := 0, 100, "older"
	if cursor != "" {
		from, to, next = 100, 199, ""
	}
	var ids []string
	for i := from; i < to; i++ {
		ids = append(ids, fmt.Sprint(i))
	}
	return ids, next, nil
}
func (p *unreadIDProvider) GetConversationMeta(_ context.Context, id string) (provider.Conversation, error) {
	p.metadata++
	return provider.Conversation{ID: id, Subject: "New unread", Unread: true, FolderIDs: []string{"INBOX"}}, nil
}

func TestUnreadRefreshReusesCacheAndReconcilesIDs(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	db, err := cache.Open()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var rows []provider.Conversation
	for i := 0; i < 198; i++ {
		rows = append(rows, provider.Conversation{ID: fmt.Sprint(i), Subject: "Cached", Unread: true, FolderIDs: []string{"INBOX"}})
	}
	rows = append(rows, provider.Conversation{ID: "no-longer-unread", Unread: true, FolderIDs: []string{"INBOX"}})
	db.UpsertConversations("work", rows)
	p := &unreadIDProvider{}
	d := &daemon{db: db, providers: map[string]provider.Provider{"work": p}}
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	client.SetDeadline(time.Now().Add(3 * time.Second))
	done := make(chan struct{})
	go func() {
		d.handle(server, command{Type: "conversations", Account: "work", Folder: "INBOX"})
		close(done)
	}()
	dec := json.NewDecoder(client)
	for i := 0; i < 2; i++ {
		var event map[string]any
		if err := dec.Decode(&event); err != nil {
			t.Fatal(err)
		}
	}
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("backfill did not finish")
	}
	if p.pages != 2 || p.metadata != 1 {
		t.Fatalf("ID pages=%d metadata fetches=%d; want two cheap lists and only one missing thread", p.pages, p.metadata)
	}
	cached := db.CachedConversations("work", "INBOX", 250)
	unread := 0
	newFound := false
	for _, row := range cached {
		if row.Unread {
			unread++
		}
		if row.ID == "198" && row.Subject == "New unread" {
			newFound = true
		}
		if row.ID == "no-longer-unread" && row.Unread {
			t.Fatal("read reconciliation lost")
		}
	}
	if unread != 199 || !newFound {
		t.Fatalf("unread=%d new=%v", unread, newFound)
	}
}

type minuteQuota struct{}

func (minuteQuota) Error() string             { return "gmail: 403 Quota exceeded for Units per minute per user" }
func (minuteQuota) RateLimited() bool         { return true }
func (minuteQuota) RetryAfter() time.Duration { return time.Millisecond }

type quotaReadProvider struct {
	provider.Provider
	mu    sync.Mutex
	calls int
}

func (p *quotaReadProvider) MarkRead(context.Context, string, bool) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls++
	if p.calls == 1 {
		return minuteQuota{}
	}
	return nil
}
func (p *quotaReadProvider) ListFolders(context.Context) ([]provider.Folder, error) {
	return []provider.Folder{{ID: "INBOX", Role: "inbox"}}, nil
}
func TestReadRetriesTypedMinuteQuotaThroughSocket(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	db, err := cache.Open()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	p := &quotaReadProvider{}
	d := &daemon{cfg: &config.Config{Accounts: []config.Account{{Name: "work"}}}, db: db, providers: map[string]provider.Provider{"work": p}, conns: map[net.Conn]struct{}{}, readPace: time.Millisecond, folderRefreshDelay: time.Millisecond}
	client, server := net.Pipe()
	defer client.Close()
	client.SetDeadline(time.Now().Add(3 * time.Second))
	go d.serve(server)
	dec := json.NewDecoder(client)
	for i := 0; i < 2; i++ {
		var event map[string]any
		if err := dec.Decode(&event); err != nil {
			t.Fatal(err)
		}
	}
	if err := json.NewEncoder(client).Encode(command{Type: "markread", Account: "work", ID: "one", Text: "true"}); err != nil {
		t.Fatal(err)
	}
	var event map[string]any
	if err := dec.Decode(&event); err != nil {
		t.Fatal(err)
	}
	if event["type"] != "folders" {
		t.Fatalf("quota was not retried: %v", event)
	}
	p.mu.Lock()
	calls := p.calls
	p.mu.Unlock()
	if calls != 2 {
		t.Fatalf("mark calls=%d", calls)
	}
	close(d.readLanes["work"].jobs)
}

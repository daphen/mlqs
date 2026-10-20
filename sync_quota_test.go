package main

import (
	"context"
	"testing"
	"time"

	"mlqs/internal/cache"
	"mlqs/internal/provider"
)

type syncQuotaProvider struct {
	provider.Provider
	limited bool
}

func (p *syncQuotaProvider) Delta(context.Context, string) (provider.Delta, error) {
	return provider.Delta{Changed: []string{"keep"}, NextToken: "new"}, nil
}
func (p *syncQuotaProvider) GetConversationMeta(context.Context, string) (provider.Conversation, error) {
	if p.limited {
		return provider.Conversation{}, minuteQuota{}
	}
	return provider.Conversation{ID: "keep", Subject: "Kept", FolderIDs: []string{"INBOX"}}, nil
}
func (p *syncQuotaProvider) ListFolders(context.Context) ([]provider.Folder, error) { return nil, nil }

func TestQuotaDuringSyncKeepsMailAndRetriesDelta(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	db, err := cache.Open()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.UpsertConversations("work", []provider.Conversation{{ID: "keep", Subject: "Kept", FolderIDs: []string{"INBOX"}}})
	db.SetDeltaToken("work", "old", time.Now().Unix())
	d := &daemon{db: db}
	p := &syncQuotaProvider{limited: true}
	d.syncOnce("work", p)
	if rows := db.CachedConversations("work", "INBOX", 10); len(rows) != 1 {
		t.Fatalf("quota removed cached mail: %v", rows)
	}
	if token := db.DeltaToken("work"); token != "old" {
		t.Fatalf("quota skipped the failed delta: %s", token)
	}
	p.limited = false
	d.syncOnce("work", p)
	if token := db.DeltaToken("work"); token != "new" {
		t.Fatalf("successful retry did not advance delta: %s", token)
	}
}

package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"testing"
	"time"

	"mlqs/internal/cache"
	"mlqs/internal/config"
	"mlqs/internal/provider"
)

type failedListProvider struct{ provider.Provider }

func (failedListProvider) ListConversations(context.Context, string, string, int, bool) (provider.Page, error) {
	return provider.Page{}, errors.New("gmail: 429 Quota exceeded")
}

func TestFailedListIdentifiesAccountAndOperation(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	db, err := cache.Open()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	d := &daemon{
		cfg: &config.Config{Accounts: []config.Account{{Name: "work"}}},
		db:  db, providers: map[string]provider.Provider{"work": failedListProvider{}},
		conns: map[net.Conn]struct{}{},
	}
	client, server := net.Pipe()
	defer client.Close()
	client.SetDeadline(time.Now().Add(3 * time.Second))
	go d.serve(server)
	dec := json.NewDecoder(client)
	for i := 0; i < 2; i++ {
		var bootstrap map[string]any
		if err := dec.Decode(&bootstrap); err != nil {
			t.Fatal(err)
		}
	}
	if err := json.NewEncoder(client).Encode(command{Type: "conversations", Account: "work", Folder: "INBOX"}); err != nil {
		t.Fatal(err)
	}
	var event struct{ Type, Account, Operation, Text string }
	if err := dec.Decode(&event); err != nil {
		t.Fatal(err)
	}
	if event.Type != "toast" || event.Account != "work" || event.Operation != "conversations" || event.Text != "mlqs conversations: gmail: 429 Quota exceeded" {
		t.Fatalf("failed request reply = %#v", event)
	}
}

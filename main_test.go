package main

import (
	"context"
	"encoding/json"
	"net"
	"testing"

	"mlqs/internal/provider"

	"golang.org/x/oauth2"
)

type expiredProvider struct {
	provider.Provider
}

func (expiredProvider) GetConversation(context.Context, string) ([]provider.Message, error) {
	return nil, &oauth2.RetrieveError{ErrorCode: "invalid_grant"}
}

func TestConversationExpiredSessionRequestsAuthentication(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	d := &daemon{providers: map[string]provider.Provider{"work": expiredProvider{}}}
	go d.handle(server, command{Type: "conversation", Account: "work", ID: "thread-1"})

	var event map[string]any
	if err := json.NewDecoder(client).Decode(&event); err != nil {
		t.Fatal(err)
	}
	if event["type"] != "authRequired" || event["account"] != "work" ||
		event["operation"] != "conversation" || event["id"] != "thread-1" {
		t.Fatalf("unexpected event: %#v", event)
	}
}

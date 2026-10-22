package main

import (
	"context"
	"testing"
	"time"

	"mlqs/internal/config"
	"mlqs/internal/provider"
)

type calendarStub struct{}

func (calendarStub) Calendars(context.Context) ([]provider.Calendar, error) { return nil, nil }
func (calendarStub) Events(context.Context, string, time.Time, time.Time) ([]provider.CalEvent, error) {
	return nil, nil
}
func (calendarStub) RSVP(context.Context, string, string, string) error { return nil }
func (calendarStub) FindByICalUID(context.Context, string, string) (*provider.CalEvent, error) {
	return nil, nil
}
func (calendarStub) Create(context.Context, string, provider.NewEvent) (*provider.CalEvent, error) {
	return nil, nil
}

func TestAccountsPayloadAdvertisesCalendarCapability(t *testing.T) {
	d := &daemon{
		cfg: &config.Config{Accounts: []config.Account{
			{Name: "work", Vendor: "outlook", Email: "work@example.com"},
			{Name: "spam", Vendor: "imap", Email: "spam@example.com"},
		}},
		cals: map[string]provider.CalendarProvider{"work": calendarStub{}},
	}
	payload := d.accountsPayload()
	workspaces, ok := payload["workspaces"].([]map[string]any)
	if !ok || len(workspaces) != 2 {
		t.Fatalf("unexpected workspaces: %#v", payload["workspaces"])
	}
	if workspaces[0]["calendar"] != true {
		t.Fatalf("work calendar capability = %#v", workspaces[0]["calendar"])
	}
	if workspaces[1]["calendar"] != false {
		t.Fatalf("spam calendar capability = %#v", workspaces[1]["calendar"])
	}
}

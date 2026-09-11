package graph

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func jsonResponse(body string) *http.Response {
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     http.Header{"Content-Type": {"application/json"}},
		Body:       io.NopCloser(strings.NewReader(body)),
	}
}

func TestAPICalTimeParsesPacificWindowsZone(t *testing.T) {
	got := (apiCalTime{DateTime: "2026-07-01T13:00:00", TimeZone: "Pacific Standard Time"}).parse()
	if want := "2026-07-01T20:00:00Z"; got.UTC().Format(time.RFC3339) != want {
		t.Fatalf("parsed time = %s, want %s", got.UTC().Format(time.RFC3339), want)
	}
}

func TestGetConversationExpandsEventMessageAndCountsConflicts(t *testing.T) {
	client := &Client{
		wellKnown: map[string]string{},
		hc: &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			switch {
			case r.URL.Path == "/v1.0/me/messages" && r.URL.Query().Get("$filter") != "":
				return jsonResponse(`{"value":[{
					"@odata.type":"#microsoft.graph.eventMessageRequest",
					"id":"message-1","conversationId":"conversation-1","subject":"Meeting",
					"receivedDateTime":"2026-08-19T11:46:14Z","hasAttachments":false,
					"body":{"contentType":"html","content":"<p>Agenda</p>"}
				}]}`), nil
			case r.URL.Path == "/v1.0/me/messages/message-1":
				if got := r.URL.Query().Get("$expand"); got != "microsoft.graph.eventMessage/event" {
					t.Fatalf("unexpected expand: %q", got)
				}
				return jsonResponse(`{
					"@odata.type":"#microsoft.graph.eventMessageRequest",
					"meetingMessageType":"meetingRequest","responseRequested":true,
					"event":{"id":"event-1","iCalUId":"invite-uid",
						"start":{"dateTime":"2026-09-01T13:00:00","timeZone":"W. Europe Standard Time"},
						"end":{"dateTime":"2026-09-01T14:30:00","timeZone":"W. Europe Standard Time"},
						"location":{"displayName":"Room 9"},
						"responseStatus":{"response":"notResponded"},"showAs":"tentative"
					}
				}`), nil
			case r.URL.Path == "/v1.0/me/calendarView":
				if got := r.URL.Query().Get("startDateTime"); got != "2026-09-01T11:00:00Z" {
					t.Fatalf("conflict query start = %q, want Windows-zone time converted to UTC", got)
				}
				return jsonResponse(`{"value":[
					{"id":"conflict-1","iCalUId":"other-uid","showAs":"busy"},
					{"id":"event-1","iCalUId":"invite-uid","showAs":"tentative"},
					{"id":"free-1","iCalUId":"free-uid","showAs":"free"},
					{"id":"cancelled-1","iCalUId":"cancelled-uid","showAs":"busy","isCancelled":true}
				]}`), nil
			default:
				t.Fatalf("unexpected Graph request: %s?%s", r.URL.Path, r.URL.RawQuery)
				return nil, nil
			}
		})},
	}

	messages, err := client.GetConversation(context.Background(), "conversation-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(messages) != 1 || messages[0].Meeting == nil {
		t.Fatalf("expected one meeting message, got %#v", messages)
	}
	meeting := messages[0].Meeting
	if meeting.EventID != "event-1" || meeting.ICalUID != "invite-uid" {
		t.Fatalf("wrong event identity: %#v", meeting)
	}
	if got := meeting.End.Sub(meeting.Start).Minutes(); got != 90 {
		t.Fatalf("duration = %v minutes, want 90", got)
	}
	if meeting.Location != "Room 9" || meeting.Response != "needsAction" || !meeting.ResponseNeeded {
		t.Fatalf("wrong meeting metadata: %#v", meeting)
	}
	if meeting.ConflictCount != 1 {
		t.Fatalf("conflicts = %d, want 1", meeting.ConflictCount)
	}
}

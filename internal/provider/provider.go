// Package provider defines the vendor-blind mail interface. Gmail and
// Microsoft Graph each implement it; everything above is vendor-agnostic.
package provider

import (
	"context"
	"time"
)

type Address struct {
	Name  string
	Email string
}

// Role classifies well-known folders so the UI can order and glyph them
// without vendor knowledge: inbox|starred|sent|drafts|archive|spam|trash|label.
type Folder struct {
	ID     string
	Name   string
	Role   string
	Unread int
	Total  int
}

type Attachment struct {
	ID        string
	Name      string
	MIME      string
	Size      int64
	Inline    bool
	ContentID string
}

type Message struct {
	ID          string
	ConvID      string
	From        Address
	To, Cc, Bcc []Address
	Subject     string
	Snippet     string
	BodyHTML    string
	BodyText    string
	Date        time.Time
	Unread      bool
	Starred     bool
	Attachments []Attachment
}

type Conversation struct {
	ID        string
	Subject   string
	Snippet   string
	Senders   []Address
	Date      time.Time
	Unread    bool
	Starred   bool
	HasAttach bool
	MsgCount  int
	FolderIDs []string
}

type Page struct {
	Conversations []Conversation
	NextCursor    string
}

// Delta reports what changed since a sync token. FullResync signals the
// token expired (Gmail history too old, Graph token invalidated) and the
// caller must re-list from scratch.
type Delta struct {
	Changed    []string
	Removed    []string
	NextToken  string
	FullResync bool
}

type Draft struct {
	To, Cc, Bcc     []Address
	Subject         string
	BodyText        string
	InReplyTo       string // message ID being replied to; threads on the vendor side
	ConvID          string
	AttachmentPaths []string
}

type Provider interface {
	ListFolders(ctx context.Context) ([]Folder, error)
	ListConversations(ctx context.Context, folderID, cursor string, limit int) (Page, error)
	GetConversation(ctx context.Context, id string) ([]Message, error)
	Delta(ctx context.Context, sinceToken string) (Delta, error)
	Send(ctx context.Context, d Draft) error
	MarkRead(ctx context.Context, convID string, read bool) error
	Star(ctx context.Context, convID string, starred bool) error
	Archive(ctx context.Context, convID string) error
	Trash(ctx context.Context, convID string) error
	Search(ctx context.Context, q string, limit int) (Page, error)
}

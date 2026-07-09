// Package cache is the sqlite store — the single source the render path
// reads from, mirroring slqs's cache.db design.
package cache

import (
	"database/sql"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite"
)

type DB struct {
	*sql.DB
}

func dbPath() string {
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".local", "share")
	}
	return filepath.Join(base, "mlqs", "cache.db")
}

const schema = `
CREATE TABLE IF NOT EXISTS folders(
	account TEXT, id TEXT, name TEXT, role TEXT,
	unread INT DEFAULT 0, total INT DEFAULT 0,
	PRIMARY KEY(account, id));
CREATE TABLE IF NOT EXISTS conversations(
	account TEXT, id TEXT, folder_ids TEXT, subject TEXT, snippet TEXT,
	senders_json TEXT, date INT, unread INT, starred INT, has_attach INT,
	msg_count INT,
	PRIMARY KEY(account, id));
CREATE INDEX IF NOT EXISTS conv_date ON conversations(account, date DESC);
CREATE TABLE IF NOT EXISTS messages(
	account TEXT, id TEXT, conv_id TEXT,
	from_name TEXT, from_email TEXT, recipients_json TEXT,
	subject TEXT, date INT, unread INT, starred INT,
	body_text TEXT, body_html TEXT, attachments_json TEXT,
	PRIMARY KEY(account, id));
CREATE INDEX IF NOT EXISTS msg_conv ON messages(account, conv_id);
CREATE TABLE IF NOT EXISTS sync_state(
	account TEXT PRIMARY KEY, delta_token TEXT, synced_at INT);
`

func Open() (*DB, error) {
	p := dbPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", p+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	return &DB{db}, nil
}

func (d *DB) DeltaToken(account string) string {
	var t string
	d.QueryRow(`SELECT delta_token FROM sync_state WHERE account=?`, account).Scan(&t)
	return t
}

func (d *DB) SetDeltaToken(account, token string, syncedAt int64) error {
	_, err := d.Exec(`INSERT INTO sync_state(account, delta_token, synced_at) VALUES(?,?,?)
		ON CONFLICT(account) DO UPDATE SET delta_token=excluded.delta_token, synced_at=excluded.synced_at`,
		account, token, syncedAt)
	return err
}

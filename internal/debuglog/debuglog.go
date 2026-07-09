// Package debuglog: categorized debug logging, active when MLQS_DEBUG is set
// (writes ~/.cache/mlqs/debug.log). No-ops otherwise. Same design as slqs.
package debuglog

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sync/atomic"
)

var (
	enabled atomic.Bool
	logger  *log.Logger
)

func Init() (*os.File, error) {
	if os.Getenv("MLQS_DEBUG") == "" {
		enabled.Store(false)
		return nil, nil
	}
	dir := filepath.Join(os.Getenv("HOME"), ".cache", "mlqs")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	f, err := os.Create(filepath.Join(dir, "debug.log"))
	if err != nil {
		return nil, err
	}
	logger = log.New(f, "", log.Ltime|log.Lmicroseconds)
	enabled.Store(true)
	return f, nil
}

func write(tag, format string, args ...any) {
	if !enabled.Load() {
		return
	}
	logger.Printf("[%s] %s", tag, fmt.Sprintf(format, args...))
}

func IPC(format string, args ...any)  { write("ipc", format, args...) }
func Sync(format string, args ...any) { write("sync", format, args...) }
func API(format string, args ...any)  { write("api", format, args...) }
func Gen(format string, args ...any)  { write("gen", format, args...) }

var _ = io.Discard

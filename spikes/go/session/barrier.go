package session

import (
	"bufio"
	"bytes"
	"io"
	"sync"
	"time"
)

// notificationBarrier works around an ordering gap in acp-go-sdk v0.13.5:
// inbound notifications go through a sequential queue, but inbound requests
// (session/request_permission) are dispatched on their own goroutine straight
// away (connection.go:412). A permission request can therefore reach the
// client before session/update chunks the agent sent before it, and the UI
// would show the permission card above text that came first.
//
// The barrier counts notification lines as they come off the agent's stdout
// and counts SessionUpdate calls as they are handled. A request handler calls
// wait() to block until every notification read so far has been handled.
type notificationBarrier struct {
	mu       sync.Mutex
	cond     *sync.Cond
	received uint64
	handled  uint64
}

func newNotificationBarrier() *notificationBarrier {
	b := &notificationBarrier{}
	b.cond = sync.NewCond(&b.mu)
	return b
}

var updateMethod = []byte(`"session/update"`)

// wrap returns a reader that yields the same bytes as r, counting
// session/update notification lines before handing them on.
func (b *notificationBarrier) wrap(r io.Reader) io.Reader {
	pr, pw := io.Pipe()
	go func() {
		sc := bufio.NewScanner(r)
		sc.Buffer(make([]byte, 64*1024), 64*1024*1024)
		for sc.Scan() {
			line := sc.Bytes()
			// Notifications have a method and no id. A cheap check is enough
			// here: only the agent sends session/update, always as a notification.
			if bytes.Contains(line, updateMethod) {
				b.mu.Lock()
				b.received++
				b.mu.Unlock()
			}
			if _, err := pw.Write(append(append([]byte{}, line...), '\n')); err != nil {
				return
			}
		}
		pw.CloseWithError(sc.Err())
	}()
	return pr
}

func (b *notificationBarrier) done() {
	b.mu.Lock()
	b.handled++
	b.cond.Broadcast()
	b.mu.Unlock()
}

// wait blocks until all notifications received so far are handled, or the
// timeout passes (so a lost notification can never wedge a permission prompt).
func (b *notificationBarrier) wait(timeout time.Duration) {
	b.mu.Lock()
	defer b.mu.Unlock()
	target := b.received
	expired := false
	t := time.AfterFunc(timeout, func() {
		b.mu.Lock()
		expired = true
		b.cond.Broadcast()
		b.mu.Unlock()
	})
	defer t.Stop()
	for b.handled < target && !expired {
		b.cond.Wait()
	}
}

// Package httpx builds HTTP transports that survive network changes: after a
// suspend/resume or Wi-Fi hop, pooled keep-alive connections turn into black
// holes (no RST ever arrives). Dialer keepalives + HTTP/2 read-idle pings
// detect the corpse in seconds and re-dial instead of wedging every request
// until its context deadline.
package httpx

import (
	"net"
	"net/http"
	"time"

	"golang.org/x/net/http2"
)

func Transport() *http.Transport {
	t := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   10 * time.Second,
			KeepAlive: 15 * time.Second,
		}).DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          20,
		IdleConnTimeout:       60 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
	}
	if h2, err := http2.ConfigureTransports(t); err == nil {
		h2.ReadIdleTimeout = 15 * time.Second
		h2.PingTimeout = 10 * time.Second
	}
	return t
}

func Client(timeout time.Duration) *http.Client {
	return &http.Client{Transport: Transport(), Timeout: timeout}
}

// langsmith-proxy: identity-aware access proxy for LangSmith access from Coder
// PHI workspaces (PRODSEC-580). Workspaces never hold a LangSmith credential;
// callers are resolved mesh identity -> Coder owner and forwarded to a Teleport-aware
// broker using an audience-bound workload identity token.
//
// Caller identity comes from the XFCC header that the inbound Istio sidecar
// replaces from the authenticated mTLS peer certificate. The application
// resolves that SPIFFE service account to Coder-owned Kubernetes metadata.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	listenAddr = ":8080"

	saTokenPath     = "/var/run/secrets/kubernetes.io/serviceaccount/token"
	saCAPath        = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
	saNamespacePath = "/var/run/secrets/kubernetes.io/serviceaccount/namespace"

	// Only pods carrying the PHI workspace label may use the proxy.
	workspaceNameLabel   = "app.kubernetes.io/name"
	workspaceNameValue   = "coder-phi-workspace"
	ownerIDLabel         = "com.coder.user.id"
	ownerEmailAnnotation = "com.coder.user.email"
	workspaceIDLabel     = "com.coder.workspace.id"
	workspaceSAPrefix    = "coder-phi-"

	metadataIdentityURL = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity"
)

// postAllowlist: read-style LangSmith endpoints that use POST. Everything else
// non-GET/HEAD is denied so the key can only be used to pull traces, not
// write or administer.
var postAllowlist = map[string]bool{
	"/api/v1/runs/query":      true,
	"/api/v1/datasets/search": true,
}

// getAllowlist contains the LangSmith resources used by the read-only SDK
// workflows in PHI workspaces. Unknown and future API resources fail closed.
var getAllowlist = []string{
	"/api/v1/info",
	"/api/v1/runs",
	"/api/v1/sessions",
	"/api/v1/datasets",
	"/api/v1/examples",
}

var workspaceServiceAccountPattern = regexp.MustCompile(
	`^coder-phi-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`,
)

type caller struct {
	userID         string
	userEmail      string
	workspaceID    string
	serviceAccount string
}

type serviceAccountResolver struct {
	client    *http.Client
	apiServer string
	namespace string
	tokenPath string
}

type serviceAccountMetadata struct {
	Name        string            `json:"name"`
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
}

func newServiceAccountResolver() (*serviceAccountResolver, error) {
	caPEM, err := os.ReadFile(saCAPath)
	if err != nil {
		return nil, fmt.Errorf("read serviceaccount CA: %w", err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(caPEM) {
		return nil, fmt.Errorf("parse serviceaccount CA")
	}
	ns, err := os.ReadFile(saNamespacePath)
	if err != nil {
		return nil, fmt.Errorf("read serviceaccount namespace: %w", err)
	}
	return &serviceAccountResolver{
		client: &http.Client{
			Timeout:   5 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool}},
		},
		apiServer: "https://" + net.JoinHostPort(
			os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")),
		namespace: strings.TrimSpace(string(ns)),
		tokenPath: saTokenPath,
	}, nil
}

// meshIdentity extracts the single SPIFFE workload identity authenticated by
// the inbound Istio sidecar. Istio is configured to replace, rather than
// append to, caller-supplied XFCC values; rejecting multiple URI fields keeps
// the application fail-closed if that behavior changes.
func meshIdentity(xfccValues []string) (string, string, bool) {
	var identities [][2]string
	for _, field := range strings.FieldsFunc(strings.Join(xfccValues, ","), func(r rune) bool {
		return r == ';' || r == ','
	}) {
		field = strings.TrimSpace(field)
		if !strings.HasPrefix(field, "URI=") {
			continue
		}
		raw := strings.TrimPrefix(field, "URI=")
		u, err := url.Parse(raw)
		if err != nil || u.Scheme != "spiffe" || u.Host == "" || u.User != nil ||
			u.RawQuery != "" || u.Fragment != "" || u.RawPath != "" {
			return "", "", false
		}
		parts := strings.Split(strings.Trim(u.Path, "/"), "/")
		if len(parts) != 4 || parts[0] != "ns" || parts[1] == "" ||
			parts[2] != "sa" || parts[3] == "" {
			return "", "", false
		}
		identities = append(identities, [2]string{parts[1], parts[3]})
	}
	if len(identities) != 1 {
		return "", "", false
	}
	return identities[0][0], identities[0][1], true
}

func validWorkspaceServiceAccount(serviceAccount string) bool {
	return workspaceServiceAccountPattern.MatchString(serviceAccount)
}

// resolve maps an exact per-workspace Kubernetes service account to its Coder
// owner metadata. Shared/default identities and tampered metadata fail closed.
func (r *serviceAccountResolver) resolve(serviceAccount string) (caller, bool, error) {
	// Bound service account token is rotated by kubelet; read per lookup.
	token, err := os.ReadFile(r.tokenPath)
	if err != nil {
		return caller{}, false, fmt.Errorf("read serviceaccount token: %w", err)
	}

	u := fmt.Sprintf("%s/api/v1/namespaces/%s/serviceaccounts/%s",
		r.apiServer, url.PathEscape(r.namespace), url.PathEscape(serviceAccount))
	req, err := http.NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return caller{}, false, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))

	resp, err := r.client.Do(req)
	if err != nil {
		return caller{}, false, fmt.Errorf("serviceaccount lookup: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return caller{}, false, nil
	}
	if resp.StatusCode != http.StatusOK {
		return caller{}, false, fmt.Errorf("serviceaccount lookup: apiserver returned %d", resp.StatusCode)
	}

	var serviceAccountRecord struct {
		Metadata serviceAccountMetadata `json:"metadata"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&serviceAccountRecord); err != nil {
		return caller{}, false, fmt.Errorf("decode serviceaccount: %w", err)
	}

	c, ok := callerFromServiceAccount(serviceAccount, serviceAccountRecord.Metadata)
	return c, ok, nil
}

func callerFromServiceAccount(serviceAccount string, metadata serviceAccountMetadata) (caller, bool) {
	labels := metadata.Labels
	workspaceID := labels[workspaceIDLabel]
	if metadata.Name != serviceAccount ||
		!validWorkspaceServiceAccount(serviceAccount) ||
		serviceAccount != workspaceSAPrefix+workspaceID ||
		labels[workspaceNameLabel] != workspaceNameValue ||
		labels[ownerIDLabel] == "" ||
		metadata.Annotations[ownerEmailAnnotation] == "" ||
		workspaceID == "" {
		return caller{}, false
	}

	return caller{
		userID:         labels[ownerIDLabel],
		userEmail:      strings.ToLower(metadata.Annotations[ownerEmailAnnotation]),
		workspaceID:    workspaceID,
		serviceAccount: serviceAccount,
	}, true
}

func matchesResourcePath(path, resource string) bool {
	return path == resource || strings.HasPrefix(path, resource+"/")
}

// authorize returns a denial reason, or "" if allowed. User authorization is
// evaluated by the broker against the current Teleport grant snapshot.
func authorize(method, path string) string {
	switch method {
	case http.MethodGet, http.MethodHead:
		for _, resource := range getAllowlist {
			if matchesResourcePath(path, resource) {
				return ""
			}
		}
		return "GET path not in read allowlist"
	case http.MethodPost:
		if postAllowlist[strings.TrimSuffix(path, "/")] {
			return ""
		}
		return "POST path not in read allowlist"
	default:
		return "method not allowed (read-only proxy)"
	}
}

// auditRoute returns a bounded route label without logging caller-controlled
// path segments, which may contain identifiers or PHI.
func auditRoute(path string) string {
	trimmed := strings.TrimSuffix(path, "/")
	if postAllowlist[trimmed] {
		return trimmed
	}
	for _, resource := range getAllowlist {
		if path == resource || path == resource+"/" {
			return resource
		}
		if strings.HasPrefix(path, resource+"/") {
			return resource + "/:resource"
		}
	}
	if strings.HasPrefix(path, "/api/") {
		return "/api/:unrecognized"
	}
	return "/:non-api"
}

type identityTokenProvider struct {
	client   *http.Client
	endpoint string
	audience string

	mu        sync.Mutex
	token     string
	refreshAt time.Time
}

func newIdentityTokenProvider(endpoint, audience string) *identityTokenProvider {
	return &identityTokenProvider{
		client:   &http.Client{Timeout: 5 * time.Second},
		endpoint: endpoint,
		audience: audience,
	}
}

func (p *identityTokenProvider) get(ctx context.Context) (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	now := time.Now()
	if p.token != "" && now.Before(p.refreshAt) {
		return p.token, nil
	}

	u, err := url.Parse(p.endpoint)
	if err != nil {
		return "", fmt.Errorf("parse metadata identity endpoint: %w", err)
	}
	query := u.Query()
	query.Set("audience", p.audience)
	query.Set("format", "full")
	u.RawQuery = query.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return "", fmt.Errorf("create metadata identity request: %w", err)
	}
	req.Header.Set("Metadata-Flavor", "Google")
	resp, err := p.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("fetch workload identity token: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("metadata identity endpoint returned %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 32<<10))
	if err != nil {
		return "", fmt.Errorf("read workload identity token: %w", err)
	}
	token := strings.TrimSpace(string(body))
	if token == "" || len(token) >= 32<<10 {
		return "", fmt.Errorf("metadata identity endpoint returned an invalid token")
	}

	refreshAt := now.Add(5 * time.Minute)
	if expiry, ok := jwtExpiry(token); ok && expiry.After(now.Add(6*time.Minute)) {
		refreshAt = expiry.Add(-5 * time.Minute)
	}
	p.token = token
	p.refreshAt = refreshAt
	return token, nil
}

func jwtExpiry(token string) (time.Time, bool) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return time.Time{}, false
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return time.Time{}, false
	}
	var claims struct {
		ExpiresAt int64 `json:"exp"`
	}
	if err := json.Unmarshal(payload, &claims); err != nil || claims.ExpiresAt <= 0 {
		return time.Time{}, false
	}
	return time.Unix(claims.ExpiresAt, 0), true
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

type auditLine struct {
	Time           string `json:"time"`
	UserID         string `json:"user_id"`
	WorkspaceID    string `json:"workspace_id"`
	ServiceAccount string `json:"service_account"`
	Method         string `json:"method"`
	Route          string `json:"route"`
	Status         int    `json:"status"`
	DurationMS     int64  `json:"duration_ms"`
	DenyReason     string `json:"deny_reason,omitempty"`
}

func logRequest(c caller, method, route string, status int, d time.Duration, denyReason string) {
	_ = json.NewEncoder(os.Stdout).Encode(auditLine{
		Time:           time.Now().UTC().Format(time.RFC3339),
		UserID:         c.userID,
		WorkspaceID:    c.workspaceID,
		ServiceAccount: c.serviceAccount,
		Method:         method,
		Route:          route,
		Status:         status,
		DurationMS:     d.Milliseconds(),
		DenyReason:     denyReason,
	})
}

type brokerRequestContext struct {
	caller caller
	token  string
}

type brokerContextKey struct{}

func withBrokerRequest(r *http.Request, c caller, token string) *http.Request {
	ctx := context.WithValue(r.Context(), brokerContextKey{}, brokerRequestContext{
		caller: c,
		token:  token,
	})
	return r.WithContext(ctx)
}

func newReverseProxy(upstream *url.URL) *httputil.ReverseProxy {
	proxy := &httputil.ReverseProxy{Rewrite: func(pr *httputil.ProxyRequest) {
		pr.SetURL(upstream)
		pr.Out.Host = upstream.Host
		// Rewrite runs after hop-by-hop header removal, so callers cannot use a
		// Connection header to remove or replace the server-owned credentials.
		for _, header := range []string{
			"Authorization", "Cookie", "Forwarded", "Proxy-Authorization",
			"X-Api-Key", "X-Coder-User-Email", "X-Coder-User-Id",
			"X-Coder-Workspace-Id", "X-Coder-Workspace-Name",
			"X-Forwarded-Client-Cert",
			"X-Forwarded-For", "X-Forwarded-Host",
			"X-Forwarded-Proto", "X-Organization-Id", "X-Real-Ip",
			"X-Service-Key", "X-Tenant-Id",
		} {
			pr.Out.Header.Del(header)
		}
		brokerRequest, ok := pr.In.Context().Value(brokerContextKey{}).(brokerRequestContext)
		if !ok {
			pr.Out.URL.Scheme = "invalid"
			pr.Out.URL.Host = "missing-broker-identity"
			pr.Out.Host = ""
			return
		}
		pr.Out.Header.Set("Authorization", "Bearer "+brokerRequest.token)
		pr.Out.Header.Set("X-Coder-User-Id", brokerRequest.caller.userID)
		pr.Out.Header.Set("X-Coder-User-Email", brokerRequest.caller.userEmail)
		pr.Out.Header.Set("X-Coder-Workspace-Id", brokerRequest.caller.workspaceID)
	}}
	proxy.ErrorLog = log.New(io.Discard, "", 0)
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		http.Error(w, "broker upstream unavailable", http.StatusBadGateway)
	}
	return proxy
}

func main() {
	upstreamRaw := os.Getenv("UPSTREAM_URL")
	brokerAudience := strings.TrimSpace(os.Getenv("BROKER_AUDIENCE"))
	if upstreamRaw == "" || brokerAudience == "" {
		log.Fatal("UPSTREAM_URL and BROKER_AUDIENCE are required")
	}
	upstream, err := url.Parse(upstreamRaw)
	if err != nil {
		log.Fatalf("parse UPSTREAM_URL: %v", err)
	}
	if upstream.Scheme != "https" || upstream.Host == "" || upstream.User != nil ||
		upstream.RawQuery != "" || upstream.Fragment != "" {
		log.Fatal("UPSTREAM_URL must be an HTTPS URL without credentials, query, or fragment")
	}
	audienceURL, err := url.Parse(brokerAudience)
	if err != nil || audienceURL.Scheme != "https" || audienceURL.Host == "" ||
		audienceURL.User != nil || audienceURL.RawQuery != "" || audienceURL.Fragment != "" {
		log.Fatal("BROKER_AUDIENCE must be an HTTPS URL without credentials, query, or fragment")
	}

	resolver, err := newServiceAccountResolver()
	if err != nil {
		log.Fatalf("init serviceaccount resolver: %v", err)
	}

	proxy := newReverseProxy(upstream)
	tokenProvider := newIdentityTokenProvider(metadataIdentityURL, brokerAudience)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		identityNamespace, serviceAccount, validIdentity := meshIdentity(
			r.Header.Values("X-Forwarded-Client-Cert"),
		)
		c := caller{serviceAccount: serviceAccount}
		deny := func(status int, msg, reason string) {
			logRequest(c, r.Method, auditRoute(r.URL.Path), status, time.Since(start), reason)
			http.Error(w, msg, status)
		}
		if !validIdentity || identityNamespace != resolver.namespace ||
			!validWorkspaceServiceAccount(serviceAccount) {
			deny(http.StatusForbidden, "forbidden", "caller mesh identity is not a PHI workspace")
			return
		}

		c, ok, err := resolver.resolve(serviceAccount)
		if err != nil {
			log.Printf("resolve serviceaccount %s: %v", serviceAccount, err)
			deny(http.StatusBadGateway, "identity resolution failed", "identity resolution error")
			return
		}
		if !ok {
			deny(http.StatusForbidden, "forbidden", "caller serviceaccount is not a PHI workspace")
			return
		}

		// authorize() sees the decoded path but the proxy forwards the raw
		// one; reject any escaping so the two can never disagree.
		if r.URL.RawPath != "" && r.URL.RawPath != r.URL.Path {
			deny(http.StatusForbidden, "forbidden", "escaped characters in path")
			return
		}
		if reason := authorize(r.Method, r.URL.Path); reason != "" {
			deny(http.StatusForbidden, "forbidden: "+reason, reason)
			return
		}
		token, err := tokenProvider.get(r.Context())
		if err != nil {
			log.Printf("fetch broker identity: %v", err)
			deny(http.StatusBadGateway, "broker identity unavailable", "workload identity token unavailable")
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // query payloads are small JSON
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		proxy.ServeHTTP(rec, withBrokerRequest(r, c, token))
		logRequest(c, r.Method, auditRoute(r.URL.Path), rec.status, time.Since(start), "")
	})

	log.Printf("langsmith-proxy listening on %s, broker upstream %s", listenAddr, upstream.Host)
	srv := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	log.Fatal(srv.ListenAndServe())
}

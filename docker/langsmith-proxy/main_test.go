package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestAuthorize(t *testing.T) {
	cases := []struct {
		name   string
		method string
		path   string
		wantOK bool
	}{
		{"GET run", "GET", "/api/v1/runs/abc", true},
		{"HEAD sessions", "HEAD", "/api/v1/sessions", true},
		{"POST runs query", "POST", "/api/v1/runs/query", true},
		{"POST runs query trailing slash", "POST", "/api/v1/runs/query/", true},
		{"POST datasets search", "POST", "/api/v1/datasets/search", true},
		{"GET info", "GET", "/api/v1/info", true},
		{"GET datasets", "GET", "/api/v1/datasets", true},
		{"GET example", "GET", "/api/v1/examples/example-id", true},
		{"write POST", "POST", "/api/v1/runs", false},
		{"DELETE", "DELETE", "/api/v1/runs/abc", false},
		{"PATCH", "PATCH", "/api/v1/runs/abc", false},
		{"unknown resource", "GET", "/api/v1/orgs/current", false},
		{"lookalike resource", "GET", "/api/v1/runs-admin", false},
		{"non-api path", "GET", "/health", false},
	}
	allowlist, err := parseRouteAllowlist("")
	if err != nil {
		t.Fatalf("parseRouteAllowlist: %v", err)
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			reason := allowlist.authorize(tc.method, tc.path)
			if got := reason == ""; got != tc.wantOK {
				t.Errorf("authorize(%q, %q) = %q, want allowed=%v",
					tc.method, tc.path, reason, tc.wantOK)
			}
		})
	}
}

func TestWriteAllowlistScopesMethodsAndWildcards(t *testing.T) {
	allowlist, err := parseRouteAllowlist(`["POST /api/v1/datasets",` +
		`"PATCH /api/v1/examples/bulk",` +
		`"POST /api/v1/annotation-queues/*/runs",` +
		`"DELETE /api/v1/datasets/*"]`)
	if err != nil {
		t.Fatalf("parseRouteAllowlist: %v", err)
	}
	cases := []struct {
		method string
		path   string
		wantOK bool
	}{
		{"POST", "/api/v1/datasets", true},
		{"PATCH", "/api/v1/examples/bulk", true},
		{"POST", "/api/v1/annotation-queues/queue-id/runs", true},
		{"DELETE", "/api/v1/datasets/dataset-id", true},
		{"POST", "/api/v1/annotation-queues/a/b/runs", false},
		{"DELETE", "/api/v1/datasets/dataset-id/examples", false},
		{"GET", "/api/v1/datasets", false},
		{"POST", "/api/v1/runs/query", false},
	}
	for _, tc := range cases {
		reason := allowlist.authorize(tc.method, tc.path)
		if got := reason == ""; got != tc.wantOK {
			t.Errorf("authorize(%q, %q) = %q, want allowed=%v",
				tc.method, tc.path, reason, tc.wantOK)
		}
	}
	want := "/api/v1/annotation-queues/:resource/runs"
	if got := allowlist.label("/api/v1/annotation-queues/queue-id/runs"); got != want {
		t.Errorf("label = %q, want %q", got, want)
	}
}

func TestParseRouteAllowlistRejectsMalformedEntries(t *testing.T) {
	for _, raw := range []string{
		`["/api/v1/datasets"]`,
		`["OPTIONS /api/v1/datasets"]`,
		`["POST api/v1/datasets"]`,
		`["POST /"]`,
		`["POST /api/**/runs"]`,
		`["POST /api/v1/datasets/../orgs"]`,
		`[]`,
		`not-json`,
	} {
		if _, err := parseRouteAllowlist(raw); err == nil {
			t.Errorf("parseRouteAllowlist(%q) accepted a malformed allowlist", raw)
		}
	}
}

func TestHasDotSegment(t *testing.T) {
	for path, want := range map[string]bool{
		"/api/v1/runs/../orgs/current": true,
		"/api/v1/runs/./abc":           true,
		"/api/v1/runs/abc":             false,
		"/api/v1/runs/..abc":           false,
	} {
		if got := hasDotSegment(path); got != want {
			t.Errorf("hasDotSegment(%q) = %v, want %v", path, got, want)
		}
	}
}

func TestParseMaxBodyBytes(t *testing.T) {
	if got, err := parseMaxBodyBytes(""); err != nil || got != defaultMaxBodyBytes {
		t.Errorf("parseMaxBodyBytes(\"\") = %d, %v", got, err)
	}
	if got, err := parseMaxBodyBytes("33554432"); err != nil || got != 33554432 {
		t.Errorf("parseMaxBodyBytes(33554432) = %d, %v", got, err)
	}
	for _, raw := range []string{"0", "-1", "abc"} {
		if _, err := parseMaxBodyBytes(raw); err == nil {
			t.Errorf("parseMaxBodyBytes(%q) accepted an invalid cap", raw)
		}
	}
}

func TestMeshIdentity(t *testing.T) {
	tests := []struct {
		name          string
		values        []string
		wantNamespace string
		wantSA        string
		wantOK        bool
	}{
		{
			name:          "fleet trust domain",
			values:        []string{`By=spiffe://fleet/ns/istio-system/sa/ztunnel;Hash=abc;URI=spiffe://fleet.example/ns/coder/sa/coder-phi-d9549545-00b8-4911-8b76-cb3ae9dec890`},
			wantNamespace: "coder",
			wantSA:        "coder-phi-d9549545-00b8-4911-8b76-cb3ae9dec890",
			wantOK:        true,
		},
		{
			name:          "cluster local trust domain",
			values:        []string{`URI=spiffe://cluster.local/ns/coder/sa/coder-phi-d9549545-00b8-4911-8b76-cb3ae9dec890`},
			wantNamespace: "coder",
			wantSA:        "coder-phi-d9549545-00b8-4911-8b76-cb3ae9dec890",
			wantOK:        true,
		},
		{name: "missing XFCC", wantOK: false},
		{
			name:   "multiple identities",
			values: []string{`URI=spiffe://cluster.local/ns/coder/sa/coder-phi-one,URI=spiffe://cluster.local/ns/coder/sa/coder-phi-two`},
			wantOK: false,
		},
		{
			name:   "malformed path",
			values: []string{`URI=spiffe://cluster.local/ns/coder/coder-phi-workspace-id`},
			wantOK: false,
		},
		{
			name:   "non SPIFFE URI",
			values: []string{`URI=https://cluster.local/ns/coder/sa/coder-phi-workspace-id`},
			wantOK: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			namespace, serviceAccount, ok := meshIdentity(tc.values)
			if namespace != tc.wantNamespace || serviceAccount != tc.wantSA || ok != tc.wantOK {
				t.Errorf("meshIdentity() = (%q, %q, %v), want (%q, %q, %v)",
					namespace, serviceAccount, ok, tc.wantNamespace, tc.wantSA, tc.wantOK)
			}
		})
	}
}

func TestValidWorkspaceServiceAccount(t *testing.T) {
	for serviceAccount, want := range map[string]bool{
		"coder-phi-d9549545-00b8-4911-8b76-cb3ae9dec890": true,
		"coder-phi-workspace":                            false,
		"coder-phi-d9549545-00b8-4911-8b76-cb3ae9dec89":  false,
		"coder-phi-D9549545-00b8-4911-8b76-cb3ae9dec890": false,
		"default": false,
	} {
		if got := validWorkspaceServiceAccount(serviceAccount); got != want {
			t.Errorf("validWorkspaceServiceAccount(%q) = %v, want %v", serviceAccount, got, want)
		}
	}
}

func TestServiceAccountResolver(t *testing.T) {
	const (
		workspaceID    = "d9549545-00b8-4911-8b76-cb3ae9dec890"
		serviceAccount = workspaceSAPrefix + workspaceID
	)
	tokenPath := t.TempDir() + "/token"
	if err := os.WriteFile(tokenPath, []byte("test-token\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Errorf("method = %q", r.Method)
		}
		wantPath := "/api/v1/namespaces/coder/serviceaccounts/" + serviceAccount
		if r.URL.Path != wantPath {
			t.Errorf("path = %q, want %q", r.URL.Path, wantPath)
		}
		if r.Header.Get("Authorization") != "Bearer test-token" {
			t.Errorf("Authorization = %q", r.Header.Get("Authorization"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprintf(w, `{
			"metadata": {
				"name": %q,
				"labels": {
					%q: %q,
					%q: "user-id",
					%q: %q
				},
				"annotations": {%q: "USER@example.com"}
			}
		}`, serviceAccount, workspaceNameLabel, workspaceNameValue,
			ownerIDLabel, workspaceIDLabel, workspaceID, ownerEmailAnnotation)
	}))
	defer server.Close()

	resolver := &serviceAccountResolver{
		client:    server.Client(),
		apiServer: server.URL,
		namespace: "coder",
		tokenPath: tokenPath,
	}
	got, ok, err := resolver.resolve(serviceAccount)
	if err != nil {
		t.Fatal(err)
	}
	if !ok {
		t.Fatal("valid per-workspace service account did not resolve")
	}
	if got.userID != "user-id" || got.userEmail != "user@example.com" ||
		got.workspaceID != workspaceID || got.serviceAccount != serviceAccount {
		t.Errorf("caller = %#v", got)
	}
}

func TestCallerFromServiceAccountRejectsUntrustedMetadata(t *testing.T) {
	const workspaceID = "d9549545-00b8-4911-8b76-cb3ae9dec890"
	valid := serviceAccountMetadata{
		Name: workspaceSAPrefix + workspaceID,
		Labels: map[string]string{
			workspaceNameLabel: workspaceNameValue,
			ownerIDLabel:       "user-id",
			workspaceIDLabel:   workspaceID,
		},
		Annotations: map[string]string{ownerEmailAnnotation: "user@example.com"},
	}
	tests := []struct {
		name           string
		serviceAccount string
		mutate         func(*serviceAccountMetadata)
	}{
		{
			name:           "shared service account",
			serviceAccount: "coder-phi-workspace",
			mutate:         func(metadata *serviceAccountMetadata) { metadata.Name = "coder-phi-workspace" },
		},
		{
			name:           "name does not match workspace ID",
			serviceAccount: valid.Name,
			mutate: func(metadata *serviceAccountMetadata) {
				metadata.Labels[workspaceIDLabel] = "different-workspace"
			},
		},
		{
			name:           "wrong workload label",
			serviceAccount: valid.Name,
			mutate: func(metadata *serviceAccountMetadata) {
				metadata.Labels[workspaceNameLabel] = "other-workload"
			},
		},
		{
			name:           "missing owner",
			serviceAccount: valid.Name,
			mutate:         func(metadata *serviceAccountMetadata) { delete(metadata.Labels, ownerIDLabel) },
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			metadata := serviceAccountMetadata{
				Name: valid.Name,
				Labels: map[string]string{
					workspaceNameLabel: valid.Labels[workspaceNameLabel],
					ownerIDLabel:       valid.Labels[ownerIDLabel],
					workspaceIDLabel:   valid.Labels[workspaceIDLabel],
				},
				Annotations: map[string]string{ownerEmailAnnotation: valid.Annotations[ownerEmailAnnotation]},
			}
			tc.mutate(&metadata)
			if _, ok := callerFromServiceAccount(tc.serviceAccount, metadata); ok {
				t.Error("callerFromServiceAccount() accepted untrusted metadata")
			}
		})
	}
}

func TestAuditRoute(t *testing.T) {
	cases := map[string]string{
		"/api/v1/runs/query":                  "/api/v1/runs/query",
		"/api/v1/runs/sensitive-identifier":   "/api/v1/runs/:resource",
		"/api/v1/datasets/secret-name/":       "/api/v1/datasets/:resource",
		"/api/v1/orgs/sensitive-organization": "/api/:unrecognized",
		"/sensitive-non-api-path":             "/:non-api",
	}
	allowlist, err := parseRouteAllowlist("")
	if err != nil {
		t.Fatalf("parseRouteAllowlist: %v", err)
	}
	for path, want := range cases {
		if got := allowlist.label(path); got != want {
			t.Errorf("label(%q) = %q, want %q", path, got, want)
		}
	}
}

func TestReverseProxyOwnsBrokerIdentityAndCallerClaims(t *testing.T) {
	upstreamURL, err := url.Parse("https://langsmith.example.test/coder-broker")
	if err != nil {
		t.Fatal(err)
	}
	proxy := newReverseProxy(upstreamURL)
	req, err := http.NewRequest(http.MethodGet, "http://proxy/api/v1/runs/example", nil)
	if err != nil {
		t.Fatal(err)
	}
	for name, value := range map[string]string{
		"Authorization":           "Bearer caller-token",
		"Cookie":                  "caller-cookie=value",
		"Forwarded":               "for=caller",
		"X-Api-Key":               "caller-key",
		"X-Coder-User-Email":      "forged@example.com",
		"X-Coder-User-Id":         "forged-user",
		"X-Coder-Workspace-Id":    "forged-workspace",
		"X-Forwarded-Client-Cert": "URI=spiffe://attacker/ns/coder/sa/coder-phi-forged",
		"X-Forwarded-For":         "192.0.2.10",
		"X-Organization-Id":       "caller-org",
		"X-Service-Key":           "caller-service-key",
		"X-Tenant-Id":             "caller-tenant",
	} {
		req.Header.Set(name, value)
	}
	c := caller{
		userID:      "trusted-user-id",
		userEmail:   "trusted@example.com",
		workspaceID: "trusted-workspace-id",
	}
	req = withBrokerRequest(req, c, "workload-token")
	pr := &httputil.ProxyRequest{In: req, Out: req.Clone(req.Context())}
	proxy.Rewrite(pr)
	got := pr.Out

	if got.Header.Get("Authorization") != "Bearer workload-token" {
		t.Errorf("Authorization = %q", got.Header.Get("Authorization"))
	}
	if got.Header.Get("X-Coder-User-Id") != c.userID ||
		got.Header.Get("X-Coder-User-Email") != c.userEmail ||
		got.Header.Get("X-Coder-Workspace-Id") != c.workspaceID {
		t.Errorf("trusted caller claims not forwarded: %#v", got.Header)
	}
	if got.URL.Scheme != "https" || got.URL.Host != "langsmith.example.test" ||
		got.URL.Path != "/coder-broker/api/v1/runs/example" {
		t.Errorf("upstream target = %q", got.URL.String())
	}
	for _, header := range []string{
		"Cookie", "Forwarded", "X-Api-Key", "X-Forwarded-Client-Cert", "X-Forwarded-For",
		"X-Organization-Id", "X-Service-Key", "X-Tenant-Id",
	} {
		if value := got.Header.Get(header); value != "" {
			t.Errorf("%s reached broker with value %q", header, value)
		}
	}
}

func TestIdentityTokenProviderFetchesAndCachesAudienceToken(t *testing.T) {
	expires := time.Now().Add(time.Hour).Unix()
	payload := base64.RawURLEncoding.EncodeToString(
		[]byte(fmt.Sprintf(`{"exp":%d}`, expires)),
	)
	token := "header." + payload + ".signature"
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.Header.Get("Metadata-Flavor") != "Google" {
			t.Error("missing Metadata-Flavor header")
		}
		if r.URL.Query().Get("audience") != "https://broker.example/coder-broker" {
			t.Errorf("audience = %q", r.URL.Query().Get("audience"))
		}
		if r.URL.Query().Get("format") != "full" {
			t.Errorf("format = %q", r.URL.Query().Get("format"))
		}
		_, _ = w.Write([]byte(token))
	}))
	defer server.Close()

	provider := newIdentityTokenProvider(
		server.URL,
		"https://broker.example/coder-broker",
	)
	for range 2 {
		got, err := provider.get(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if got != token {
			t.Errorf("token = %q, want metadata token", got)
		}
	}
	if requests.Load() != 1 {
		t.Errorf("metadata requests = %d, want 1", requests.Load())
	}
}

func TestReverseProxyFailsClosedWithoutBrokerContext(t *testing.T) {
	upstreamURL, err := url.Parse("https://langsmith.example.test/coder-broker")
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequest(http.MethodGet, "http://proxy/api/v1/runs", nil)
	if err != nil {
		t.Fatal(err)
	}
	pr := &httputil.ProxyRequest{In: req, Out: req.Clone(req.Context())}
	newReverseProxy(upstreamURL).Rewrite(pr)
	if pr.Out.URL.Scheme != "invalid" || pr.Out.URL.Host != "missing-broker-identity" {
		t.Errorf("missing context target = %q", pr.Out.URL.String())
	}
}

func TestJWTExpiryRejectsMalformedToken(t *testing.T) {
	if _, ok := jwtExpiry("not-a-jwt"); ok {
		t.Fatal("malformed token unexpectedly had an expiry")
	}
	payload := base64.RawURLEncoding.EncodeToString([]byte(`{"no_exp":true}`))
	if _, ok := jwtExpiry(strings.Join([]string{"header", payload, "signature"}, ".")); ok {
		t.Fatal("token without exp unexpectedly had an expiry")
	}
}

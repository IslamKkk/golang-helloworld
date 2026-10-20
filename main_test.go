package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRoutes(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		statusCode int
		bodyPart   string
	}{
		{name: "home", path: "/", statusCode: http.StatusOK, bodyPart: "Hello from the diploma service"},
		{name: "health", path: "/healthz", statusCode: http.StatusOK, bodyPart: "{\"status\":\"ok\"}"},
		{name: "metrics", path: "/metrics", statusCode: http.StatusOK, bodyPart: "http_requests_total"},
		{name: "unknown route", path: "/missing", statusCode: http.StatusNotFound, bodyPart: "404 page not found"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, test.path, nil)
			response := httptest.NewRecorder()
			newHandler("test-version").ServeHTTP(response, request)

			if response.Code != test.statusCode {
				t.Fatalf("got status %d, want %d", response.Code, test.statusCode)
			}
			if !strings.Contains(response.Body.String(), test.bodyPart) {
				t.Fatalf("response body %q does not contain %q", response.Body.String(), test.bodyPart)
			}
		})
	}
}

func TestMetricsIncludeVersionAndRequestCount(t *testing.T) {
	handler := newHandler("release\"\\line")
	for _, path := range []string{"/", "/healthz", "/metrics"} {
		request := httptest.NewRequest(http.MethodGet, path, nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
	}

	request := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	body := response.Body.String()
	if !strings.Contains(body, "http_requests_total 4") {
		t.Fatalf("metrics do not report the expected request count: %s", body)
	}
	if !strings.Contains(body, "app_info{version=\"release\\\"\\\\line\"} 1") {
		t.Fatalf("metrics do not escape the version label: %s", body)
	}
}

func TestHealthRejectsNonGetMethod(t *testing.T) {
	request := httptest.NewRequest(http.MethodPost, "/healthz", nil)
	response := httptest.NewRecorder()
	newHandler("test-version").ServeHTTP(response, request)

	if response.Code != http.StatusMethodNotAllowed {
		t.Fatalf("got status %d, want %d", response.Code, http.StatusMethodNotAllowed)
	}
}

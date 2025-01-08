---
title: Authentication
type: docs
weight: 15
---

{{< callout type="info" >}}
**Protocol Revision**: {{< param protocolRevision >}}
{{< /callout >}}

## Overview

The Model Context Protocol currently supports authentication through OAuth 2.0. Authentication is only available when using HTTP transport. Authentication occurs at the transport level. This specification defines how clients authenticate with MCP servers using standard OAuth 2.0 flows.

## Authentication Flow

MCP servers **MAY** require authentication for any request. When authentication is required and has not been provided, servers **MUST** respond with *HTTP 401 Unauthorized*. Clients **MUST** then initiate the OAuth 2.0 authentication flow.

The basic authentication flow is as follows:

```mermaid
sequenceDiagram
    participant C as Client
    participant M as MCP Server
    participant A as OAuth Server

    C->>M: Any MCP Request
    M->>C: HTTP 401 Unauthorized
    C->>M: GET /authorize?redirect_uri=http://localhost:1234/callback
    Note over M: Validate redirect_uri
    M->>C: Redirect to OAuth Server
    C->>A: OAuth Authorization Request
    A->>M: Authorization Code (via redirect)
    M->>A: Exchange Code for Tokens
    A->>M: Access Token + Refresh Token
    M->>C: Redirect to validated redirect_uri with session token
    C->>M: Subsequent requests with session token
    Note over C,M: Begin standard MCP message exchange
```

### Authorization Endpoints

MCP servers **MUST** expose the following OAuth-related endpoints:

1. `/authorize` - Initial authorization endpoint
2. `/token` - Token exchange endpoint

These endpoints are relative to the MCP server's base URL. For example, if the MCP server is at `https://example.com/mcp/`, the authorize endpoint would be `https://example.com/mcp/authorize`.

### Session Token Usage

After successful OAuth authentication, clients receive a session token that **MUST** be included in all subsequent requests to the MCP server. The session token **MUST** be provided in the HTTP Authorization header using the Bearer scheme:

```
Authorization: Bearer <session-token>
```

Session tokens **MUST**:
1. Be cryptographically secure random values
2. Have a minimum length of 32 bytes when encoded
3. Be treated as opaque strings by clients
4. Be validated by servers on every request
5. Have defined expiration times

For example:
```http
GET /v1/contexts HTTP/1.1
Host: mcp.example.com
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

Servers **MUST NOT** accept session tokens provided via query parameters or request bodies. If a session token expires, servers **MUST** respond with HTTP 401 Unauthorized, requiring the client to obtain a new session token through the authentication flow.

### PKCE Support

MCP servers **SHOULD** support PKCE (Proof Key for Code Exchange) to enhance security. The MCP server generates both the code verifier and code challenge, using the code challenge in the OAuth flow while keeping the code verifier secret. This ensures secure token exchange between the MCP server and OAuth provider.

```mermaid
sequenceDiagram
    participant C as Client
    participant M as MCP Server
    participant A as OAuth Server

    C->>M: Any MCP Request
    M->>C: HTTP 401
    C->>M: GET /authorize?redirect_uri=http://localhost:1234/callback
    Note over M: Generate code_verifier<br/>Calculate code_challenge<br/>Validate redirect_uri
    M->>C: Redirect to OAuth Server with code_challenge
    C->>A: OAuth Authorization Request
    A->>M: Authorization Code (via redirect)
    Note over M: Use stored code_verifier
    M->>A: Exchange Code + code_verifier
    A->>M: Access Token + Refresh Token
    M->>C: Redirect to validated redirect_uri with session token
    Note over C,M: Begin standard MCP message exchange
```

## Transport Upgrade for Authentication

For STDIO transports that require authentication, servers **MUST** use the transport upgrade mechanism during initialization to direct clients to an HTTP-based MCP server as defined in the [lifecycle specification]({{< ref "/specification/draft/basic/lifecycle" >}}). The server includes an `upgrade` field in the initialize response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "upgrade": {
      "endpoint": "http://new-server.example.com:8080",
      "transport": "http+sse"
    },
    "serverInfo": {
      "name": "ExampleServer",
      "version": "1.0.0"
    }
  }
}
```

## Security Considerations

1. Clients **MUST** securely store tokens following OAuth 2.0 best practices
2. Servers **SHOULD** enforce token expiration and rotation
3. All authorization endpoints **MUST** be served over HTTPS
4. Clients **SHOULD** implement refresh token flows for long-lived sessions
5. Servers **MUST** validate redirect URIs to prevent open redirect vulnerabilities
6. Redirect URIs **MUST** be either localhost URLs or HTTPS URLs

## Error Handling

Servers **MUST** return appropriate HTTP status codes for authentication errors:

- 401 Unauthorized - Authentication required or token invalid
- 403 Forbidden - Invalid scopes or insufficient permissions
- 400 Bad Request - Malformed authentication request

## Implementation Notes

1. Implementations **MUST** follow OAuth 2.0 security best practices
2. PKCE is strongly **RECOMMENDED**.
3. Refresh token rotation **SHOULD** be implemented for enhanced security
4. Token lifetimes **SHOULD** be limited based on security requirements

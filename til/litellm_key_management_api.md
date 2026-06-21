# How to Discover Virtual Key Management API Endpoints in LiteLLM

While working with LiteLLM's proxy server, I needed to understand the virtual key management API — what endpoints exist and what payloads they expect. Here's how I traced through the codebase to find this information, followed by a complete reference for every endpoint.

## The Discovery Process

### Step 1: Find the Endpoint Definitions

All key management endpoints live in one file:

```
litellm/proxy/management_endpoints/key_management_endpoints.py
```

The module docstring at the top lists the core endpoints right away:

```python
"""
KEY MANAGEMENT

All /key management endpoints

/key/generate
/key/info
/key/update
/key/delete
"""
```

But the file has grown — it also includes `/key/block`, `/key/unblock`, `/key/regenerate`, `/key/bulk_update`, and `/key/service-account/generate`. To find all routes systematically, search for the FastAPI route decorators:

```bash
grep -n "@router\.\(post\|get\|put\|delete\|patch\)" key_management_endpoints.py
```

This gives you every registered endpoint alongside its line number.

### Step 2: Find the Request/Response Schemas

Each handler function takes a Pydantic model as its `data` parameter. For instance:

```python
async def generate_key_fn(data: GenerateKeyRequest, ...):
```

Search for the class definition to find the full schema:

```bash
grep -rn "class GenerateKeyRequest" litellm/proxy/
```

This leads to `litellm/proxy/_types.py`. The interesting part is that schemas use inheritance so fields are spread across multiple classes:

```
GenerateRequestBase          (line 917)  — common fields: key_alias, duration, models, spend, max_budget, team_id, user_id, metadata, permissions, guardrails, tpm_limit, rpm_limit, ...
  └── KeyRequestBase         (line 969)  — adds: key, budget_id, tags, allowed_routes, router_settings, access_group_ids
        └── GenerateKeyRequest (line 998)  — adds: soft_budget, send_invite_email, key_type, auto_rotate, organization_id, project_id
```

You have to walk up the inheritance chain to see the full field list. The same pattern applies to `UpdateKeyRequest`, `RegenerateKeyRequest`, and others.

### Step 3: Read the Docstrings for Examples

Every endpoint function has a detailed docstring with parameter descriptions and a `curl` example. These are the single best source for the expected JSON payload shape. For example, from `generate_key_fn` at line 1226:

```python
"""
...
Example:

curl --location 'http://0.0.0.0:4000/key/generate' \\
    --header 'Authorization: Bearer sk-1234' \\
    --header 'Content-Type: application/json' \\
    --data '{
        "permissions": {"allow_pii_controls": true}
    }'
"""
```

### Step 4: Check Special Request Types

Some endpoints use simpler, purpose-built types. For instance, `BlockKeyRequest` is just `{"key": str}` — find it at line 1850 in `_types.py`:

```bash
grep -rn "class BlockKeyRequest" litellm/proxy/_types.py
```

### The Pattern

**Endpoint function → `data` parameter type → `_types.py` for schema → docstring for examples.**

## Complete API Reference

All endpoints require the `Authorization: Bearer <admin_key>` header.

### `POST /key/generate`

Generate a new virtual key. Source: line 1211.

**Request body** — `GenerateKeyRequest`

```json
{
  "key": "sk-custom-key-value",
  "key_alias": "my-api-key",
  "duration": "30d",
  "team_id": "team-123",
  "user_id": "user-456",
  "organization_id": "org-789",
  "project_id": "proj-abc",
  "budget_id": "budget-id-1",
  "models": ["gpt-4", "gpt-3.5-turbo"],
  "aliases": {"my-gpt4": "gpt-4"},
  "spend": 0,
  "max_budget": 100.0,
  "soft_budget": 50.0,
  "budget_duration": "30d",
  "budget_limits": [{"budget_limit": 10.0, "time_period": "1d"}, {"budget_limit": 50.0, "time_period": "7d"}],
  "max_parallel_requests": 10,
  "tpm_limit": 100000,
  "rpm_limit": 1000,
  "model_max_budget": {"gpt-4": {"budget_limit": 0.0005, "time_period": "30d"}},
  "model_rpm_limit": {"gpt-4": 100},
  "model_tpm_limit": {"gpt-4": 100000},
  "tpm_limit_type": "best_effort_throughput",
  "rpm_limit_type": "best_effort_throughput",
  "metadata": {"team": "core-infra", "app": "app2"},
  "permissions": {"allow_pii_controls": true},
  "guardrails": ["guardrail-1"],
  "policies": ["policy-1"],
  "blocked": false,
  "tags": ["production", "api"],
  "prompts": ["prompt-id-1"],
  "enforced_params": ["model", "messages"],
  "allowed_routes": ["/chat/completions", "/embeddings", "/keys/*"],
  "allowed_passthrough_routes": ["/custom-endpoint"],
  "allowed_cache_controls": ["no-cache", "no-store"],
  "object_permission": {
    "mcp_servers": ["mcp-1"],
    "mcp_access_groups": ["dev-group"],
    "vector_stores": ["vs-1"],
    "agents": ["agent-1"],
    "agent_access_groups": ["dev-group"]
  },
  "key_type": "default",
  "auto_rotate": false,
  "rotation_interval": "90d",
  "access_group_ids": ["group-1"],
  "send_invite_email": true,
  "allowed_vector_store_indexes": [{"index_name": "my-index", "index_permissions": ["read", "write"]}],
  "config": {}
}
```

All fields are optional unless you want to constrain the key.

**Example:**

```bash
curl --location 'http://0.0.0.0:4000/key/generate' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data '{
    "key_alias": "my-api-key",
    "team_id": "team-123",
    "max_budget": 100,
    "models": ["gpt-4", "gpt-3.5-turbo"],
    "duration": "30d"
  }'
```

**Response** — `GenerateKeyResponse`

```json
{
  "key": "sk-abc123...",
  "key_name": null,
  "expires": "2025-07-21T00:00:00Z",
  "user_id": "user-456",
  "token_id": "token-uuid",
  "team_id": "team-123",
  "organization_id": null,
  "project_id": null,
  "litellm_budget_table": {...},
  "token": "sk-abc123...",
  "created_by": "admin-user-id",
  "updated_by": null,
  "created_at": "2025-06-21T00:00:00Z",
  "updated_at": null
}
```

### `POST /key/service-account/generate`

Generate a service account key. Same schema as `/key/generate` but the key belongs to the team, not a user. Useful for keys that should survive user deletion. Source: line 1426.

**Request body** — `GenerateKeyRequest` (same as `/key/generate`)

**Key difference:** `user_id` is ignored (set to null). The key is associated with the team only.

**Example:**

```bash
curl --location 'http://0.0.0.0:4000/key/service-account/generate' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data '{
    "team_id": "team-123",
    "max_budget": 500,
    "key_alias": "ci-deploy-key"
  }'
```

### `POST /key/update`

Update an existing key's parameters. Source: line 2221.

**Request body** — `UpdateKeyRequest`

```json
{
  "key": "sk-abc123...",
  "key_alias": "new-alias",
  "team_id": "new-team-456",
  "user_id": "new-user-789",
  "organization_id": "new-org-123",
  "project_id": "new-proj-456",
  "models": ["gpt-4"],
  "max_budget": 200.0,
  "soft_budget": 100.0,
  "budget_duration": "30d",
  "budget_limits": [{"budget_limit": 10.0, "time_period": "1d"}, {"budget_limit": 50.0, "time_period": "7d"}],
  "spend": 0,
  "max_parallel_requests": 20,
  "tpm_limit": 200000,
  "rpm_limit": 2000,
  "model_max_budget": {"gpt-4": {"budget_limit": 0.001, "time_period": "30d"}},
  "model_rpm_limit": {"gpt-4": 200},
  "model_tpm_limit": {"gpt-4": 200000},
  "tpm_limit_type": "guaranteed_throughput",
  "rpm_limit_type": "guaranteed_throughput",
  "metadata": {"updated": true},
  "permissions": {"allow_pii_controls": false},
  "guardrails": ["guardrail-2"],
  "policies": ["policy-2"],
  "blocked": true,
  "tags": ["production"],
  "prompts": ["prompt-id-2"],
  "enforced_params": ["model"],
  "allowed_routes": ["/chat/completions"],
  "allowed_passthrough_routes": ["/my-endpoint"],
  "allowed_cache_controls": ["no-cache"],
  "object_permission": {"vector_stores": ["vs-2"]},
  "aliases": {"my-gpt4": "gpt-4o"},
  "duration": "60d",
  "auto_rotate": true,
  "rotation_interval": "30d",
  "allowed_vector_store_indexes": [{"index_name": "my-index", "index_permissions": ["read"]}],
  "router_settings": {"model_group_retry_policy": {"max_retries": 5}},
  "access_group_ids": ["group-2"],
  "temp_budget_increase": 50.0,
  "temp_budget_expiry": "2025-07-01T00:00:00Z"
}
```

Only `key` is required. All other fields are optional — omitted fields are not modified.

**Example:**

```bash
curl --location 'http://0.0.0.0:4000/key/update' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data '{
    "key": "sk-abc123...",
    "max_budget": 200,
    "blocked": true
  }'
```

### `POST /key/delete`

Delete one or more keys. Source: line 2664.

**Request body** — `KeyRequest`

You must provide **either** `keys` **or** `key_aliases` (at least one is required):

```json
{
  "keys": ["sk-abc123...", "sk-def456..."]
}
```

or:

```json
{
  "key_aliases": ["my-key-alias", "another-alias"]
}
```

**Example:**

```bash
curl --location 'http://0.0.0.0:4000/key/delete' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data '{
    "keys": ["sk-abc123...", "sk-def456..."]
  }'
```

**Response:**

```json
{
  "deleted_keys": ["sk-abc123...", "sk-def456..."]
}
```

### `GET /key/info`

Retrieve information about a key. Source: line 2860.

**Query parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | No | The key to look up. If omitted, the key from the Authorization header is used. |

**Example:**

```bash
# Look up a specific key
curl -X GET "http://0.0.0.0:4000/key/info?key=sk-abc123..." \
  -H "Authorization: Bearer sk-1234"

# Look up the calling key (uses Authorization header key)
curl -X GET "http://0.0.0.0:4000/key/info" \
  -H "Authorization: Bearer sk-abc123..."
```

**Response:**

```json
{
  "key": "sk-abc123...",
  "info": {
    "key_alias": "my-api-key",
    "max_budget": 100.0,
    "spend": 12.5,
    "models": ["gpt-4"],
    "team_id": "team-123",
    "user_id": "user-456",
    "blocked": false,
    "expires": "2025-07-21T00:00:00Z",
    "metadata": {},
    "object_permission": null
  }
}
```

### `POST /v2/key/info`

Retrieve information about multiple keys. Source: line 2781.

**Request body** — `KeyRequest`

```json
{
  "keys": ["sk-1", "sk-2", "sk-3"]
}
```

or:

```json
{
  "key_aliases": ["alias-1", "alias-2"]
}
```

**Example:**

```bash
curl -X POST "http://0.0.0.0:4000/v2/key/info" \
  -H "Authorization: Bearer sk-1234" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["sk-1", "sk-2", "sk-3"]}'
```

**Response:**

```json
{
  "key": ["sk-1", "sk-2", "sk-3"],
  "info": [
    {"key_alias": "key-1", "max_budget": 100, "spend": 10, ...},
    {"key_alias": "key-2", "max_budget": 200, "spend": 20, ...},
    {"key_alias": "key-3", "max_budget": 300, "spend": 30, ...}
  ]
}
```

### `POST /key/block`

Block a virtual key from making any requests. Admin-only. Source: line 5209.

**Request body** — `BlockKeyRequest`

```json
{
  "key": "sk-Fn8Ej39NxjAXrvpUGKghGw"
}
```

The `key` field accepts either the unhashed key (`sk-...`) or the hashed key value.

**Example:**

```bash
curl --location 'http://0.0.0.0:4000/key/block' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data '{
    "key": "sk-Fn8Ej39NxjAXrvpUGKghGw"
  }'
```

**Response** — `LiteLLM_VerificationToken` (the updated key record with `blocked: true`)

### `POST /key/unblock`

Unblock a previously blocked key. Admin-only. Source: line 5318.

**Request body** — `BlockKeyRequest` (same schema as `/key/block`)

```json
{
  "key": "sk-Fn8Ej39NxjAXrvpUGKghGw"
}
```

**Example:**

```bash
curl --location 'http://0.0.0.0:4000/key/unblock' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data '{
    "key": "sk-Fn8Ej39NxjAXrvpUGKghGw"
  }'
```

### `POST /key/regenerate`

Regenerate a key (creates a new key that replaces the old one). Source: line 3906. **Enterprise feature** (requires premium license).

Can be called two ways:
- `POST /key/regenerate` with `key` in the request body
- `POST /key/{key}/regenerate` with `key` as a path parameter

**Request body** — `RegenerateKeyRequest`

```json
{
  "key": "sk-abc123...",
  "new_key": "sk-new-key-value",
  "new_master_key": "sk-new-master-key",
  "grace_period": "24h",
  "key_alias": "updated-alias",
  "team_id": "team-456",
  "models": ["gpt-4o"],
  "max_budget": 200.0,
  "metadata": {"team": "core-infra"},
  "duration": "60d"
}
```

- `new_master_key` is only used when regenerating the master key itself.
- `grace_period` keeps the old key valid for a duration (e.g. `"24h"`, `"2d"`) before revoking it.

**Example:**

```bash
curl --location --request POST 'http://localhost:4000/key/sk-abc123.../regenerate' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "grace_period": "24h",
    "max_budget": 100,
    "metadata": {"team": "core-infra"},
    "models": ["gpt-4", "gpt-3.5-turbo"]
  }'
```

**Response** — `GenerateKeyResponse` (same shape as `/key/generate`, contains the new key)

### `POST /key/bulk_update`

Update multiple keys in a single request. Source: line 2428. **Proxy admin only.**

**Request body** — `BulkUpdateKeyRequest`

```json
{
  "keys": [
    {
      "key": "sk-abc123...",
      "max_budget": 100.0,
      "team_id": "team-123",
      "tags": ["production", "api"]
    },
    {
      "key": "sk-def456...",
      "budget_id": "budget-456",
      "tags": ["staging"]
    }
  ]
}
```

Maximum 500 keys per request.

**Example:**

```bash
curl --location 'http://0.0.0.0:4000/key/bulk_update' \
  --header 'Authorization: Bearer sk-1234' \
  --header 'Content-Type: application/json' \
  --data '{
    "keys": [
      {"key": "sk-abc123...", "max_budget": 100, "tags": ["production"]},
      {"key": "sk-def456...", "budget_id": "budget-456", "tags": ["staging"]}
    ]
  }'
```

**Response** — `BulkUpdateKeyResponse`

```json
{
  "total_requested": 2,
  "successful_updates": [
    {"key": "sk-abc123...", "info": {...}}
  ],
  "failed_updates": [
    {"key": "sk-def456...", "failed_reason": "Key not found"}
  ]
}
```

## Quick Reference Table

| Endpoint | Method | Request Type | Source Line |
|----------|--------|--------------|-------------|
| `/key/generate` | POST | `GenerateKeyRequest` | 1211 |
| `/key/service-account/generate` | POST | `GenerateKeyRequest` | 1426 |
| `/key/update` | POST | `UpdateKeyRequest` | 2221 |
| `/key/bulk_update` | POST | `BulkUpdateKeyRequest` | 2428 |
| `/key/delete` | POST | `KeyRequest` | 2664 |
| `/key/info` | GET | Query param `key` | 2860 |
| `/v2/key/info` | POST | `KeyRequest` | 2781 |
| `/key/regenerate` | POST | `RegenerateKeyRequest` | 3906 |
| `/key/block` | POST | `BlockKeyRequest` | 5209 |
| `/key/unblock` | POST | `BlockKeyRequest` | 5318 |

## File Location Reference

| Content | File | Line |
|---------|------|------|
| Endpoint handlers | `litellm/proxy/management_endpoints/key_management_endpoints.py` | — |
| `GenerateRequestBase` (common fields) | `litellm/proxy/_types.py` | 917 |
| `KeyRequestBase` | `litellm/proxy/_types.py` | 969 |
| `GenerateKeyRequest` | `litellm/proxy/_types.py` | 998 |
| `GenerateKeyResponse` | `litellm/proxy/_types.py` | 1016 |
| `UpdateKeyRequest` | `litellm/proxy/_types.py` | 1056 |
| `RegenerateKeyRequest` | `litellm/proxy/_types.py` | 1079 |
| `KeyRequest` (delete/info) | `litellm/proxy/_types.py` | 1096 |
| `BlockKeyRequest` | `litellm/proxy/_types.py` | 1850 |
| `BulkUpdateKeyRequest` | `litellm/types/proxy/management_endpoints/key_management_endpoints.py` | — |

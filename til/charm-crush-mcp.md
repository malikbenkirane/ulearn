# Crush MCP Configuration

Based on the schema from `charm.land/crush.json`, here's how to configure MCP (Model Context Protocol) servers in Crush:

## MCP Configuration Structure

The `mcp` field in your Crush config is an object where each key is an MCP server name, and the value is an `MCPConfig` object.

### MCPConfig Properties

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `type` | `"stdio"` \| `"sse"` \| `"http"` | **Yes** | `"stdio"` | Type of MCP connection |
| `command` | string | No | — | Command to execute for stdio MCP servers |
| `args` | string[] | No | — | Arguments to pass to the MCP server command |
| `env` | object | No | — | Environment variables to set for the MCP server |
| `url` | string (URI) | No | — | URL for HTTP or SSE MCP servers |
| `headers` | object | No | — | HTTP headers for HTTP/SSE MCP servers |
| `disabled` | boolean | No | `false` | Whether this MCP server is disabled |
| `disabled_tools` | string[] | No | — | List of tools from this MCP server to disable |
| `enabled_tools` | string[] | No | — | Allow list of tools from this MCP server |
| `timeout` | integer | No | `15` | Timeout in seconds for MCP server connections |

## Example Configurations

### Stdio MCP Server (most common)
```json
{
  "mcp": {
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"],
      "env": {
        "NODE_OPTIONS": "--max-old-space-size=4096"
      },
      "timeout": 30
    }
  }
}
```

### HTTP MCP Server
```json
{
  "mcp": {
    "my-http-server": {
      "type": "http",
      "url": "http://localhost:3000/mcp",
      "headers": {
        "Authorization": "Bearer my-token"
      },
      "timeout": 60
    }
  }
}
```

### SSE (Server-Sent Events) MCP Server
```json
{
  "mcp": {
    "my-sse-server": {
      "type": "sse",
      "url": "http://localhost:8080/sse",
      "timeout": 30
    }
  }
}
```

### With Tool Filtering
```json
{
  "mcp": {
    "limited-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "some-mcp-server"],
      "enabled_tools": ["read_file", "write_file"],
      "timeout": 30
    }
  }
}
```

### Disabled MCP Server
```json
{
  "mcp": {
    "experimental-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "experimental-mcp"],
      "disabled": true
    }
  }
}
```

## Complete Config Example

```json
{
  "$schema": "https://charm.land/crush.json",
  "mcp": {
    "github": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "$GITHUB_TOKEN"
      }
    },
    "postgres": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "postgresql://user:pass@localhost/db"
      },
      "disabled": false
    }
  }
}
```



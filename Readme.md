
OpenCode Config files
Config sources are loaded in this order (later sources override earlier ones):

    Remote config (from .well-known/opencode) - organizational defaults
    Global config (~/.config/opencode/opencode.json) - user preferences
    Custom config (OPENCODE_CONFIG env var) - custom overrides
    Project config (opencode.json in project) - project-specific settings
    .opencode directories - agents, commands, plugins
    Inline config (OPENCODE_CONFIG_CONTENT env var) - runtime overrides
    Managed config files (/Library/Application Support/opencode/ on macOS) - admin-controlled
    macOS managed preferences (.mobileconfig via MDM) - highest priority, not user-overridable

This means project configs can override global defaults, and global configs can override remote organizational defaults. Managed settings override everything.



MCP
https://hub.docker.com/mcp/server/context7/overview
https://hub.docker.com/mcp/server/duckduckgo/overview

todo:
https://hub.docker.com/mcp/server/fetch/overview
https://hub.docker.com/mcp/server/firecrawl/overview
https://hub.docker.com/mcp/server/gemini-api-docs/overview
https://hub.docker.com/mcp/server/git/overview
https://hub.docker.com/mcp/server/memory/overview
https://hub.docker.com/mcp/server/sequentialthinking/overview

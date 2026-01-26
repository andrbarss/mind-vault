# Teisutis AI/Rules/Config Scan

Comprehensive scan of AI-related configurations, prompts, rules, and patterns found in Teisutis project.

**Date**: 2026-01-26  
**Scanner**: OpenCode  
**Status**: Ready for skill extraction

---

## Summary

| Category | Count | Priority |
|----------|-------|----------|
| System Prompts | 1 | CRITICAL |
| Tool Usage Rules | 3 | CRITICAL |
| Language Instructions | 1 | HIGH |
| Text Processing Patterns | 4 | HIGH |
| Django/Tenants Patterns | 2 | HIGH |
| AI Service Rules | 2 | MEDIUM |
| Performance Patterns | 1 | MEDIUM |

---

## 1. CRITICAL: System Prompt Template

**Location**: `/web/teisutis_ai/consumers.py:64-128`  
**Type**: System prompt template  
**Function**: `get_default_system_prompt_template()`

### Content
The canonical AI system prompt for the knowledge base assistant. Contains:

- Role definition: "helpful AI assistant for a knowledge base system"
- User context awareness (username, email, organization, permissions)
- Tool usage guidelines (search, create, update articles/events)
- Permission-based filtering rules
- Category/tag assignment rules
- FAQ handling (internal use only)
- Reference generation rules

### Key Rules Embedded
1. **User Context Usage**: Filter results based on user scopes and permissions
2. **Permission Checks**: Only suggest actions user has permission for
3. **Tool Capabilities**: Clear listing of what tools do
4. **References**: Automatically generate article links in responses
5. **Category Assignment**: Always include category_id when creating articles

### Related Code
- `get_system_prompt_template()` method - retrieves from DB or creates default
- `PromptTemplate` model - stores customizable prompts per tenant

**Priority**: CRITICAL - This is the foundation of all AI behavior

**Action**: Create `teisutis-ai-system-prompt` skill

---

## 2. CRITICAL: Tool Dependency & Sequential Execution Rules

**Location**: `/web/teisutis_ai/consumers.py:111-115`  
**Type**: Execution pattern/rule  
**Scope**: All tool invocations

### Content
```
CRITICAL: Tool Dependency & Sequential Execution

No Parallel Dependencies: Never invoke tools in parallel if one tool's input 
depends on another tool's output (e.g., creating a category and an article simultaneously).

Verification First: When creating or updating articles/events, always ensure you have 
the correct category_id or tag_id as an integer. If only a name is provided, 
you MUST run search_categories or search_tags first.

Chain of Command: Execute creation tools sequentially: 
create_category -> [Wait for Response/ID] -> create_article.
```

### Why This Exists
Result of BUG-001 investigation (2026-01-20) - discovered that parallel tool calls 
cause race conditions where IDs aren't available yet.

**Priority**: CRITICAL - Prevents tool execution failures

**Action**: Create `teisutis-tool-dependency` skill

---

## 3. CRITICAL: Search Result Handling (Prevent Infinite Loops)

**Location**: `/web/teisutis_ai/consumers.py:117-123`  
**Type**: Execution pattern/safeguard  
**Scope**: Search operations

### Content
```
When search_categories or search_tags returns 0 results:
- If user explicitly requested that category/tag, create it
- If category/tag was inferred, proceed without it
- NEVER search more than 2-3 times with different queries
- If first search returns 0 results, either create or proceed without
```

### Purpose
Prevents AI from getting stuck in infinite search loops when looking for non-existent items.

**Priority**: CRITICAL - Prevents agent failures

**Action**: Include in `teisutis-tool-dependency` skill

---

## 4. HIGH: Language-Specific Instructions

**Location**: `/web/teisutis_ai/ai_service.py`  
**Type**: Dynamic instruction generation  
**Function**: `_get_language_instruction()`

### Details
Generates language-specific instructions based on user's language preference.
Used in system prompt construction.

**Known Languages**: Lithuanian (lt), English (en), Russian (ru), Polish (pl)

**Pattern**: 
- Detect user language from preferences or tenant settings
- Generate locale-specific instructions
- Append to system prompt

**Note**: Mentioned in IDEA-033 for standardization to BCP-47 format

**Priority**: HIGH - Affects response quality for non-English users

**Action**: Create `teisutis-language-instructions` skill

---

## 5. HIGH: Text Processing Rules

**Location**: `/web/teisutis_ai/ai_service.py`  
**Type**: Text transformation templates  
**Count**: 4 patterns

### 5a. Text Structuring Pattern
- **Template**: `STRUCTURE_TEXT_TEMPLATE`
- **Purpose**: Organize unstructured text into logical sections
- **Usage**: Converting raw input into formatted KB articles

### 5b. Text Refactoring Pattern
- **Template**: `REFACTOR_TEXT_TEMPLATE`
- **Purpose**: Improve clarity and organization
- **Usage**: Polish existing article content

### 5c. Tag Suggestion Pattern
- **Template**: `SUGGEST_TAGS_TEMPLATE`
- **Purpose**: Generate relevant tags for articles
- **Usage**: Auto-categorization of content

### 5d. Knowledge Query Pattern
- **Template**: `QUERY_KNOWLEDGE_TEMPLATE`
- **Purpose**: Query knowledge base semantically
- **Usage**: Finding relevant context for responses

**Priority**: HIGH - Core AI functionality

**Action**: Create `teisutis-text-processing` skill

---

## 6. HIGH: Django/Django-Tenants Patterns

**Location**: `/web/teisutis_ai/consumers.py`, `/web/teisutis_ai/ai_service.py`  
**Type**: Django architecture patterns  
**Count**: 2+ patterns

### 6a. Multi-Tenant Context Management
- Use `tenant_context()` and `schema_context()` for tenant operations
- Store tenant in WebSocket scope: `self.tenant = self.scope.get('tenant')`
- Always verify tenant presence and user permissions

### 6b. Async Database Operations
- Use `@database_sync_to_async` for sync DB calls in async contexts
- Used in conversation retrieval, message persistence
- Prevents database blocking in WebSocket handlers

**Related Files**:
- `TenantChannelsMiddleware` - sets tenant in scope
- Conversation model - tenant-scoped data

**Priority**: HIGH - Critical for data isolation

**Action**: Create `teisutis-django-tenants` skill

---

## 7. MEDIUM: AI Service Configuration

**Location**: `/web/teisutis/settings.py`  
**Type**: Environment configuration  
**Variables**: 
- `MAX_AI_PROMPT_LENGTH` - max input text length (default 50000)
- Language codes for STT/TTS
- API keys for external AI services

**Used By**: `ai_service.py` validation, streaming response handling

**Priority**: MEDIUM - Important for performance tuning

**Action**: Document in `teisutis-ai-config` skill

---

## 8. MEDIUM: Semantic Search & Performance Patterns

**Location**: `/web/teisutis_ai/semantic_search.py`, `/web/teisutis_ai/performance_metrics.py`  
**Type**: Performance optimization patterns  
**Patterns**:
- Model pre-loading at startup
- Elasticsearch timeout configuration (3s for search, 10s for indexing)
- Performance logging and metrics tracking
- GPU acceleration considerations (IDEA-015)

**Related**: 
- IDEA-015: Fix Semantic Search Performance
- Performance monitoring for slow queries (>3s warnings)

**Priority**: MEDIUM - Performance optimization

**Action**: Create `teisutis-performance` skill

---

## 9. LOW: Knowledge Base Management Rules

**Location**: `/web/teisutis_ai/consumers.py:100-109`  
**Type**: Operational guidelines  
**Rules**:
- References section auto-generated
- FAQs for internal AI use only
- Attachment assignment rules
- Permission-based actions

**Priority**: LOW - Supporting guidelines

**Action**: Include in system prompt skill

---

## Other Detected Files

### Prompt Documentation
- `/docs/prompts/grok_prompt_short.txt` - Django test troubleshooting prompt (not AI system prompt)
- `/docs/prompts/grok_django_tenants_trigger_issue.md` - Problem description (reference material)

### Management Commands
- `/web/teisutis_ai/management/commands/update_prompt_templates.py` - Syncs DB templates with code

### Documentation
- `/docs/execution/IDEAS.md` - Contains IDEA-031 (session management, relevant for context staleness)
- `/docs/execution/DEVELOPMENT_LOG.md` - Implementation history

---

## Extraction Plan

### Priority 1 (CRITICAL - Do First)
1. **`teisutis-ai-system-prompt`** - System prompt template
2. **`teisutis-tool-dependency`** - Sequential execution rules + search safeguards

### Priority 2 (HIGH - Do Next)
3. **`teisutis-text-processing`** - Text transformation templates
4. **`teisutis-django-tenants`** - Multi-tenant architecture patterns
5. **`teisutis-language-instructions`** - Language-specific behavior

### Priority 3 (MEDIUM - Polish)
6. **`teisutis-ai-config`** - Configuration and setup patterns
7. **`teisutis-performance`** - Performance optimization and monitoring
8. **`teisutis-kb-management`** - Knowledge base operational guidelines

### Priority 4 (OPTIONAL - Future)
- `teisutis-semantic-search` - Advanced search patterns
- `teisutis-tool-executor` - Tool execution patterns
- `teisutis-permission-rules` - Permission-based behavior

---

## Notes

- All files use Python type hints and async/await patterns
- Database operations use django-tenants for isolation
- Performance is tracked via custom metrics system
- Context staleness issue documented in IDEA-031 (relevant for session management)
- Recent system prompt updates (2026-01-20) include BUG-001 fixes for tool sequencing

---

**Next Step**: Start with Priority 1 skills and create SKILL.md files in `~/projects/mind-vault/skills/`

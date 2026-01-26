# SKILL_django-architecture

## Overview

Core Django project architecture patterns for organizing models, views, serializers, and middleware. Covers BaseModel abstractions, DRF conventions, ASGI setup, and common DRY patterns. This skill covers standard Django architecture without multi-tenancy, Celery, or async/WebSocket specifics - see separate skills for those.

## When to Use

- Starting a new Django project
- Organizing app structure and models
- Setting up DRF viewsets and permissions
- Configuring middleware and ASGI
- Extracting common patterns into mixins/base classes
- Optimizing database queries
- Adding performance monitoring

## Pattern

### Project Structure

**Standard Django layout**:
```
project_root/
├── manage.py
├── requirements.txt
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── config/                          # Project settings
│   ├── __init__.py
│   ├── settings.py                  # Main settings
│   ├── asgi.py                      # Async Server Gateway Interface
│   ├── wsgi.py                      # (if using traditional deployment)
│   └── urls.py                      # Root URL configuration
├── apps/                            # Django apps directory
│   ├── core/                        # Shared utilities, abstract models
│   │   ├── models.py                # BaseModel, abstract classes
│   │   ├── mixins.py                # QuerySet and ViewSet mixins
│   │   ├── permissions.py           # Custom permission classes
│   │   ├── serializers.py           # Base serializers
│   │   └── decorators.py            # Reusable decorators
│   ├── auth/                        # Authentication app
│   ├── api/                         # Main API endpoints
│   └── [feature]/                   # Feature-specific apps
│       ├── models.py
│       ├── views.py
│       ├── serializers.py
│       ├── permissions.py
│       ├── urls.py
│       └── tests/
├── static/                          # Static files (CSS, JS, images)
│   ├── css/
│   ├── js/
│   └── images/
├── templates/                       # Django templates
│   ├── base.html
│   └── [app]/
└── logs/                            # Application logs
```

**Why this structure**:
- Each app is self-contained (models, views, serializers, permissions)
- `core/` app centralizes shared patterns (mixins, decorators, base classes)
- Static and templates separate from code
- Easy to find and modify patterns
- Follows Django conventions for discoverability

### BaseModel Abstraction

**Create abstract base models to reduce duplication**:

```python
# apps/core/models.py
from django.db import models
from django.utils import timezone

class BaseModel(models.Model):
    """Abstract base model with common fields."""
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_deleted = models.BooleanField(default=False)

    class Meta:
        abstract = True
        indexes = [
            models.Index(fields=['created_at']),
            models.Index(fields=['updated_at']),
        ]

    def soft_delete(self):
        """Mark as deleted instead of removing."""
        self.is_deleted = True
        self.save(update_fields=['is_deleted', 'updated_at'])

    def restore(self):
        """Restore soft-deleted record."""
        self.is_deleted = False
        self.save(update_fields=['is_deleted', 'updated_at'])
```

**Use in your models**:

```python
class Article(BaseModel):
    title = models.CharField(max_length=255)
    content = models.TextField()
    author = models.ForeignKey(User, on_delete=models.CASCADE)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.title
```

**Critical**: Always filter soft-deleted records in queries:

```python
# Correct: Exclude soft-deleted
Article.objects.filter(is_deleted=False)

# Wrong: Forgets soft-delete filter!
Article.objects.all()  # ❌ Includes deleted records
```

### Settings & Configuration

**Organize settings with environment variables**:

```python
# config/settings.py
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# Environment-based configuration
SECRET_KEY = os.getenv('SECRET_KEY', 'dev-key-change-in-production')
DEBUG = os.getenv('DEBUG', 'false').lower() == 'true'
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'project_db'),
        'USER': os.getenv('DB_USER', 'postgres'),
        'PASSWORD': os.getenv('DB_PASSWORD', ''),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
        'CONN_MAX_AGE': int(os.getenv('DB_CONN_MAX_AGE', '600')),
    }
}

# Feature gates (enable features without code changes)
FEATURE_ENABLE_ELASTICSEARCH = os.getenv('FEATURE_ENABLE_ELASTICSEARCH', 'false').lower() == 'true'
FEATURE_ENABLE_CACHING = os.getenv('FEATURE_ENABLE_CACHING', 'true').lower() == 'true'

# Sensible defaults with overrides
SEARCH_TIMEOUT = int(os.getenv('SEARCH_TIMEOUT', '3'))  # seconds
API_TIMEOUT = int(os.getenv('API_TIMEOUT', '30'))       # seconds
BATCH_SIZE = int(os.getenv('BATCH_SIZE', '1000'))       # for bulk operations
```

**Why this pattern**:
- Configuration lives in environment, not code
- Same codebase works dev/staging/production
- Defaults work for development
- Feature gates allow A/B testing without deployment

### DRF Patterns

**Base ViewSet with common functionality**:

```python
# apps/core/views.py
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated

class BaseViewSet(viewsets.ModelViewSet):
    """Base viewset with common functionality."""
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        """Override to add common optimizations."""
        queryset = super().get_queryset()
        # Add select_related/prefetch_related as needed
        return queryset

    def perform_create(self, serializer):
        """Hook for additional logic on create."""
        serializer.save()

    def perform_update(self, serializer):
        """Hook for additional logic on update."""
        serializer.save()
```

**Permission classes for authorization**:

```python
# apps/core/permissions.py
from rest_framework.permissions import BasePermission

class IsResourceOwner(BasePermission):
    """Only allow resource owner to modify."""
    def has_object_permission(self, request, view, obj):
        return obj.author == request.user

class HasRequiredRole(BasePermission):
    """Check if user has required role."""
    required_role = None

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        return request.user.role == self.required_role
```

**Use permissions in viewsets**:

```python
class ArticleViewSet(BaseViewSet):
    queryset = Article.objects.filter(is_deleted=False)
    serializer_class = ArticleSerializer
    permission_classes = [IsAuthenticated, IsResourceOwner]
```

### Middleware Patterns

**Custom middleware for request context**:

```python
# apps/core/middleware.py
class RequestContextMiddleware:
    """Add context to request for downstream use."""
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # Store user info on request
        request.user_context = {
            'user_id': request.user.id if request.user.is_authenticated else None,
            'timestamp': timezone.now(),
        }

        response = self.get_response(request)
        return response
```

**Add to settings**:

```python
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'apps.core.middleware.RequestContextMiddleware',  # Your custom middleware
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]
```

**Critical**: Middleware order matters! Context-setting middleware should run early.

### ASGI Configuration (Daphne)

**Pragmatic single-server setup with Daphne**:

```python
# config/asgi.py
import os
from django.core.asgi import get_asgi_application
from django.urls import path

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

# Initialize Django ASGI application
django_asgi_app = get_asgi_application()

async def application(scope, receive, send):
    """Single entry point for all HTTP/WebSocket."""
    if scope['type'] == 'http':
        await django_asgi_app(scope, receive, send)
    else:
        # WebSocket handling (see SKILL_django-async-websocket)
        await django_asgi_app(scope, receive, send)
```

**docker-compose.yml**:

```yaml
version: '3.8'
services:
  web:
    build: .
    command: daphne -b 0.0.0.0 -p 8000 config.asgi:application
    ports:
      - "8000:8000"
    environment:
      - DEBUG=false
      - ALLOWED_HOSTS=localhost,0.0.0.0
    depends_on:
      - db

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=project_db
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

### Common Abstractions - Mixins

**Reduce boilerplate with queryable mixins**:

```python
# apps/core/mixins.py
class SoftDeleteMixin:
    """Automatically filter out soft-deleted objects."""
    def get_queryset(self):
        return super().get_queryset().filter(is_deleted=False)

class TimestampMixin:
    """Add created_at/updated_at to list views."""
    def get_queryset(self):
        queryset = super().get_queryset()
        return queryset.order_by('-created_at')

class OptimizedQueryMixin:
    """Apply select_related/prefetch_related automatically."""
    select_related_fields = []
    prefetch_related_fields = []

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.select_related_fields:
            queryset = queryset.select_related(*self.select_related_fields)
        if self.prefetch_related_fields:
            queryset = queryset.prefetch_related(*self.prefetch_related_fields)
        return queryset
```

**Use in viewsets**:

```python
class ArticleViewSet(SoftDeleteMixin, OptimizedQueryMixin, BaseViewSet):
    queryset = Article.objects.all()
    serializer_class = ArticleSerializer
    select_related_fields = ['author']
    prefetch_related_fields = ['comments']
```

### Database Optimization

**Prevent N+1 query problems**:

```python
# Wrong: N+1 queries
articles = Article.objects.all()
for article in articles:
    print(article.author.name)  # ❌ One query per article!

# Correct: Select related (one-to-one, foreign key)
articles = Article.objects.select_related('author')
for article in articles:
    print(article.author.name)  # ✅ Only 2 queries total

# Correct: Prefetch related (many-to-many, reverse foreign key)
articles = Article.objects.prefetch_related('comments')
for article in articles:
    for comment in article.comments.all():  # ✅ Only 2 queries total
        print(comment.text)
```

**Batch operations**:

```python
# Inefficient: Loop with individual saves
for article in articles:
    article.status = 'published'
    article.save()  # ❌ One query per article!

# Efficient: Batch update
Article.objects.filter(
    status='draft'
).update(status='published')  # ✅ One query!

# Batch create
articles = [
    Article(title=f"Article {i}", author=user)
    for i in range(1000)
]
Article.objects.bulk_create(articles, batch_size=100)  # ✅ Efficient!
```

### Performance Monitoring

**Decorator-based timing and alerting**:

```python
# apps/core/decorators.py
import time
import logging
from functools import wraps

logger = logging.getLogger(__name__)

def monitor_performance(operation_name, warn_threshold_ms=1000):
    """Alert if operation takes longer than threshold."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            start = time.time()
            try:
                result = func(*args, **kwargs)
                return result
            finally:
                elapsed_ms = (time.time() - start) * 1000
                if elapsed_ms > warn_threshold_ms:
                    logger.warning(
                        f"{operation_name} took {elapsed_ms:.1f}ms (threshold: {warn_threshold_ms}ms)"
                    )
        return wrapper
    return decorator
```

**Use in views**:

```python
class ArticleViewSet(BaseViewSet):
    @monitor_performance('list_articles', warn_threshold_ms=500)
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)
```

## Why It's Generic

- **BaseModel pattern**: Used across any Django project needing soft deletes and timestamps
- **Settings management**: Environment-based config standard for production apps
- **DRF conventions**: ViewSets, permissions, serializers are DRF best practices
- **Middleware**: Request context handling applies to any Django project
- **ASGI**: Daphne setup relevant for any project needing WebSocket support
- **Mixins**: Query optimization patterns reusable across models/views
- **Database optimization**: N+1 prevention, batch operations apply universally

These patterns **don't require multi-tenancy, Celery, or async** - they're core Django architecture applicable to any size project.

## Example Use Cases

- **Teisutis**: Knowledge base + AI features, uses all patterns
- **Django REST API**: Any REST API project uses ViewSet + permission patterns
- **Content management**: Soft deletes, timestamps, performance monitoring
- **SaaS application**: BaseModel abstraction, middleware, query optimization
- **Dashboard application**: DRF + permissions for role-based access

## Related Skills

- [`SKILL_django-multi-tenant.md`](../skills/SKILL_django-multi-tenant.md) - If using multi-tenancy, extends BaseModel
- [`SKILL_django-celery.md`](../skills/SKILL_django-celery.md) - If using background tasks
- [`SKILL_django-async-websocket.md`](../skills/SKILL_django-async-websocket.md) - If using real-time features

## References

- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Django ORM Query Optimization](https://docs.djangoproject.com/en/stable/topics/db/optimization/)
- [ASGI Specification](https://asgi.readthedocs.io/)
- [Daphne Documentation](https://github.com/django/daphne)

---

**Last Updated**: 2026-01-26

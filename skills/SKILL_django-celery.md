# SKILL_django-celery

## Overview

Background task patterns using Celery for asynchronous job processing in Django. Complete guide to implementing reliable async tasks with tenant context, error handling, retry strategies, and Channels integration for real-time updates. Build on SKILL_django-architecture and SKILL_django-multi-tenant for context.

## When to Use

- Implementing background tasks that don't block user requests
- Sending emails, generating reports, processing files asynchronously
- Long-running operations triggered by user actions
- Scheduled jobs (cron-like tasks)
- Integration with Celery + Redis + Channels for real-time feedback
- Multi-tenant apps where each task must know its tenant context

**DO NOT USE if**:
- Task is critical path (user must wait for result)
- Task needs synchronous database lock
- No task queue infrastructure available

## Pattern

### Installation & Configuration

```python
# requirements.txt
celery>=5.3.0
redis>=4.5.0
```

**settings.py** (at `web/project/settings.py`):

```python
# Celery Configuration
CELERY_BROKER_URL = 'redis://redis:6379/0'  # Redis for task queue
CELERY_RESULT_BACKEND = 'redis://redis:6379/0'  # Result storage
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'

# Task execution settings
CELERY_TASK_TRACK_STARTED = True  # Track task status
CELERY_TASK_TIME_LIMIT = 30 * 60  # 30 minutes hard limit
CELERY_TASK_SOFT_TIME_LIMIT = 25 * 60  # 25 minutes soft limit (signals)

# Timezone consistency
CELERY_TIMEZONE = 'UTC'
CELERY_ENABLE_UTC = True

# Retry settings
CELERY_TASK_AUTORETRY_FOR = (Exception,)  # Retry on any exception
CELERY_TASK_MAX_RETRIES = 3  # Max 3 attempts
CELERY_TASK_DEFAULT_RETRY_DELAY = 60  # Wait 60s between retries
```

**celery.py** (at `web/project/celery.py`):

```python
import os
from celery import Celery

# Set default Django settings
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')

app = Celery('project')
app.config_from_object('django.conf:settings', namespace='CELERY')

# Auto-discover tasks from all apps
app.autodiscover_tasks()

@app.task(bind=True)
def debug_task(self):
    """Test task to verify Celery is working."""
    print(f'Request: {self.request!r}')
```

**asgi.py** (Channels integration):

```python
import os
import django
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'project.settings')
django.setup()

from teisutis_ai.routing import websocket_urlpatterns

application = ProtocolTypeRouter({
    'http': get_asgi_application(),
    'websocket': AuthMiddlewareStack(
        URLRouter(websocket_urlpatterns)
    ),
})
```

### Core Task Pattern

**Never assume request context in tasks!** Tasks run in background worker, no request object.

```python
# tasks.py - in an app (auth/tasks.py, core/tasks.py, api/tasks.py)
from celery import shared_task
from django.core.mail import send_mail
from django_tenants.utils import tenant_context

@shared_task(bind=True, max_retries=3)
def send_welcome_email(self, user_id, tenant_id):
    """
    Send welcome email to newly created user.
    
    CRITICAL: Pass tenant_id explicitly - no request context!
    """
    from django.contrib.auth.models import User
    from core.models import Tenant
    
    try:
        # Get tenant from database (explicitly!)
        tenant = Tenant.objects.get(id=tenant_id)
        
        # Switch to tenant schema for this task
        with tenant_context(tenant):
            user = User.objects.get(id=user_id)
        
        # Send email (works fine outside tenant_context)
        send_mail(
            subject='Welcome!',
            message=f'Hi {user.email}',
            from_email='noreply@example.com',
            recipient_list=[user.email],
        )
        
        return f'Email sent to {user.email}'
    
    except Exception as exc:
        # Retry with exponential backoff
        retry_delay = 60 * (2 ** self.request.retries)  # 60s, 120s, 240s
        raise self.retry(exc=exc, countdown=retry_delay)
```

**Key principles**:
- ✅ Pass `tenant_id` as explicit parameter
- ✅ Use `tenant_context()` to switch schemas
- ✅ Wrap tenant-dependent queries in context
- ✅ Retry with exponential backoff
- ❌ Don't access `request` object (it doesn't exist)
- ❌ Don't assume current tenant is set

### Signal-Based Task Triggering

**Models trigger tasks via Django signals**:

```python
# models.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from .tasks import send_welcome_email, generate_report

class User(AbstractUser):
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

@receiver(post_save, sender=User)
def user_created(sender, instance, created, **kwargs):
    """Trigger welcome email when user is created."""
    if created:
        # Pass tenant_id explicitly!
        send_welcome_email.delay(
            user_id=instance.id,
            tenant_id=instance.tenant_id  # From request context or database lookup
        )
```

**In views, trigger via signal**:

```python
# views.py
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import User

class RegisterView(APIView):
    def post(self, request):
        # Create user - signal triggers task automatically
        user = User.objects.create_user(
            email=request.data['email'],
            password=request.data['password'],
        )
        
        # Signal fires post_save → send_welcome_email.delay()
        # → Background worker sends email (no blocking)
        
        return Response({'user_id': user.id}, status=201)
```

### Task State & Real-Time Feedback (Channels)

**Track task progress with Channels WebSocket**:

```python
# tasks.py
from celery import shared_task
from django_tenants.utils import tenant_context
import json

@shared_task(bind=True)
def process_large_file(self, file_id, tenant_id, channel_name=None):
    """
    Process file in background.
    Sends progress updates via WebSocket (Channels).
    """
    from core.models import Tenant
    from uploads.models import File
    
    try:
        tenant = Tenant.objects.get(id=tenant_id)
        
        with tenant_context(tenant):
            file_obj = File.objects.get(id=file_id)
            
            # Simulate processing steps
            for step in range(1, 11):
                # Do actual work...
                process_chunk(file_obj, step)
                
                # Send progress via Channels
                if channel_name:
                    async_to_sync(channel_layer.group_send)(
                        channel_name,
                        {
                            'type': 'file_progress',
                            'progress': step * 10,
                            'status': 'processing',
                        }
                    )
                
                # Update Celery state
                self.update_state(
                    state='PROGRESS',
                    meta={'current': step, 'total': 10}
                )
        
        return {'status': 'complete', 'file_id': file_id}
    
    except Exception as exc:
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
```

**WebSocket consumer receiving updates**:

```python
# consumers.py
from channels.generic.websocket import AsyncWebsocketConsumer
import json

class FileProcessingConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.file_id = self.scope['url_route']['kwargs']['file_id']
        self.group_name = f'file_{self.file_id}'
        
        # Join group for progress updates
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
    
    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)
    
    async def file_progress(self, event):
        """Receive progress updates from task."""
        await self.send(text_data=json.dumps({
            'type': 'progress',
            'progress': event['progress'],
            'status': event['status'],
        }))
```

### Error Handling & Retry Strategies

**Categorize errors**: Retry vs. Fail

```python
# tasks.py
from celery import shared_task
from django_tenants.utils import tenant_context
import requests

@shared_task(bind=True, max_retries=5)
def sync_external_data(self, org_id, tenant_id):
    """
    Sync data from external API.
    Retry on network errors, fail fast on validation errors.
    """
    from core.models import Tenant
    
    try:
        tenant = Tenant.objects.get(id=tenant_id)
        
        with tenant_context(tenant):
            # Call external API
            response = requests.get('https://api.example.com/data', timeout=10)
            response.raise_for_status()
            
            data = response.json()
            # Validate and save...
        
        return {'status': 'synced', 'records': len(data)}
    
    except requests.exceptions.Timeout as exc:
        # Network timeout - RETRY (transient error)
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    
    except requests.exceptions.ConnectionError as exc:
        # Connection failed - RETRY (transient error)
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
    
    except ValueError as exc:
        # Invalid data - FAIL FAST (permanent error)
        # Don't retry bad data
        return {
            'status': 'failed',
            'error': 'Invalid data from API',
            'exc': str(exc)
        }
```

**Retry backoff patterns**:

```python
# Linear backoff (same delay each time)
# 60s, 60s, 60s
countdown = 60

# Exponential backoff (double each time)
# 60s, 120s, 240s
countdown = 60 * (2 ** self.request.retries)

# Fibonacci backoff (realistic growth)
# 60s, 60s, 120s, 180s, 300s
fibonacci = [60, 60, 120, 180, 300]
countdown = fibonacci[min(self.request.retries, len(fibonacci)-1)]

# Max backoff cap (don't wait forever)
countdown = min(60 * (2 ** self.request.retries), 3600)  # Max 1 hour
```

### Task Monitoring & Logging

**Add observability to tasks**:

```python
# tasks.py
import logging
from celery import shared_task
from django_tenants.utils import tenant_context
import time

logger = logging.getLogger(__name__)

@shared_task(bind=True)
def analyze_data(self, tenant_id, dataset_id):
    """Analyze dataset with timing and logging."""
    from core.models import Tenant
    
    start_time = time.time()
    task_id = self.request.id
    
    logger.info(
        f'Task {task_id} started',
        extra={
            'task_name': 'analyze_data',
            'tenant_id': tenant_id,
            'dataset_id': dataset_id,
        }
    )
    
    try:
        tenant = Tenant.objects.get(id=tenant_id)
        
        with tenant_context(tenant):
            # Actual work...
            result = compute_analysis(dataset_id)
        
        duration = time.time() - start_time
        logger.info(
            f'Task {task_id} completed',
            extra={
                'task_name': 'analyze_data',
                'duration_seconds': duration,
                'result_size': len(result),
            }
        )
        
        return result
    
    except Exception as exc:
        duration = time.time() - start_time
        logger.error(
            f'Task {task_id} failed',
            exc_info=exc,
            extra={
                'task_name': 'analyze_data',
                'duration_seconds': duration,
                'retries': self.request.retries,
            }
        )
        
        retry_delay = 60 * (2 ** self.request.retries)
        raise self.retry(exc=exc, countdown=retry_delay)
```

### Common Pitfalls

**❌ WRONG: Accessing request in task**

```python
@shared_task
def send_email(email):
    user = request.user  # ❌ AttributeError: request doesn't exist
    send_mail(...)
```

**✅ CORRECT: Pass required data as parameters**

```python
@shared_task
def send_email(user_id, tenant_id):  # Pass IDs explicitly
    user = User.objects.get(id=user_id)
    send_mail(...)
```

---

**❌ WRONG: Losing tenant context**

```python
@shared_task
def create_article(article_data):
    # Which tenant does this belong to?
    Article.objects.create(**article_data)  # ❌ Wrong schema?
```

**✅ CORRECT: Explicit tenant context**

```python
@shared_task
def create_article(article_data, tenant_id):
    tenant = Tenant.objects.get(id=tenant_id)
    with tenant_context(tenant):
        Article.objects.create(**article_data)  # ✅ Correct schema
```

---

**❌ WRONG: Synchronous work blocks worker**

```python
@shared_task
def download_and_process():
    data = requests.get('https://bigfile.com/data.zip')  # Blocks worker!
    process_large_file(data)
```

**✅ CORRECT: Use timeouts and async**

```python
@shared_task
def download_and_process():
    # Set timeout to prevent hanging
    data = requests.get(
        'https://bigfile.com/data.zip',
        timeout=30  # ✅ Will raise Timeout exception
    )
    process_large_file(data)
```

---

**❌ WRONG: No error categorization**

```python
@shared_task
def sync_api():
    response = requests.get(url)  # Retry on EVERYTHING
    # If API is down, retries forever
```

**✅ CORRECT: Categorize errors**

```python
@shared_task(bind=True, max_retries=5)
def sync_api(self):
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
    except requests.exceptions.Timeout:
        # Transient - retry
        raise self.retry(countdown=60)
    except ValueError:
        # Invalid data - fail fast
        return {'error': 'Bad data'}
```

### 9 Celery Injection Points

1. **settings.py** - CELERY_BROKER_URL, retry settings, timeouts
2. **celery.py** - App configuration, task auto-discovery
3. **tasks.py** - Task definitions with tenant_id parameter
4. **models.py** - Signal handlers triggering tasks
5. **views.py** - Calling `.delay()` on tasks (async trigger)
6. **consumers.py** - Receiving task updates via Channels
7. **asgi.py** - Channels ProtocolTypeRouter configuration
8. **Makefile/docker-compose.yml** - Running Celery worker
9. **logging** - Task progress and error monitoring

**Verify all 9 locations** when implementing Celery integration.

### Testing Celery Tasks

```python
# tests/test_tasks.py
from django.test import TestCase
from django_tenants.test.cases import TenantTestCase
from celery.result import EagerResult
from celery import current_app
from core.models import Tenant, User
from auth.tasks import send_welcome_email

class CeleryTaskTestCase(TenantTestCase):
    """Test Celery tasks in eager mode (synchronous)."""
    
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Run tasks immediately (no queue)
        current_app.conf.task_always_eager = True
    
    def setUp(self):
        self.tenant = Tenant.objects.create(name='Test Org')
        self.set_tenant(self.tenant)
    
    def test_send_welcome_email(self):
        """Test welcome email task."""
        user = User.objects.create_user(
            email='test@example.com',
            password='testpass'
        )
        
        result = send_welcome_email.delay(
            user_id=user.id,
            tenant_id=self.tenant.id
        )
        
        # In eager mode, result is available immediately
        self.assertEqual(result.status, 'SUCCESS')
        self.assertIn('test@example.com', result.result)
```

## Why It's Generic

- **Celery**: Industry-standard task queue (not Teisutis-specific)
- **Multi-tenant support**: Works with any schema-per-tenant setup
- **Signal patterns**: Django's built-in mechanism for decoupling
- **Channels integration**: Real-time feedback for long-running tasks
- **Retry strategies**: Apply to any external API/service integration
- **Production-ready**: Used in Teisutis for email, reports, AI processing

## Example Use Cases

- **Teisutis**: Process KB articles, generate AI responses, send notifications
- **SaaS apps**: Email verification, invoice generation, data exports
- **E-commerce**: Order confirmation emails, inventory syncs, payment processing
- **Analytics**: Report generation, data aggregation, cleanup tasks
- **Real-time systems**: Task progress tracking via WebSocket

## Related Skills

- [`SKILL_django-architecture.md`](../skills/SKILL_django-architecture.md) - Core Django patterns (required foundation)
- [`SKILL_django-multi-tenant.md`](../skills/SKILL_django-multi-tenant.md) - Multi-tenant context in tasks
- [`SKILL_django-async-websocket.md`](../skills/SKILL_django-async-websocket.md) - Channels for real-time updates

## Related Rules

- [`RULE_celery-context-safety.md`](../rules/RULE_celery-context-safety.md) - Tenant context critical guardrails (TBD)

## References

- [Celery Documentation](https://docs.celeryproject.org/)
- [Django Signals](https://docs.djangoproject.org/en/stable/topics/signals/)
- [Django Channels](https://channels.readthedocs.io/)
- [Redis Configuration](https://redis.io/documentation)
- [Retry Strategies](https://docs.celeryproject.org/en/stable/userguide/tasks.html#retries)

---

**Last Updated**: 2026-01-27

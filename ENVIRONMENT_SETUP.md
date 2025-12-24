# Environment Configuration - Production Ready Setup

## Overview

Your Flutter app is now configured to use environment variables via `.env` files. This setup is **production-ready** and includes built-in security protections.

## Key Features

✅ **Secure credential management** - Sensitive keys never hardcoded  
✅ **Environment detection** - Automatic development/production switching  
✅ **Production security** - Service role key disabled in production builds  
✅ **CI/CD ready** - Easy to inject secrets in deployment pipelines  
✅ **Git safe** - `.env` in `.gitignore` prevents accidental commits

## File Structure

```
frontend/
├── .env                 # Your actual credentials (⚠️ NOT in git)
├── .env.example         # Template for reference
├── .gitignore           # Configured to ignore .env files
├── pubspec.yaml         # Contains flutter_dotenv dependency
├── lib/
│   ├── config.dart      # Reads from .env, handles production safety
│   ├── main.dart        # Loads .env on startup
│   └── services/
│       └── supabase_service.dart  # Uses safe credential access
└── PRODUCTION_SETUP.md  # This guide
```

## Setup for Development

1. **Create `.env` file from template:**

   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your credentials:**

   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=eyJhbGc...
   SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...
   ENVIRONMENT=development
   ```

3. **Install dependencies:**

   ```bash
   flutter pub get
   flutter clean
   flutter run
   ```

## Setup for Production

### Option 1: GitHub Actions (Recommended)

```yaml
name: Build Release APK

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Create .env file
        run: |
          cat > frontend/.env << EOF
          SUPABASE_URL=${{ secrets.PROD_SUPABASE_URL }}
          SUPABASE_ANON_KEY=${{ secrets.PROD_SUPABASE_ANON_KEY }}
          SUPABASE_SERVICE_ROLE_KEY=${{ secrets.PROD_SUPABASE_SERVICE_ROLE_KEY }}
          ENVIRONMENT=production
          EOF

      - name: Build APK
        run: |
          cd frontend
          flutter pub get
          flutter build apk --release
```

### Option 2: Manual Build for Production

```bash
# Create production .env
cat > .env << EOF
SUPABASE_URL=https://your-prod-project.supabase.co
SUPABASE_ANON_KEY=prod_anon_key_here
SUPABASE_SERVICE_ROLE_KEY=prod_service_key_here
ENVIRONMENT=production
EOF

# Build
flutter build apk --release
flutter build ios --release
```

## Security Features Built-In

### 1. Service Role Key Protection

**Development:**

```dart
// ✅ Service role key IS available
String key = Config.supabaseServiceRoleKey;  // Returns key value
```

**Production:**

```dart
// ❌ Service role key is BLOCKED
String key = Config.supabaseServiceRoleKey;  // Returns empty string
// Warning logged: "Service role key access in production is disabled"
```

### 2. Environment Detection

```dart
Config.isDevelopment   // true/false based on kDebugMode
Config.isProduction    // true if ENVIRONMENT=production
Config.environment     // Current environment name
```

### 3. Automatic Warnings

When service role key is needed but empty:

```
[SUPABASE] ⚠️ Service role key not configured.
In development: Add your service_role key to .env file.
In production: This operation should be done via a backend server.
```

## Usage Examples

### Reading Configuration

```dart
import 'config.dart';

// Get credentials
String url = Config.supabaseUrl;
String anonKey = Config.supabaseAnonKey;

// Check environment
if (Config.isDevelopment) {
  // Dev-only code
}

if (Config.isProduction) {
  // Production-only code
}
```

### Environment-Specific Behavior

```dart
// In services/supabase_service.dart
Future<void> adminOperation() async {
  if (Config.supabaseServiceRoleKey.isEmpty) {
    if (Config.isProduction) {
      throw Exception(
        'Admin operations should be done via backend server in production'
      );
    } else {
      throw Exception('Service role key not configured in .env');
    }
  }

  // Perform admin operation using service role client
  final client = _getServiceRoleClient();
  // ...
}
```

## Deployment Checklist

- [ ] Create separate Supabase project for production
- [ ] Generate new API keys for production (Settings → API)
- [ ] Update GitHub Actions secrets with production keys
- [ ] Test build locally with production .env before deploying
- [ ] Verify service role key is NOT included in release APK:

  ```bash
  # Extract and inspect APK
  unzip -l app-release.apk | grep "\.env"  # Should show nothing
  ```

- [ ] Monitor logs for any security warnings in production
- [ ] Set up RLS policies in production Supabase
- [ ] Rotate keys periodically (quarterly recommended)

## Testing

### Test Development Setup

```bash
# .env should have service role key
echo $SUPABASE_SERVICE_ROLE_KEY  # Should output key value

# Run app in debug mode
flutter run

# Check logs for:
# [MAIN] Environment: development
# [MAIN] Is Production: false
```

### Test Production Build

```bash
# Create temp .env with ENVIRONMENT=production
echo "ENVIRONMENT=production" > .env

flutter build apk --release

# Check logs should show:
# [MAIN] Environment: production
# [MAIN] Is Production: true

# Admin operations should fail gracefully
# [SUPABASE] ⚠️ Service role key access in production is disabled
```

## Troubleshooting

| Issue                         | Solution                                             |
| ----------------------------- | ---------------------------------------------------- |
| `.env` not loading            | Run `flutter clean` and `flutter pub get`            |
| Service role key empty        | Verify `SUPABASE_SERVICE_ROLE_KEY=` in `.env`        |
| Admin operations fail in prod | Expected behavior - use backend server instead       |
| Keys exposed in git           | Run `git rm --cached .env` immediately               |
| CI/CD secrets not working     | Verify GitHub Actions secret names match `.env` vars |

## Next Steps

1. **Set your production credentials in `.env`**
2. **Run `flutter pub get` to install dependencies**
3. **Test locally with `flutter run`**
4. **Deploy using your CI/CD pipeline**
5. **Monitor logs for any issues**

## Additional Resources

- [Supabase Security Best Practices](https://supabase.com/docs/guides/auth)
- [Flutter Security](https://flutter.dev/docs/security)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

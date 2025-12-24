# Quick Start: Environment Configuration

## TL;DR - For Developers

### First Time Setup

```bash
cp .env.example .env
# Edit .env and add your Supabase credentials
SUPABASE_SERVICE_ROLE_KEY=your_key_here
ENVIRONMENT=development

flutter pub get
flutter run
```

### For Production

```bash
# Update .env with production credentials
SUPABASE_URL=https://prod-project.supabase.co
SUPABASE_ANON_KEY=prod_anon_key
SUPABASE_SERVICE_ROLE_KEY=prod_service_key
ENVIRONMENT=production

flutter build apk --release
```

## How It Works

| Setting              | Dev Build        | Prod Build              |
| -------------------- | ---------------- | ----------------------- |
| **Loads from**       | `.env` file      | `.env` or CI/CD secrets |
| **Service Role Key** | ✅ Available     | ❌ Blocked (empty)      |
| **Admin Ops**        | ✅ Work normally | ❌ Fail gracefully      |
| **RLS Policies**     | Ignored          | Enforced                |

## Important Files

| File                   | Purpose                                 |
| ---------------------- | --------------------------------------- |
| `.env`                 | Your credentials (secret, don't commit) |
| `.env.example`         | Template for team reference             |
| `lib/config.dart`      | Reads .env, handles security            |
| `ENVIRONMENT_SETUP.md` | Full production guide                   |

## Production Safety Features

1. **Service role key auto-disabled** in production builds
2. **Environment detection** prevents accidental misconfigurations
3. **Helpful error messages** guide developers
4. **Git protection** prevents secret leaks

## Key Methods in Config

```dart
Config.supabaseUrl              // Project URL
Config.supabaseAnonKey          // Client key
Config.supabaseServiceRoleKey   // Admin key (dev only)
Config.isDevelopment            // Debug mode check
Config.isProduction             // Production check
Config.environment              // Current environment
```

## Common Tasks

### Change Supabase Project

```bash
# Edit .env
SUPABASE_URL=https://new-project.supabase.co
SUPABASE_ANON_KEY=new_key_here
SUPABASE_SERVICE_ROLE_KEY=new_key_here
```

### Deploy to Production

```bash
# Update .env with prod credentials
# Commit NOTHING (it's in .gitignore)
# Use CI/CD to inject secrets at build time
```

### Test Production Locally

```bash
# Edit .env
ENVIRONMENT=production
# Admin operations will now be blocked
flutter run --release
```

### Fix "Service role key not configured" Error

```bash
# 1. Check if .env exists
ls -la .env

# 2. Verify key is set
grep SUPABASE_SERVICE_ROLE_KEY .env

# 3. If empty, copy from Supabase Settings → API

# 4. If file missing
cp .env.example .env
# Then edit and add keys
```

## Questions?

- **Development issues?** See `PRODUCTION_SETUP.md`
- **Production deployment?** See `ENVIRONMENT_SETUP.md`
- **Security concerns?** Check the Security section in `ENVIRONMENT_SETUP.md`

---

**Remember:** 🔐 Never commit `.env` files! Always use CI/CD for production deployments.

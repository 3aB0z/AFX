# Production Setup Guide

## Environment Configuration

This project uses `.env` files to manage sensitive credentials and configuration.

### Files Structure

- **`.env`** - Your actual environment variables (⚠️ NEVER commit this file!)
- **`.env.example`** - Template showing required variables
- **`.gitignore`** - Configured to ignore `.env` files

### Setup Instructions

#### 1. Local Development

```bash
# Create .env file from template
cp .env.example .env

# Edit .env and add your credentials
nano .env  # or your preferred editor
```

#### 2. Production Deployment

For production deployment, you have several options:

##### Option A: Build-Time Environment Variables (Recommended for Mobile)

```bash
# When building APK/IPA, the .env file is bundled
flutter build apk --release
flutter build ios --release
```

**Note:** The .env file will be embedded in the app binary. For maximum security:

- Use a separate Supabase project for production
- Restrict the service_role key usage (see Security Notes below)
- Consider not including service_role key in mobile builds

##### Option B: CI/CD Pipeline (Recommended)

Set up environment variables in your CI/CD system:

**GitHub Actions Example:**

```yaml
- name: Create .env file
  run: |
    echo "SUPABASE_URL=${{ secrets.SUPABASE_URL }}" > frontend/.env
    echo "SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}" >> frontend/.env
    echo "SUPABASE_SERVICE_ROLE_KEY=${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}" >> frontend/.env

- name: Build APK
  run: flutter build apk --release
```

### Security Notes

#### ⚠️ IMPORTANT: Service Role Key Security

The `SUPABASE_SERVICE_ROLE_KEY` should **NEVER** be exposed in production mobile apps because:

1. **Mobile apps can be decompiled** - Anyone can extract the key from the binary
2. **Bypasses Row Level Security (RLS)** - Anyone with this key can access/modify any data
3. **Security risk** - Malicious actors could use it to access your database

#### Recommended Production Setup

For production, we recommend:

1. **Remove service_role key from mobile builds:**

   ```dart
   // In config.dart, only load in development
   static String get supabaseServiceRoleKey =>
       kDebugMode ? (dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '') : '';
   ```

2. **Use a backend server for admin operations:**

   - Instead of calling `getRequestsByStatus()` from mobile
   - Create an API endpoint that validates user is admin
   - Backend uses service_role key to fetch data
   - Return filtered results to mobile

3. **Database RLS Policies:**
   - Ensure RLS is properly configured
   - Only allow authenticated users to view appropriate data
   - Admins should have their own role and permissions

### Environment Variables Reference

| Variable                    | Purpose                | Visibility | Required |
| --------------------------- | ---------------------- | ---------- | -------- |
| `SUPABASE_URL`              | Project URL            | Public     | Yes      |
| `SUPABASE_ANON_KEY`         | Client auth            | Public     | Yes      |
| `SUPABASE_SERVICE_ROLE_KEY` | Admin operations       | Secret     | Dev only |
| `BACKEND_BASE_URL`          | API endpoint           | Public     | No       |
| `ENVIRONMENT`               | deployment environment | Public     | No       |

### Troubleshooting

**Issue:** `.env` file not being read

- Solution: Run `flutter pub get` and `flutter clean`
- Ensure `.env` is listed in `pubspec.yaml` under `flutter.assets`

**Issue:** Service role operations returning 403

- Solution: Check that service role key is correctly set in `.env`
- Verify RLS policies are properly configured

**Issue:** Keys exposed in version control

- Solution: Remove from git history: `git rm --cached .env`
- Add to `.gitignore` immediately
- Consider using git-secrets or similar tools

### Checklist for Production

- [ ] Use separate Supabase project for production
- [ ] Update all credentials in `.env` for production values
- [ ] Remove or restrict service_role key from mobile builds
- [ ] Implement RLS policies in Supabase
- [ ] Set up CI/CD to inject secrets at build time
- [ ] Test that all features work with production credentials
- [ ] Monitor logs for any security warnings
- [ ] Rotate keys periodically
- [ ] Document your environment setup for the team

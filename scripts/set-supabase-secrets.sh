#!/usr/bin/env bash
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-pjvgtmxyxrfhabyuefne}"
ENV_FILE="${1:-.env.supabase.local}"

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is not installed or not on PATH."
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE"
  echo "Create it with: cp supabase-secrets.example.env $ENV_FILE"
  exit 1
fi

if ! grep -Eq '^OPENAI_API_KEY=.+$' "$ENV_FILE"; then
  echo "Missing OPENAI_API_KEY in $ENV_FILE"
  exit 1
fi

echo "Uploading secrets from $ENV_FILE to Supabase project $PROJECT_REF..."
if ! supabase secrets set --project-ref "$PROJECT_REF" --env-file "$ENV_FILE"; then
  echo
  echo "Secret upload failed. If Supabase says an access token is missing, run:"
  echo "  supabase login"
  echo
  echo "Or export a Supabase access token just for this command:"
  echo "  SUPABASE_ACCESS_TOKEN=... $0 $ENV_FILE"
  exit 1
fi
echo "Done. Verify names with:"
echo "  supabase secrets list --project-ref $PROJECT_REF"

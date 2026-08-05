create table if not exists platform_family_ai_relays (
  family_id uuid primary key references platform_families(id) on delete cascade,
  provider_kind text not null check (provider_kind in (
    'openai', 'google_gemini', 'deepseek', 'moonshot_kimi', 'alibaba_qwen'
  )),
  model_name text not null,
  encrypted_api_key text not null,
  guidance_enabled boolean not null default false,
  image_upload_enabled boolean not null default false,
  voice_enabled boolean not null default false,
  config_version integer not null default 1 check (config_version > 0),
  updated_by_guardian_id uuid not null references platform_guardian_accounts(id),
  updated_at timestamptz not null default now()
);

alter table platform_family_ai_relays enable row level security;

comment on table platform_family_ai_relays is
  'Encrypted guardian BYOK configuration used only as a family-scoped child AI relay. Child devices never receive provider credentials.';
comment on column platform_family_ai_relays.encrypted_api_key is
  'AES-256-GCM ciphertext. The encryption key exists only in server environment secrets.';

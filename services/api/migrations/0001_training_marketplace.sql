create extension if not exists pgcrypto;

create table if not exists marketplace_creators (
  id text primary key,
  display_name_zh text not null,
  display_name_en text not null,
  bio_zh text not null,
  bio_en text not null,
  is_verified boolean not null default false,
  rating numeric(2, 1) not null default 0 check (rating between 0 and 5),
  verified_family_count integer not null default 0 check (verified_family_count >= 0),
  internal_contact text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists marketplace_listings (
  id text primary key,
  version text not null,
  kind text not null check (kind in ('library_asset', 'single_content_pack', 'course_pack', 'mixed_growth_pack', 'official_program')),
  category text not null check (category in ('routines', 'family', 'learning', 'outdoor', 'creativity', 'library')),
  title_zh text not null,
  title_en text not null,
  summary_zh text not null,
  summary_en text not null,
  detail_zh text not null,
  detail_en text not null,
  min_age integer not null check (min_age between 2 and 18),
  max_age integer not null check (max_age between min_age and 18),
  duration_days integer not null default 0 check (duration_days between 0 and 365),
  creator_id text not null references marketplace_creators(id),
  availability_kind text not null check (availability_kind in ('free', 'beta_access', 'price_preview', 'unavailable')),
  price_preview text,
  rating numeric(2, 1) not null default 0 check (rating between 0 and 5),
  rating_count integer not null default 0 check (rating_count >= 0),
  tags_zh text[] not null default '{}',
  tags_en text[] not null default '{}',
  status text not null default 'draft' check (status in ('draft', 'review', 'published', 'suspended', 'revoked')),
  content_hash char(64) not null check (content_hash ~ '^[0-9a-f]{64}$'),
  critical_update boolean not null default false,
  revoked_at timestamptz,
  internal_notes text,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists marketplace_plan_items (
  listing_id text not null references marketplace_listings(id) on delete cascade,
  position integer not null check (position >= 0),
  pack_type text not null check (pack_type in ('basic_habits', 'chores', 'outdoor_sports', 'learning', 'skill_extension', 'finance_literacy', 'creative_works', 'family_responsibility')),
  template_id text not null,
  day_offset integer not null check (day_offset between 0 and 365),
  primary key (listing_id, position)
);

create table if not exists marketplace_reviews (
  id text primary key,
  listing_id text not null references marketplace_listings(id) on delete cascade,
  title_zh text not null,
  title_en text not null,
  body_zh text not null,
  body_en text not null,
  rating integer not null check (rating between 1 and 5),
  verified_use boolean not null default false,
  status text not null default 'review' check (status in ('review', 'published', 'hidden')),
  reviewer_internal_ref text,
  created_at timestamptz not null default now()
);

create index if not exists marketplace_listings_public_idx
  on marketplace_listings (status, category, published_at desc)
  where revoked_at is null;
create index if not exists marketplace_plan_items_listing_idx on marketplace_plan_items (listing_id, position);
create index if not exists marketplace_reviews_listing_idx on marketplace_reviews (listing_id, status);

alter table marketplace_creators enable row level security;
alter table marketplace_listings enable row level security;
alter table marketplace_plan_items enable row level security;
alter table marketplace_reviews enable row level security;

comment on table marketplace_listings is 'Server-owned marketplace catalog. Public clients read through the redacted Vercel API only.';
comment on column marketplace_listings.content_hash is 'SHA-256 of the versioned public listing and plan payload.';
comment on column marketplace_listings.revoked_at is 'Immediate catalog takedown marker; revoked rows are never returned by the public API.';

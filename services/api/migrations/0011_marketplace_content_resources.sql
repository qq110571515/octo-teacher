create table if not exists marketplace_content_resources (
  id text primary key,
  kind text not null check (kind in ('book', 'video', 'creation_template')),
  title_zh text not null,
  title_en text not null,
  summary_zh text not null default '',
  summary_en text not null default '',
  source_name text not null,
  source_url text not null,
  thumbnail_url text,
  language_code text not null default 'und',
  min_age integer not null check (min_age between 2 and 18),
  max_age integer not null check (max_age between min_age and 18),
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  categories_zh text[] not null default '{}',
  categories_en text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  creator_id text references marketplace_creators(id),
  status text not null default 'review' check (status in ('draft', 'review', 'published', 'suspended', 'revoked')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists marketplace_listing_resources (
  listing_id text not null references marketplace_listings(id) on delete cascade,
  resource_id text not null references marketplace_content_resources(id) on delete restrict,
  position integer not null check (position >= 0),
  install_behavior text not null check (install_behavior in ('library_reference', 'video_reference', 'creation_template')),
  primary key (listing_id, resource_id),
  unique (listing_id, position)
);

create index if not exists marketplace_content_resources_public_idx
  on marketplace_content_resources (status, kind, min_age, max_age)
  where status = 'published';
create index if not exists marketplace_listing_resources_listing_idx
  on marketplace_listing_resources (listing_id, position);

alter table marketplace_content_resources enable row level security;
alter table marketplace_listing_resources enable row level security;
revoke all on marketplace_content_resources from anon, authenticated;
revoke all on marketplace_listing_resources from anon, authenticated;

comment on table marketplace_content_resources is
  'Moderated market content metadata. Mobile clients receive only the public projection through the Octo Teacher API.';
comment on table marketplace_listing_resources is
  'Versioned relation from a market listing to resources installed into Library, Educational Videos, or Creation Plaza.';

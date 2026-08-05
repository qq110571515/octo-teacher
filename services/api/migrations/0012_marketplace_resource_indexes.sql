create index if not exists marketplace_content_resources_creator_idx
  on marketplace_content_resources (creator_id)
  where creator_id is not null;

create index if not exists marketplace_listing_resources_resource_idx
  on marketplace_listing_resources (resource_id);

create index if not exists marketplace_listings_creator_idx
  on marketplace_listings (creator_id);

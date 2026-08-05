import { createHash } from "node:crypto";
import postgres from "postgres";
import { readFile } from "node:fs/promises";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const official = {
  id: "creator-octoteacher-official",
  displayName: "章鱼老师官方",
  displayNameEnglish: "Octo Teacher Official",
  bio: "围绕家庭真实使用路径设计，并经过儿童安全与任务闭环检查。",
  bioEnglish: "Designed around real family routines with child-safety and workflow checks.",
  isVerified: true,
  rating: 4.9,
  verifiedFamilyCount: 38,
};

const educator = {
  id: "creator-family-rhythm-lab",
  displayName: "家庭节律实验室",
  displayNameEnglish: "Family Rhythm Lab",
  bio: "专注把家庭目标拆成孩子能够开始的小步骤。",
  bioEnglish: "Turns family goals into small steps children can actually start.",
  isVerified: true,
  rating: 4.7,
  verifiedFamilyCount: 24,
};

const commonReviews = [
  {
    id: "pace",
    title: "节奏清楚",
    titleEnglish: "Clear pace",
    body: "安装前能看到每天做什么，积分也能先调整。",
    bodyEnglish: "We could preview each day and adjust points before installing.",
    rating: 5,
    verifiedUse: true,
  },
  {
    id: "start",
    title: "孩子知道从哪里开始",
    titleEnglish: "Easy to start",
    body: "没有一下塞很多要求，第一天就能照着做。",
    bodyEnglish: "It did not dump too many demands on day one.",
    rating: 4,
    verifiedUse: true,
  },
];

const item = (packType, templateID, dayOffset) => ({ packType, templateID, dayOffset });
const officialContent = JSON.parse(
  await readFile(new URL("../data/official-content-catalog.json", import.meta.url), "utf8"),
);

const listings = [
  {
    id: "octoteacher-free-library", version: "1.1.0", kind: "library_asset", category: "library",
    title: "章鱼老师免费图书馆", titleEnglish: "Octo Teacher Free Library",
    summary: "先挑选适龄图书，再由家长决定是否下载、导入和布置阅读。",
    summaryEnglish: "Choose age-appropriate books, then decide whether to download, import, and assign reading.",
    detail: "图书与任务包分开管理。浏览不会自动下载，也不会自动给孩子布置任务。",
    detailEnglish: "Books stay separate from task packs. Browsing never downloads or assigns anything automatically.",
    minAge: 3, maxAge: 18, durationDays: 0, creator: official,
    availability: { kind: "free" }, rating: 4.9, ratingCount: 38,
    tags: ["免费", "家长确认", "独立书库"], tagsEnglish: ["Free", "Parent approved", "Separate library"],
    planItems: [], resourceIDs: officialContent.packs["octoteacher-free-library"], reviews: commonReviews,
  },
  {
    id: "octoteacher-education-videos", version: "1.0.0", kind: "library_asset", category: "learning",
    title: "章鱼老师教育视频资源库", titleEnglish: "Octo Teacher Educational Video Library",
    summary: "210 条按年龄和主题整理、逐条验证过链接的教育视频，安装后进入教育视频工作台。",
    summaryEnglish: "210 age- and topic-organized educational videos with individually validated links, installed into Educational Videos.",
    detail: "安装只加入家庭内容库，不会自动给孩子布置任务。家长可按年龄筛选、预览并逐条安排。",
    detailEnglish: "Installation adds resources to the family library without assigning tasks. Parents preview, filter by age, and assign individual videos.",
    minAge: 3, maxAge: 13, durationDays: 0, creator: official,
    availability: { kind: "free" }, rating: 4.9, ratingCount: 0,
    tags: ["教育视频", "3-13岁", "逐条验证"], tagsEnglish: ["Educational videos", "Ages 3-13", "Link checked"],
    planItems: [], resourceIDs: officialContent.packs["octoteacher-education-videos"], reviews: [],
  },
  {
    id: "independence-week", version: "1.0.0", kind: "mixed_growth_pack", category: "routines",
    title: "我的事情我来做", titleEnglish: "I Can Do It Myself",
    summary: "用 7 天练习洗漱、穿衣、书包、房间和睡前准备。",
    summaryEnglish: "A 7-day practice for washing up, dressing, packing, tidying, and bedtime.",
    detail: "每天只推进一个清晰动作，家长仍是最后审核人；任务不会直接兑换设备时间。",
    detailEnglish: "One clear action each day. Parents keep final approval, and tasks never unlock devices directly.",
    minAge: 5, maxAge: 12, durationDays: 7, creator: official,
    availability: { kind: "beta_access" }, rating: 4.9, ratingCount: 38,
    tags: ["独立", "作息", "低压力"], tagsEnglish: ["Independence", "Routine", "Low pressure"],
    planItems: [
      item("basic_habits", "habit-wash-up", 0), item("basic_habits", "habit-dress-self", 1),
      item("basic_habits", "habit-pack-bag", 2), item("basic_habits", "habit-clothes-away", 3),
      item("basic_habits", "habit-tidy-room", 4), item("basic_habits", "habit-morning-ready", 5),
      item("basic_habits", "habit-early-sleep", 6),
    ], reviews: commonReviews,
  },
  {
    id: "family-helper-week", version: "1.0.0", kind: "course_pack", category: "family",
    title: "家庭小帮手一周", titleEnglish: "Family Helper Week",
    summary: "从餐桌、衣物、垃圾和植物开始练习家庭协作。",
    summaryEnglish: "Practice family teamwork through tables, laundry, trash, and plant care.",
    detail: "每件事都来自现有家务包，证明方式和成长积分可在安装前统一调整。",
    detailEnglish: "Every task uses the existing chores workflow; proof and points can be adjusted before installation.",
    minAge: 6, maxAge: 14, durationDays: 7, creator: official,
    availability: { kind: "beta_access" }, rating: 4.9, ratingCount: 38,
    tags: ["家务", "协作", "一周"], tagsEnglish: ["Chores", "Teamwork", "One week"],
    planItems: [
      item("chores", "chore-set-table", 0), item("chores", "chore-clear-table", 1),
      item("chores", "chore-sort-laundry", 2), item("chores", "chore-trash", 3),
      item("chores", "chore-wipe-surface", 4), item("chores", "chore-pet-care", 5),
    ], reviews: commonReviews,
  },
  {
    id: "outdoor-reset", version: "1.0.0", kind: "course_pack", category: "outdoor",
    title: "放下手机去户外", titleEnglish: "Put the Phone Down and Go Outside",
    summary: "5 次安全户外活动，把屏幕后的空档变成真实体验。",
    summaryEnglish: "Five safe outdoor activities that turn screen breaks into real experiences.",
    detail: "骑行、球类和公园活动保留大人陪同标记；安装不会自动操作 Screen Time。",
    detailEnglish: "Bike, ball, and park activities keep adult-supervision flags. Installation never changes Screen Time automatically.",
    minAge: 6, maxAge: 15, durationDays: 7, creator: official,
    availability: { kind: "beta_access" }, rating: 4.9, ratingCount: 38,
    tags: ["户外", "运动", "少屏幕"], tagsEnglish: ["Outdoor", "Exercise", "Less screen"],
    planItems: [
      item("outdoor_sports", "outdoor-park-walk", 0), item("outdoor_sports", "outdoor-jump-rope", 1),
      item("outdoor_sports", "outdoor-ball-play", 3), item("outdoor_sports", "outdoor-nature-search", 5),
      item("outdoor_sports", "outdoor-family-game", 6),
    ], reviews: commonReviews,
  },
  {
    id: "creative-weekend", version: "1.0.0", kind: "course_pack", category: "creativity",
    title: "会讲故事的创作周末", titleEnglish: "A Creative Story Weekend",
    summary: "画画、手工和故事表达组成一个轻量创作项目。",
    summaryEnglish: "A small creative project combining drawing, crafts, and storytelling.",
    detail: "作品进入创作广场，AI 小伙伴可以初评，家长仍负责最终确认。",
    detailEnglish: "Work appears in Creation Plaza. The AI companion may give a first review, while parents make the final decision.",
    minAge: 5, maxAge: 14, durationDays: 3, creator: official,
    availability: { kind: "beta_access" }, rating: 4.9, ratingCount: 38,
    tags: ["绘画", "手工", "表达"], tagsEnglish: ["Drawing", "Crafts", "Expression"],
    planItems: [
      item("creative_works", "create-theme-drawing", 0), item("creative_works", "create-handcraft", 1),
      item("creative_works", "create-journal", 2),
    ], reviews: commonReviews,
  },
  {
    id: "whole-family-starter", version: "1.0.0", kind: "mixed_growth_pack", category: "learning",
    title: "家庭成长启动计划", titleEnglish: "Family Growth Starter",
    summary: "把独立、家务、学习、户外、创作和亲情任务放进同一周。",
    summaryEnglish: "A one-week mix of independence, chores, learning, outdoor play, creativity, and family care.",
    detail: "这是混合成长包示范：每个任务仍回到原来的业务模块，市场只负责选择、预览和安装。",
    detailEnglish: "This mixed pack sends every task back to its original module. The marketplace only handles discovery, preview, and installation.",
    minAge: 7, maxAge: 13, durationDays: 7, creator: official,
    availability: { kind: "beta_access" }, rating: 4.9, ratingCount: 38,
    tags: ["综合", "一周", "跨模块"], tagsEnglish: ["Mixed", "One week", "Cross-module"],
    planItems: [
      item("basic_habits", "habit-morning-ready", 0), item("chores", "chore-set-table", 0),
      item("learning", "learn-mental-math", 1), item("outdoor_sports", "outdoor-jump-rope", 2),
      item("creative_works", "create-theme-drawing", 3), item("family_responsibility", "family-call-grandparents", 4),
      item("learning", "learn-new-words", 5), item("basic_habits", "habit-early-sleep", 6),
    ], reviews: commonReviews,
  },
  {
    id: "expert-literacy-preview", version: "1.0.0", kind: "course_pack", category: "learning",
    title: "幼儿识字亲子课（预览）", titleEnglish: "Early Literacy Family Course (Preview)",
    summary: "展示未来创作者课程的简介、价格与适龄信息，当前不开放购买。",
    summaryEnglish: "A preview of future creator courses, including age guidance and price. Purchasing is not available.",
    detail: "该条目只验证产品展示，不创建订单、不写权益、不布置任务。",
    detailEnglish: "This listing only validates product presentation. It creates no order, entitlement, or task.",
    minAge: 3, maxAge: 7, durationDays: 14, creator: educator,
    availability: { kind: "price_preview", pricePreview: "$4.99" }, rating: 4.7, ratingCount: 24,
    tags: ["价格预览", "尚未开放"], tagsEnglish: ["Price preview", "Not yet available"],
    planItems: [], reviews: [],
  },
];

const sql = postgres(databaseUrl, { max: 1, prepare: false, ssl: "require" });

try {
  await sql.begin(async (transaction) => {
    for (const creator of [official, educator]) {
      await transaction`
        insert into marketplace_creators (
          id, display_name_zh, display_name_en, bio_zh, bio_en,
          is_verified, rating, verified_family_count, updated_at
        ) values (
          ${creator.id}, ${creator.displayName}, ${creator.displayNameEnglish}, ${creator.bio}, ${creator.bioEnglish},
          ${creator.isVerified}, ${creator.rating}, ${creator.verifiedFamilyCount}, now()
        )
        on conflict (id) do update set
          display_name_zh = excluded.display_name_zh,
          display_name_en = excluded.display_name_en,
          bio_zh = excluded.bio_zh,
          bio_en = excluded.bio_en,
          is_verified = excluded.is_verified,
          rating = excluded.rating,
          verified_family_count = excluded.verified_family_count,
          updated_at = now()
      `;
    }

    for (const resource of officialContent.resources) {
      await transaction`
        insert into marketplace_content_resources (
          id, kind, title_zh, title_en, summary_zh, summary_en, source_name, source_url,
          thumbnail_url, language_code, min_age, max_age, duration_seconds,
          categories_zh, categories_en, metadata, creator_id, status, published_at, updated_at
        ) values (
          ${resource.id}, ${resource.kind}, ${resource.titleZh}, ${resource.titleEn},
          ${resource.summaryZh}, ${resource.summaryEn}, ${resource.sourceName}, ${resource.sourceURL},
          ${resource.thumbnailURL ?? null}, ${resource.languageCode}, ${resource.minAge}, ${resource.maxAge},
          ${resource.durationSeconds}, ${resource.categoriesZh}, ${resource.categoriesEn},
          ${transaction.json(resource.metadata)}, ${official.id}, 'published', now(), now()
        )
        on conflict (id) do update set
          kind = excluded.kind,
          title_zh = excluded.title_zh,
          title_en = excluded.title_en,
          summary_zh = excluded.summary_zh,
          summary_en = excluded.summary_en,
          source_name = excluded.source_name,
          source_url = excluded.source_url,
          thumbnail_url = excluded.thumbnail_url,
          language_code = excluded.language_code,
          min_age = excluded.min_age,
          max_age = excluded.max_age,
          duration_seconds = excluded.duration_seconds,
          categories_zh = excluded.categories_zh,
          categories_en = excluded.categories_en,
          metadata = excluded.metadata,
          creator_id = excluded.creator_id,
          status = 'published',
          updated_at = now()
      `;
    }

    for (const listing of listings) {
      const contentHash = createHash("sha256").update(JSON.stringify(listing)).digest("hex");
      await transaction`
        insert into marketplace_listings (
          id, version, kind, category, title_zh, title_en, summary_zh, summary_en,
          detail_zh, detail_en, min_age, max_age, duration_days, creator_id,
          availability_kind, price_preview, rating, rating_count, tags_zh, tags_en,
          status, content_hash, critical_update, published_at, updated_at
        ) values (
          ${listing.id}, ${listing.version}, ${listing.kind}, ${listing.category}, ${listing.title}, ${listing.titleEnglish},
          ${listing.summary}, ${listing.summaryEnglish}, ${listing.detail}, ${listing.detailEnglish},
          ${listing.minAge}, ${listing.maxAge}, ${listing.durationDays}, ${listing.creator.id},
          ${listing.availability.kind}, ${listing.availability.pricePreview ?? null}, ${listing.rating}, ${listing.ratingCount},
          ${listing.tags}, ${listing.tagsEnglish}, 'published', ${contentHash}, false, now(), now()
        )
        on conflict (id) do update set
          version = excluded.version,
          kind = excluded.kind,
          category = excluded.category,
          title_zh = excluded.title_zh,
          title_en = excluded.title_en,
          summary_zh = excluded.summary_zh,
          summary_en = excluded.summary_en,
          detail_zh = excluded.detail_zh,
          detail_en = excluded.detail_en,
          min_age = excluded.min_age,
          max_age = excluded.max_age,
          duration_days = excluded.duration_days,
          creator_id = excluded.creator_id,
          availability_kind = excluded.availability_kind,
          price_preview = excluded.price_preview,
          rating = excluded.rating,
          rating_count = excluded.rating_count,
          tags_zh = excluded.tags_zh,
          tags_en = excluded.tags_en,
          content_hash = excluded.content_hash,
          updated_at = now()
      `;

      await transaction`delete from marketplace_plan_items where listing_id = ${listing.id}`;
      for (const [position, planItem] of listing.planItems.entries()) {
        await transaction`
          insert into marketplace_plan_items (listing_id, position, pack_type, template_id, day_offset)
          values (${listing.id}, ${position}, ${planItem.packType}, ${planItem.templateID}, ${planItem.dayOffset})
        `;
      }

      await transaction`delete from marketplace_listing_resources where listing_id = ${listing.id}`;
      for (const [position, resourceID] of (listing.resourceIDs ?? []).entries()) {
        const resource = officialContent.resources.find((candidate) => candidate.id === resourceID);
        if (!resource) throw new Error(`Unknown official content resource: ${resourceID}`);
        const behavior = resource.kind === "book" ? "library_reference"
          : resource.kind === "video" ? "video_reference" : "creation_template";
        await transaction`
          insert into marketplace_listing_resources (listing_id, resource_id, position, install_behavior)
          values (${listing.id}, ${resourceID}, ${position}, ${behavior})
        `;
      }

      await transaction`delete from marketplace_reviews where listing_id = ${listing.id}`;
      for (const review of listing.reviews) {
        await transaction`
          insert into marketplace_reviews (
            id, listing_id, title_zh, title_en, body_zh, body_en, rating, verified_use, status
          ) values (
            ${`${listing.id}-${review.id}`}, ${listing.id}, ${review.title}, ${review.titleEnglish},
            ${review.body}, ${review.bodyEnglish}, ${review.rating}, ${review.verifiedUse}, 'published'
          )
        `;
      }
    }
  });
  console.log(`Seeded ${listings.length} marketplace listings and ${officialContent.resources.length} content resources`);
} finally {
  await sql.end();
}

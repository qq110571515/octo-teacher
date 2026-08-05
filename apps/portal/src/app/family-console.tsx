"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import type { Session } from "@supabase/supabase-js";
import {
  AlertCircle,
  Archive,
  BookOpen,
  CheckCircle2,
  Clock3,
  Cloud,
  Film,
  KeyRound,
  LayoutDashboard,
  Link2,
  ListChecks,
  LockKeyhole,
  Pencil,
  Palette,
  RefreshCw,
  ShieldCheck,
  Smartphone,
  Sparkles,
  TimerReset,
  Trash2,
  UserMinus,
  UserPlus,
  UserCog,
  UsersRound,
} from "lucide-react";
import {
  PlatformApiError,
  archiveAccountFamilyChild,
  createAccountFamilyChild,
  deleteAccountFamily,
  linkAccountFamily,
  loadAccountFamily,
  renameAccountFamily,
  revokeAccountFamilyDevice,
  revokeAccountFamilyGuardian,
  updateAccountFamilyScreenTimeControl,
} from "@/lib/platform-api";
import type { FamilyConsole, FamilyTaskStatus } from "@/lib/platform-api";
import styles from "./page.module.css";

type Locale = "zh" | "en";
type ConsoleSection = "overview" | "tasks" | "learning" | "content" | "family";
type ViewState =
  | { kind: "loading" }
  | { kind: "unlinked" }
  | { kind: "ready"; console: FamilyConsole; refreshedAt: Date }
  | { kind: "error"; message: string };

const taskStatusOrder: FamilyTaskStatus[] = [
  "assigned",
  "started",
  "submitted",
  "approved",
  "rejected",
  "cancelled",
];

function defaultLocale(): Locale {
  if (typeof window === "undefined") return "en";
  const saved = window.localStorage.getItem("octo-family-console-language");
  if (saved === "zh" || saved === "en") return saved;
  return "en";
}

function subscribeLocale(onStoreChange: () => void) {
  window.addEventListener("storage", onStoreChange);
  window.addEventListener("octo-family-console-language-change", onStoreChange);
  return () => {
    window.removeEventListener("storage", onStoreChange);
    window.removeEventListener("octo-family-console-language-change", onStoreChange);
  };
}

function formatDate(value: string | Date | undefined, locale: Locale): string {
  if (!value) return locale === "zh" ? "尚无记录" : "No record yet";
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return locale === "zh" ? "时间未知" : "Time unavailable";
  return new Intl.DateTimeFormat(locale === "zh" ? "zh-CN" : "en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function durationLabel(seconds: number | undefined, locale: Locale): string | undefined {
  if (seconds === undefined || seconds < 0) return undefined;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return locale === "zh" ? `${minutes} 分钟` : `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return locale === "zh" ? `${hours} 小时 ${rest} 分钟` : `${hours} hr ${rest} min`;
}

function localDateKey(date = new Date()): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function screenTimeAuthorityLabel(resourceRef: string | undefined, locale: Locale): string {
  const normalized = resourceRef?.toLowerCase() ?? "";
  if (normalized.includes("growth_points")) {
    return locale === "zh" ? "积分兑换" : "Growth points";
  }
  if (normalized.includes("parent_pin")) {
    return locale === "zh" ? "家长 PIN" : "Parent PIN";
  }
  if (normalized.includes("guardian_remote")) {
    return locale === "zh" ? "家长远程授权" : "Guardian remote";
  }
  if (normalized.includes("school_emergency")) {
    return locale === "zh" ? "学校紧急授权" : "School emergency";
  }
  return locale === "zh" ? "其他授权" : "Other authorization";
}

function screenTimeAppDisplayLabel(appRef: string, locale: Locale): string {
  const match = /^app:([a-f0-9]{32})$/.exec(appRef.toLowerCase());
  const base = locale === "zh" ? "受控 App" : "Controlled App";
  return match ? `${base} • ${match[1].slice(0, 4).toUpperCase()}` : base;
}

function taskStatusLabel(status: FamilyTaskStatus, locale: Locale): string {
  const labels: Record<FamilyTaskStatus, [string, string]> = {
    assigned: ["待开始", "Assigned"],
    started: ["进行中", "In progress"],
    submitted: ["待审核", "Submitted"],
    approved: ["已完成", "Approved"],
    rejected: ["需重做", "Needs retry"],
    cancelled: ["已撤销", "Cancelled"],
  };
  return labels[status][locale === "zh" ? 0 : 1];
}

type ConsoleChild = FamilyConsole["children"][number];
type ConsoleTask = ConsoleChild["tasks"][number];

function childTasks(child: ConsoleChild): ConsoleTask[] {
  return child.surface?.tasks.map(({ task }) => ({
    id: task.id,
    title: task.title,
    titleEnglish: task.titleEnglish,
    status: task.status,
    deliveryStatus: task.deliveryStatus,
    growthPoints: task.growthPoints,
    plannedFor: task.plannedFor,
  })) ?? child.tasks;
}

function childPoints(child: ConsoleChild): number {
  return child.surface?.child.growthPointBalance ?? child.growthPointBalance;
}

function childTaskStatusSummary(child: ConsoleChild): Record<FamilyTaskStatus, number> {
  if (!child.surface) return child.taskStatusSummary;
  const summary = Object.fromEntries(taskStatusOrder.map((status) => [status, 0])) as Record<FamilyTaskStatus, number>;
  for (const task of childTasks(child)) summary[task.status] += 1;
  return summary;
}

function localizedTaskTitle(task: ConsoleTask, locale: Locale): string {
  return locale === "en" && task.titleEnglish?.trim() ? task.titleEnglish : task.title;
}

function authorizationLabel(value: FamilyConsole["children"][number]["availability"]["screenTime"]["authorization"], locale: Locale) {
  const labels: Record<typeof value, [string, string]> = {
    not_requested: ["未请求", "Not requested"],
    approved: ["已授权", "Approved"],
    denied: ["已拒绝", "Denied"],
    unavailable: ["设备不支持", "Unavailable"],
    error: ["需要处理", "Needs attention"],
  };
  return labels[value][locale === "zh" ? 0 : 1];
}

function enforcementLabel(value: FamilyConsole["children"][number]["availability"]["screenTime"]["enforcement"], locale: Locale) {
  const labels: Record<typeof value, [string, string]> = {
    waiting_for_authorization: ["等待授权", "Waiting for authorization"],
    waiting_for_policy: ["等待家长策略", "Waiting for policy"],
    ready: ["可以执行", "Ready"],
    applied: ["正在执行", "Applied"],
    error: ["需要处理", "Needs attention"],
  };
  return labels[value][locale === "zh" ? 0 : 1];
}

function apiErrorMessage(error: unknown, locale: Locale): string {
  if (error instanceof PlatformApiError) {
    if (error.status === 401 || error.status === 403) {
      return locale === "zh" ? "登录状态已失效，请重新登录。" : "Your session expired. Please sign in again.";
    }
    if (error.code === "invalid_family_link_code") {
      return locale === "zh" ? "链接码无效，请在家长 App 中重新生成。" : "That link code is invalid. Generate a new one in the parent app.";
    }
    if (error.code === "guardian_identity_family_conflict" || error.code === "guardian_identity_account_conflict") {
      return locale === "zh" ? "账号身份存在冲突，系统没有自动猜测或覆盖任何家庭。" : "This account has an identity conflict. No family was guessed or overwritten.";
    }
    if (error.code === "family_creator_required") {
      return locale === "zh" ? "只有家庭创建者可以执行此操作。" : "Only the family creator can do this.";
    }
    if (error.status === 422) {
      return locale === "zh" ? "提交的数据无效，请检查后重试。" : "The submitted data is invalid. Check it and try again.";
    }
    if (error.code.includes("expired")) {
      return locale === "zh" ? "链接码已过期，请重新生成。" : "That link code expired. Generate a new one.";
    }
    if (error.status === 409) {
      return locale === "zh" ? "这个账号或家庭已完成关联，请刷新后重试。" : "This account or family is already linked. Refresh and try again.";
    }
  }
  return locale === "zh" ? "家庭控制台暂时无法连接，请稍后重试。" : "The Family Console is temporarily unavailable. Please try again.";
}

function ActivitySummary({ child, locale }: { child: FamilyConsole["children"][number]; locale: Locale }) {
  const activity = child.activity;
  const rows = [
    { kind: "task" as const, icon: <ListChecks size={18} />, label: locale === "zh" ? "任务" : "Tasks" },
    { kind: "reading" as const, icon: <BookOpen size={18} />, label: locale === "zh" ? "阅读" : "Reading" },
    { kind: "video" as const, icon: <Film size={18} />, label: locale === "zh" ? "视频" : "Video" },
    { kind: "creation" as const, icon: <Palette size={18} />, label: locale === "zh" ? "创作" : "Creation" },
    { kind: "screen_time" as const, icon: <Clock3 size={18} />, label: locale === "zh" ? "App 授权时长" : "App authorized time" },
  ];
  const hasActivity = Boolean(activity && activity.recent.length > 0);

  if (!hasActivity) {
    return (
      <div className={styles.inlineEmpty}>
        <Clock3 size={18} />
        <span>{locale === "zh" ? "尚未同步活动摘要。设备产生记录后会显示在这里。" : "No activity summaries have synced yet. Device activity will appear here when available."}</span>
      </div>
    );
  }

  return (
    <div className={styles.activityGrid}>
      {rows.map(({ kind, icon, label }) => {
        const events = activity?.recent.filter((event) => event.kind === kind) ?? [];
        const duration = durationLabel(activity?.durationSeconds[kind], locale);
        const names = Array.from(new Set(events.map((event) => event.displayName))).slice(0, 4);
        const latest = events[0];
        return (
          <div className={styles.activityItem} key={kind}>
            <div className={styles.activityItemTitle}>{icon}<strong>{label}</strong></div>
            <span>{locale === "zh" ? `${events.length} 条近期记录` : `${events.length} recent records`}</span>
            {duration ? <span>{duration}</span> : null}
            {names.length > 0 ? <small>{names.join(" · ")}</small> : null}
            {latest ? <small>{formatDate(latest.occurredAt, locale)}</small> : null}
          </div>
        );
      })}
    </div>
  );
}

function ChildConsoleCard({
  child,
  locale,
  session,
  onChanged,
}: {
  child: FamilyConsole["children"][number];
  locale: Locale;
  session: Session;
  onChanged: () => Promise<void> | void;
}) {
  const [controlMinutes, setControlMinutes] = useState(30);
  const [controlBusy, setControlBusy] = useState(false);
  const [controlMessage, setControlMessage] = useState("");
  const screen = child.availability.screenTime;
  const tasks = childTasks(child);
  const statusSummary = childTaskStatusSummary(child);
  const activeTasks = tasks.filter((task) => task.status !== "cancelled");
  const latestSync = child.activity?.recent[0]?.occurredAt ?? child.lastSyncedAt;
  const screenTimeEvents = child.activity?.recent.filter((event) => event.kind === "screen_time") ?? [];
  const todayScreenTime = child.activity?.screenTimeDaily.find((row) => row.date === localDateKey());
  const screenTimeAppDaily = child.activity?.screenTimeAppDaily ?? [];
  const todayAppUsage = screenTimeAppDaily
    .filter((row) => row.date === localDateKey())
    .sort((left, right) => (
      right.durationSeconds - left.durationSeconds
      || left.appRef.localeCompare(right.appRef)
    ));
  const appUsageHistory = Array.from(new Set(screenTimeAppDaily.map((row) => row.date)))
    .sort((left, right) => right.localeCompare(left))
    .slice(0, 7)
    .map((date) => {
      const rows = screenTimeAppDaily
        .filter((row) => row.date === date)
        .sort((left, right) => (
          right.durationSeconds - left.durationSeconds
          || left.appRef.localeCompare(right.appRef)
        ));
      return {
        date,
        rows,
        durationSeconds: rows.reduce((total, row) => total + row.durationSeconds, 0),
        eventCount: rows.reduce((total, row) => total + row.eventCount, 0),
      };
    });
  const todayAuthorizedSeconds = todayScreenTime?.durationSeconds ?? 0;
  const todaySessionCount = todayScreenTime?.eventCount ?? 0;
  const totalAuthorizedSeconds = child.activity?.durationSeconds.screen_time ?? 0;
  const activityWindowDays = child.activity?.windowDays ?? 0;
  const controlApplied = screen.controlCommandId === undefined
    || screen.controlCommandId === screen.appliedControlCommandId;

  async function sendScreenTimeControl(action: "lock" | "unlock") {
    setControlBusy(true);
    setControlMessage("");
    try {
      await updateAccountFamilyScreenTimeControl(
        session,
        child.id,
        action,
        action === "unlock" ? controlMinutes : undefined,
      );
      setControlMessage(action === "lock"
        ? (locale === "zh" ? "上锁命令已发送，等待孩子设备确认。" : "Lock command sent; waiting for the child device.")
        : (locale === "zh" ? "定时解锁已发送，等待孩子设备确认。" : "Timed unlock sent; waiting for the child device."));
      await onChanged();
    } catch (error) {
      setControlMessage(apiErrorMessage(error, locale));
    } finally {
      setControlBusy(false);
    }
  }

  return (
    <article className={styles.childConsoleCard}>
      <div className={styles.childConsoleHeader}>
        <div>
          <p className={styles.eyebrow}>{locale === "zh" ? "孩子概览" : "CHILD OVERVIEW"}</p>
          <h3>{child.displayName}</h3>
          <span>{locale === "zh" ? `设备同步：${formatDate(latestSync, locale)}` : `Device sync: ${formatDate(latestSync, locale)}`}</span>
        </div>
        <div className={styles.pointsBlock}>
          <strong>{childPoints(child)}</strong>
          <span>{locale === "zh" ? "成长积分" : "Growth points"}</span>
        </div>
      </div>

      <section className={styles.consoleBand}>
        <div className={styles.bandHeading}>
          <ListChecks size={19} />
          <h4>{locale === "zh" ? "任务状态" : "Task status"}</h4>
          <span>{locale === "zh" ? `${activeTasks.length} 个有效任务` : `${activeTasks.length} active tasks`}</span>
        </div>
        <div className={styles.statusGrid}>
          {taskStatusOrder.map((status) => (
            <div key={status}>
              <strong>{statusSummary[status] ?? 0}</strong>
              <span>{taskStatusLabel(status, locale)}</span>
            </div>
          ))}
        </div>
        {tasks.length > 0 ? (
          <details className={styles.taskDetails}>
            <summary>{locale === "zh" ? "查看任务清单" : "View task list"}</summary>
            <div className={styles.taskList}>
              {tasks.map((task) => (
                <div className={styles.taskRow} key={task.id}>
                  <div><strong>{localizedTaskTitle(task, locale)}</strong><span>{taskStatusLabel(task.status, locale)} · {task.growthPoints} {locale === "zh" ? "积分" : "points"}</span></div>
                  <span className={task.deliveryStatus === "ready" ? styles.readyDot : styles.warningDot}>
                    {task.deliveryStatus === "ready" ? (locale === "zh" ? "可用" : "Ready") : (locale === "zh" ? "待处理" : "Needs attention")}
                  </span>
                </div>
              ))}
            </div>
          </details>
        ) : null}
      </section>

      <section className={styles.consoleBand}>
        <div className={styles.bandHeading}><BookOpen size={19} /><h4>{locale === "zh" ? "内容可用性" : "Content availability"}</h4></div>
        <div className={styles.availabilityGrid}>
          <div><BookOpen /><strong>{child.availability.reading.available}/{child.availability.reading.total}</strong><span>{locale === "zh" ? "阅读可用" : "Reading ready"}</span><small>{locale === "zh" ? `${child.availability.reading.digitalReady} 本数字书 · ${child.availability.reading.physicalManual} 本实体书` : `${child.availability.reading.digitalReady} digital · ${child.availability.reading.physicalManual} physical`}</small></div>
          <div><Film /><strong>{child.availability.video.available}/{child.availability.video.total}</strong><span>{locale === "zh" ? "视频可用" : "Videos ready"}</span></div>
        </div>
      </section>

      <section className={styles.consoleBand}>
        <div className={styles.bandHeading}><LockKeyhole size={19} /><h4>Screen Time</h4><span className={screen.available ? styles.statusGood : styles.statusMuted}>{screen.available ? (locale === "zh" ? "设备就绪" : "Device ready") : (locale === "zh" ? "尚未就绪" : "Not ready")}</span></div>
        <div className={styles.screenTimeFacts}>
          <span>{locale === "zh" ? "策略" : "Policy"}<strong>{screen.configured ? (locale === "zh" ? "已配置" : "Configured") : (locale === "zh" ? "未配置" : "Not configured")}</strong></span>
          <span>{locale === "zh" ? "授权" : "Authorization"}<strong>{authorizationLabel(screen.authorization, locale)}</strong></span>
          <span>{locale === "zh" ? "执行" : "Enforcement"}<strong>{enforcementLabel(screen.enforcement, locale)}</strong></span>
          <span>{locale === "zh" ? "孩子 App 目录" : "Child App Catalog"}<strong>{screen.catalogRevision === undefined ? (locale === "zh" ? "未采集" : "Not captured") : (locale === "zh" ? `${screen.catalogApplicationCount} App · 版本 ${screen.catalogRevision}` : `${screen.catalogApplicationCount} apps · revision ${screen.catalogRevision}`)}</strong></span>
          <span>{locale === "zh" ? "选择范围" : "Selection"}<strong>{locale === "zh" ? `${screen.applicationCount} App · ${screen.categoryCount} 类别 · ${screen.webDomainCount} 网站` : `${screen.applicationCount} apps · ${screen.categoryCount} categories · ${screen.webDomainCount} sites`}</strong></span>
        </div>
        <div className={styles.screenTimeControl}>
          <div className={styles.screenTimeControlStatus}>
            <strong>
              {screen.controlMode === "unlocked"
                ? (locale === "zh" ? `解锁至 ${formatDate(screen.unlockedUntil, locale)}` : `Unlocked until ${formatDate(screen.unlockedUntil, locale)}`)
                : (locale === "zh" ? "上锁" : "Locked")}
            </strong>
            <span className={controlApplied ? styles.statusGood : styles.statusPending}>
              {controlApplied
                ? (locale === "zh" ? "孩子设备已确认" : "Confirmed by child device")
                : (locale === "zh" ? "等待孩子设备执行" : "Waiting for child device")}
            </span>
          </div>
          <div className={styles.screenTimeDuration} role="group" aria-label={locale === "zh" ? "解锁时长" : "Unlock duration"}>
            {[15, 30, 60].map((minutes) => (
              <button
                aria-pressed={controlMinutes === minutes}
                className={controlMinutes === minutes ? styles.screenTimeDurationActive : ""}
                disabled={controlBusy}
                key={minutes}
                onClick={() => setControlMinutes(minutes)}
                type="button"
              >
                {minutes}
              </button>
            ))}
          </div>
          <div className={styles.screenTimeControlActions}>
            <button disabled={controlBusy || !screen.configured} onClick={() => void sendScreenTimeControl("unlock")} type="button">
              <LockKeyhole />{locale === "zh" ? "定时解锁" : "Timed unlock"}
            </button>
            <button disabled={controlBusy || !screen.configured} onClick={() => void sendScreenTimeControl("lock")} type="button">
              <ShieldCheck />{locale === "zh" ? "立即上锁" : "Lock now"}
            </button>
          </div>
          {controlMessage ? <p role="status">{controlMessage}</p> : null}
        </div>
        <div className={styles.screenTimeDaily}>
          <div className={styles.screenTimeDailyMetrics}>
            <span>{locale === "zh" ? "今日授权" : "Authorized today"}<strong>{durationLabel(todayAuthorizedSeconds, locale)}</strong></span>
            <span>{locale === "zh" ? "今日次数" : "Sessions today"}<strong>{todaySessionCount}</strong></span>
            <span>{locale === "zh" ? `近 ${activityWindowDays} 天` : `Last ${activityWindowDays} days`}<strong>{durationLabel(totalAuthorizedSeconds, locale)}</strong></span>
          </div>
          {todayAppUsage.length > 0 ? (
            <div className={styles.screenTimeAppList}>
              <strong>{locale === "zh" ? "今日逐 App 授权" : "Today by app"}</strong>
              {todayAppUsage.map((row) => (
                <div className={styles.screenTimeAppRow} key={`${row.date}:${row.appRef}:${row.authority}`}>
                  <div>
                    <strong>{screenTimeAppDisplayLabel(row.appRef, locale)}</strong>
                    <small>{screenTimeAuthorityLabel(`authority:${row.authority}`, locale)}</small>
                  </div>
                  <span>{durationLabel(row.durationSeconds, locale)}</span>
                  <small>
                    {locale === "zh" ? `${row.eventCount} 次` : `${row.eventCount} session${row.eventCount === 1 ? "" : "s"}`}
                  </small>
                </div>
              ))}
            </div>
          ) : null}
          {appUsageHistory.length > 0 ? (
            <details className={styles.screenTimeHistory}>
              <summary>{locale === "zh" ? "查看最近 7 个活动日" : "View last 7 active days"}</summary>
              <div className={styles.screenTimeHistoryDays}>
                {appUsageHistory.map((day) => (
                  <details key={day.date}>
                    <summary>
                      <strong>{day.date}</strong>
                      <span>{durationLabel(day.durationSeconds, locale)} · {locale === "zh" ? `${day.eventCount} 次` : `${day.eventCount} windows`}</span>
                    </summary>
                    <div className={styles.screenTimeAppList}>
                      {day.rows.map((row) => (
                        <div className={styles.screenTimeAppRow} key={`${row.date}:${row.appRef}:${row.authority}`}>
                          <div>
                            <strong>{screenTimeAppDisplayLabel(row.appRef, locale)}</strong>
                            <small>{screenTimeAuthorityLabel(`authority:${row.authority}`, locale)}</small>
                          </div>
                          <span>{durationLabel(row.durationSeconds, locale)}</span>
                          <small>
                            {locale === "zh" ? `${row.eventCount} 次` : `${row.eventCount} window${row.eventCount === 1 ? "" : "s"}`}
                          </small>
                        </div>
                      ))}
                    </div>
                  </details>
                ))}
              </div>
            </details>
          ) : null}
          {screenTimeEvents.length > 0 ? (
            <div className={styles.screenTimeRecent}>
              {screenTimeEvents.slice(0, 3).map((event) => (
                <div className={styles.screenTimeRecentRow} key={event.eventId}>
                  <span>{screenTimeAuthorityLabel(event.resourceRef, locale)}</span>
                  <strong>{durationLabel(event.durationSeconds, locale) ?? "—"}</strong>
                  <time>{formatDate(event.occurredAt, locale)}</time>
                </div>
              ))}
            </div>
          ) : null}
          <p className={styles.screenTimeNote}>
            {locale === "zh"
              ? "这里显示章鱼老师批准的 App 可用窗口，不是 Apple 统计的前台使用时长。云端保存执行规则所需的 Apple 不透明令牌，但不保存 App 名称或 bundle ID；网站只显示匿名 App 编号。"
              : "These are app-access windows authorized by Octo Teacher, not foreground usage measured by Apple. The cloud stores the opaque Apple tokens required for enforcement, but never app names or bundle IDs; the website shows anonymous app numbers only."}
          </p>
        </div>
      </section>

      <section className={styles.consoleBand}>
        <div className={styles.bandHeading}><TimerReset size={19} /><h4>{locale === "zh" ? "活动摘要" : "Activity summaries"}</h4></div>
        <ActivitySummary child={child} locale={locale} />
      </section>

      {child.quarantine.count > 0 ? (
        <section className={styles.consoleWarning}>
          <AlertCircle size={19} />
          <div><strong>{locale === "zh" ? `${child.quarantine.count} 个内容任务需要家长处理` : `${child.quarantine.count} content tasks need attention`}</strong><p>{locale === "zh" ? "这些任务不会下发给孩子，直到阅读或视频资源准备完整。" : "These tasks stay off the child device until their reading or video resources are ready."}</p></div>
        </section>
      ) : null}
    </article>
  );
}

function SectionHeading({ icon, title, description }: { icon: React.ReactNode; title: string; description: string }) {
  return (
    <div className={styles.consoleSectionHeading}>
      <div className={styles.sectionHeadingIcon}>{icon}</div>
      <div><h3>{title}</h3><p>{description}</p></div>
    </div>
  );
}

function TasksAndPointsView({ family, locale }: { family: FamilyConsole; locale: Locale }) {
  const totalPoints = family.children.reduce((sum, child) => sum + childPoints(child), 0);
  const totalTasks = family.children.reduce((sum, child) => sum + childTasks(child).length, 0);
  const pendingReview = family.children.reduce((sum, child) => sum + (childTaskStatusSummary(child).submitted ?? 0), 0);

  return (
    <div className={styles.consoleSection}>
      <SectionHeading icon={<ListChecks />} title={locale === "zh" ? "统一任务与积分" : "Tasks and points"} description={locale === "zh" ? "跨孩子查看任务状态、交付可用性和当前成长积分。" : "Review task status, delivery readiness, and growth points across every child."} />
      <div className={styles.metricStrip}>
        <div><span>{locale === "zh" ? "全部任务" : "All tasks"}</span><strong>{totalTasks}</strong></div>
        <div><span>{locale === "zh" ? "待家长审核" : "Awaiting review"}</span><strong>{pendingReview}</strong></div>
        <div><span>{locale === "zh" ? "家庭成长积分" : "Family growth points"}</span><strong>{totalPoints}</strong></div>
      </div>
      <div className={styles.dataTableWrap}>
        <table className={styles.dataTable}>
          <thead><tr><th>{locale === "zh" ? "孩子" : "Child"}</th><th>{locale === "zh" ? "任务" : "Task"}</th><th>{locale === "zh" ? "状态" : "Status"}</th><th>{locale === "zh" ? "交付" : "Delivery"}</th><th>{locale === "zh" ? "积分" : "Points"}</th><th>{locale === "zh" ? "计划日期" : "Planned"}</th></tr></thead>
          <tbody>
            {family.children.flatMap((child) => childTasks(child).map((task) => (
              <tr key={`${child.id}-${task.id}`}>
                <td><strong>{child.displayName}</strong></td>
                <td>{localizedTaskTitle(task, locale)}</td>
                <td>{taskStatusLabel(task.status, locale)}</td>
                <td><span className={task.deliveryStatus === "ready" ? styles.tableStatusGood : styles.tableStatusWarning}>{task.deliveryStatus === "ready" ? (locale === "zh" ? "可用" : "Ready") : (locale === "zh" ? "待处理" : "Needs attention")}</span></td>
                <td>{task.growthPoints}</td>
                <td>{task.plannedFor ? formatDate(task.plannedFor, locale) : "—"}</td>
              </tr>
            )))}
            {totalTasks === 0 ? <tr><td colSpan={6} className={styles.tableEmpty}>{locale === "zh" ? "尚未同步任务。" : "No tasks have synced yet."}</td></tr> : null}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function LearningView({ family, locale }: { family: FamilyConsole; locale: Locale }) {
  const events = family.children.flatMap((child) => (child.activity?.recent ?? []).map((event) => ({ ...event, childName: child.displayName }))).sort((a, b) => b.occurredAt.localeCompare(a.occurredAt));
  return (
    <div className={styles.consoleSection}>
      <SectionHeading icon={<TimerReset />} title={locale === "zh" ? "学习活动摘要" : "Learning activity"} description={locale === "zh" ? "汇总阅读、教育视频、任务和 App 授权窗口的结构化活动记录。" : "A structured summary of reading, educational video, tasks, and approved app-access windows."} />
      <div className={styles.learningGrid}>
        {family.children.map((child) => <div className={styles.learningChild} key={child.id}><div><strong>{child.displayName}</strong><span>{locale === "zh" ? `${child.activity?.windowDays ?? 0} 天摘要窗口` : `${child.activity?.windowDays ?? 0}-day summary window`}</span></div><ActivitySummary child={child} locale={locale} /></div>)}
      </div>
      <div className={styles.subsectionTitle}><h4>{locale === "zh" ? "近期活动流水" : "Recent activity feed"}</h4><span>{locale === "zh" ? `${events.length} 条` : `${events.length} records`}</span></div>
      <div className={styles.activityFeed}>
        {events.slice(0, 40).map((event) => <div key={`${event.childName}-${event.eventId}`}><span className={styles.activityKind}>{event.kind === "reading" ? <BookOpen /> : event.kind === "video" ? <Film /> : event.kind === "creation" ? <Palette /> : event.kind === "screen_time" ? <Clock3 /> : <ListChecks />}</span><div><strong>{event.displayName}</strong><span>{event.childName} · {formatDate(event.occurredAt, locale)}{event.progressPercent !== undefined ? ` · ${event.progressPercent}%` : ""}{durationLabel(event.durationSeconds, locale) ? ` · ${durationLabel(event.durationSeconds, locale)}` : ""}</span></div></div>)}
        {events.length === 0 ? <div className={styles.inlineEmpty}><Clock3 /><span>{locale === "zh" ? "尚未同步学习活动。" : "No learning activity has synced yet."}</span></div> : null}
      </div>
    </div>
  );
}

function CloudContentView({ family, locale }: { family: FamilyConsole; locale: Locale }) {
  type ContentKind = "book" | "video" | "creation";
  type ContentSummary = {
    kind: ContentKind;
    title: string;
    titleEnglish?: string;
    children: Set<string>;
    latest: string;
    progress?: number;
    duration: number;
    availability: "processing" | "ready" | "unavailable" | "archived";
  };
  const resources = new Map<string, ContentSummary>();
  for (const child of family.children) {
    const surfaceContent = child.surface
      ? [...child.surface.library.books, ...child.surface.library.videos, ...child.surface.library.creations]
      : [];
    for (const content of surfaceContent) {
      const key = `${content.kind}:${content.publicRef || content.clientRef}`;
      const current = resources.get(key);
      if (current) {
        current.children.add(child.displayName);
        current.duration += content.assignment.durationSeconds ?? 0;
        if (content.updatedAt > current.latest) current.latest = content.updatedAt;
        if (content.assignment.progressPercent !== undefined) {
          current.progress = Math.max(current.progress ?? 0, content.assignment.progressPercent);
        }
      } else {
        resources.set(key, {
          kind: content.kind,
          title: content.title,
          titleEnglish: content.titleEnglish,
          children: new Set([child.displayName]),
          latest: content.updatedAt,
          progress: content.assignment.progressPercent,
          duration: content.assignment.durationSeconds ?? 0,
          availability: content.availability,
        });
      }
    }

    if (!child.surface) {
      for (const event of child.activity?.recent ?? []) {
        if (event.kind !== "reading" && event.kind !== "video" && event.kind !== "creation") continue;
        const kind: ContentKind = event.kind === "reading" ? "book" : event.kind;
        const key = event.resourceRef ?? `${kind}:${event.displayName}`;
        const current = resources.get(key);
        if (current) {
          current.children.add(child.displayName);
          current.duration += event.durationSeconds ?? 0;
          if (event.occurredAt > current.latest) current.latest = event.occurredAt;
          if (event.progressPercent !== undefined) current.progress = Math.max(current.progress ?? 0, event.progressPercent);
        } else {
          resources.set(key, {
            kind,
            title: event.displayName,
            children: new Set([child.displayName]),
            latest: event.occurredAt,
            progress: event.progressPercent,
            duration: event.durationSeconds ?? 0,
            availability: "ready",
          });
        }
      }
    }
  }
  const items = Array.from(resources.values()).sort((a, b) => b.latest.localeCompare(a.latest));
  const columns: Array<{ kind: ContentKind; title: string; icon: React.ReactNode }> = [
    { kind: "book", title: locale === "zh" ? "图书馆" : "Library", icon: <BookOpen /> },
    { kind: "video", title: locale === "zh" ? "教育视频" : "Educational videos", icon: <Film /> },
    { kind: "creation", title: locale === "zh" ? "创作广场" : "Creation plaza", icon: <Palette /> },
  ];
  const readyCount = (kind: ContentKind) => items.filter((item) => item.kind === kind && item.availability === "ready").length;

  return (
    <div className={styles.consoleSection}>
      <SectionHeading icon={<Cloud />} title={locale === "zh" ? "家庭云内容" : "Family cloud content"} description={locale === "zh" ? "图书馆、教育视频与创作广场使用同一份孩子内容清单，和手机端保持一致。" : "The library, educational videos, and creation plaza use the same child content manifest as the mobile apps."} />
      <div className={styles.contentSummary}>
        {columns.map((column) => <div key={column.kind}>{column.icon}<span>{column.title}</span><strong>{readyCount(column.kind)}</strong></div>)}
      </div>
      <div className={styles.contentColumns}>
        {columns.map((column) => {
          const columnItems = items.filter((item) => item.kind === column.kind);
          return <section key={column.kind}><div className={styles.subsectionTitle}><h4>{column.title}</h4><span>{columnItems.length}</span></div><div className={styles.resourceList}>{columnItems.map((item) => <div key={`${item.kind}-${item.title}`}><span className={styles.resourceIcon}>{column.icon}</span><div><strong>{locale === "en" && item.titleEnglish?.trim() ? item.titleEnglish : item.title}</strong><span>{Array.from(item.children).join(" · ")} · {formatDate(item.latest, locale)}</span><small>{item.progress !== undefined ? `${locale === "zh" ? "进度" : "Progress"} ${item.progress}%` : locale === "zh" ? "尚无进度摘要" : "No progress summary"}{item.duration > 0 ? ` · ${durationLabel(item.duration, locale)}` : ""} · {item.availability === "ready" ? (locale === "zh" ? "可用" : "Ready") : (locale === "zh" ? "准备中" : "Preparing")}</small></div></div>)}{columnItems.length === 0 ? <div className={styles.inlineEmpty}>{column.icon}<span>{locale === "zh" ? "尚未同步内容。" : "No content has synced yet."}</span></div> : null}</div></section>;
        })}
      </div>
    </div>
  );
}

function FamilyManagementView({
  family,
  locale,
  session,
  onChanged,
}: {
  family: FamilyConsole;
  locale: Locale;
  session: Session;
  onChanged: () => Promise<void> | void;
}) {
  const [name, setName] = useState(family.family.displayName);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [childName, setChildName] = useState("");
  const [childAge, setChildAge] = useState(8);
  const [childBusy, setChildBusy] = useState<string | undefined>();
  const [childMessage, setChildMessage] = useState("");
  const [memberBusy, setMemberBusy] = useState<string | undefined>();
  const [memberMessage, setMemberMessage] = useState("");
  const [deletingFamily, setDeletingFamily] = useState(false);

  async function submitRename(event: FormEvent) {
    event.preventDefault();
    const nextName = name.trim();
    if (!nextName || nextName === family.family.displayName) return;
    setSaving(true);
    setMessage("");
    try {
      await renameAccountFamily(session, family.family.id, nextName);
      setMessage(locale === "zh" ? "家庭名称已更新。" : "Family name updated.");
      await onChanged();
    } catch (error) {
      setMessage(apiErrorMessage(error, locale));
    } finally {
      setSaving(false);
    }
  }

  async function submitChild(event: FormEvent) {
    event.preventDefault();
    const displayName = childName.trim();
    if (!displayName) return;
    setChildBusy("create");
    setChildMessage("");
    try {
      await createAccountFamilyChild(session, { displayName, age: childAge });
      setChildName("");
      setChildMessage(locale === "zh" ? `已添加 ${displayName}。` : `Added ${displayName}.`);
      await onChanged();
    } catch (error) {
      setChildMessage(apiErrorMessage(error, locale));
    } finally {
      setChildBusy(undefined);
    }
  }

  async function archiveChild(child: FamilyConsole["children"][number]) {
    const warning = locale === "zh"
      ? `归档 ${child.displayName}？孩子设备会解除绑定，未完成任务会取消；已批准任务、积分账本和成长历史会保留。`
      : `Archive ${child.displayName}? Child devices will be unbound and unfinished tasks cancelled. Approved tasks, points, and growth history remain.`;
    if (!window.confirm(warning)) return;
    setChildBusy(child.id);
    setChildMessage("");
    try {
      await archiveAccountFamilyChild(session, child.id);
      setChildMessage(locale === "zh" ? `已归档 ${child.displayName}。` : `Archived ${child.displayName}.`);
      await onChanged();
    } catch (error) {
      setChildMessage(apiErrorMessage(error, locale));
    } finally {
      setChildBusy(undefined);
    }
  }

  async function removeGuardian(guardian: FamilyConsole["guardians"][number]) {
    const warning = locale === "zh"
      ? `移除监护人 ${guardian.displayName}？这会同时撤销其家庭设备。`
      : `Remove guardian ${guardian.displayName}? Their family devices will also be revoked.`;
    if (!window.confirm(warning)) return;
    setMemberBusy(guardian.id);
    setMemberMessage("");
    try {
      await revokeAccountFamilyGuardian(session, guardian.id);
      setMemberMessage(locale === "zh" ? `已移除 ${guardian.displayName}。` : `Removed ${guardian.displayName}.`);
      await onChanged();
    } catch (error) {
      setMemberMessage(apiErrorMessage(error, locale));
    } finally {
      setMemberBusy(undefined);
    }
  }

  async function removeDevice(device: FamilyConsole["devices"][number]) {
    const warning = locale === "zh"
      ? `撤销设备 ${device.displayName}？该设备需要重新扫码才能加入。`
      : `Revoke ${device.displayName}? It must scan a new invite to rejoin.`;
    if (!window.confirm(warning)) return;
    setMemberBusy(device.id);
    setMemberMessage("");
    try {
      await revokeAccountFamilyDevice(session, device.id);
      setMemberMessage(locale === "zh" ? `已撤销 ${device.displayName}。` : `Revoked ${device.displayName}.`);
      await onChanged();
    } catch (error) {
      setMemberMessage(apiErrorMessage(error, locale));
    } finally {
      setMemberBusy(undefined);
    }
  }

  async function removeFamily() {
    const prompt = locale === "zh"
      ? `此操作会让所有家庭设备退出。请输入家庭名称“${family.family.displayName}”确认删除：`
      : `This signs out every family device. Type “${family.family.displayName}” to delete the family:`;
    if (window.prompt(prompt) !== family.family.displayName) return;
    setDeletingFamily(true);
    setMemberMessage("");
    try {
      const receipt = await deleteAccountFamily(session, family.family.publicRef);
      setMemberMessage(locale === "zh" ? `家庭已删除。凭证：${receipt.receiptId}` : `Family deleted. Receipt: ${receipt.receiptId}`);
      await onChanged();
    } catch (error) {
      setMemberMessage(apiErrorMessage(error, locale));
    } finally {
      setDeletingFamily(false);
    }
  }

  return (
    <div className={styles.consoleSection}>
      <SectionHeading icon={<UserCog />} title={locale === "zh" ? "家庭、成员与设备" : "Family, members, and devices"} description={locale === "zh" ? "网站与家长 App 使用同一份家庭身份、成员权限和设备目录。" : "The website and parent app share one family identity, membership, and device directory."} />
      <div className={styles.managementGrid}>
        <section className={styles.managementPanel}><div className={styles.subsectionTitle}><h4>{locale === "zh" ? "家庭资料" : "Family profile"}</h4><Pencil /></div><form className={styles.renameForm} onSubmit={submitRename}><label htmlFor="family-display-name">{locale === "zh" ? "家庭名称" : "Family name"}</label><div><input id="family-display-name" value={name} onChange={(event) => setName(event.target.value)} maxLength={80} /><button disabled={saving || !name.trim() || name.trim() === family.family.displayName} type="submit">{saving ? (locale === "zh" ? "保存中…" : "Saving…") : (locale === "zh" ? "保存名称" : "Save name")}</button></div>{message ? <p className={styles.capabilityMessage} role="status">{message}</p> : null}</form><dl className={styles.profileFacts}><div><dt>{locale === "zh" ? "家庭编号" : "Family reference"}</dt><dd>{family.family.publicRef}</dd></div><div><dt>{locale === "zh" ? "云端更新时间" : "Cloud updated"}</dt><dd>{formatDate(family.family.updatedAt, locale)}</dd></div></dl></section>
        <section className={styles.managementPanel}>
          <div className={styles.subsectionTitle}><h4>{locale === "zh" ? "孩子档案" : "Child profiles"}</h4><UsersRound /></div>
          <form className={styles.childCreateForm} onSubmit={submitChild}>
            <label htmlFor="child-display-name">{locale === "zh" ? "新增孩子" : "Add a child"}</label>
            <div>
              <input id="child-display-name" value={childName} onChange={(event) => setChildName(event.target.value)} maxLength={80} placeholder={locale === "zh" ? "孩子昵称" : "Child nickname"} />
              <input aria-label={locale === "zh" ? "年龄" : "Age"} type="number" min={3} max={18} value={childAge} onChange={(event) => setChildAge(Number(event.target.value))} />
              <button disabled={childBusy !== undefined || !childName.trim()} type="submit"><UserPlus />{locale === "zh" ? "添加" : "Add"}</button>
            </div>
          </form>
          <div className={styles.memberList}>
            {family.children.map((child) => (
              <div key={child.id}>
                <span className={styles.memberAvatar}>{child.displayName.slice(0, 1).toUpperCase()}</span>
                <div><strong>{child.displayName}</strong><span>{locale === "zh" ? `${childTasks(child).length} 个任务 · ${childPoints(child)} 积分` : `${childTasks(child).length} tasks · ${childPoints(child)} points`}</span><small>{locale === "zh" ? `最近同步 ${formatDate(child.lastSyncedAt, locale)}` : `Last synced ${formatDate(child.lastSyncedAt, locale)}`}</small></div>
                <button className={styles.archiveButton} disabled={childBusy !== undefined || family.children.length <= 1} onClick={() => archiveChild(child)} type="button"><Archive />{childBusy === child.id ? (locale === "zh" ? "归档中…" : "Archiving…") : (locale === "zh" ? "归档" : "Archive")}</button>
              </div>
            ))}
          </div>
          {childMessage ? <p className={styles.childMutationMessage} role="status">{childMessage}</p> : null}
        </section>
      </div>
      <div className={styles.managementGrid}>
        <section className={styles.managementPanel}>
          <div className={styles.subsectionTitle}><h4>{locale === "zh" ? "监护人" : "Guardians"}</h4><UsersRound /></div>
          <div className={styles.memberList}>
            {family.guardians.map((guardian) => (
              <div key={guardian.id}>
                <span className={styles.memberAvatar}>{guardian.displayName.slice(0, 1).toUpperCase()}</span>
                <div><strong>{guardian.displayName}</strong><span>{guardian.isCreator ? (locale === "zh" ? "家庭创建者" : "Family creator") : (locale === "zh" ? "共同监护人" : "Co-guardian")}</span><small>{guardian.id === family.currentGuardian.id ? (locale === "zh" ? "当前网站账号" : "Current web account") : formatDate(guardian.joinedAt, locale)}</small></div>
                {family.currentGuardian.isCreator && !guardian.isCreator && guardian.id !== family.currentGuardian.id ? <button className={styles.archiveButton} disabled={memberBusy !== undefined} onClick={() => removeGuardian(guardian)} type="button"><UserMinus />{memberBusy === guardian.id ? (locale === "zh" ? "移除中…" : "Removing…") : (locale === "zh" ? "移除" : "Remove")}</button> : null}
              </div>
            ))}
          </div>
        </section>
        <section className={styles.managementPanel}>
          <div className={styles.subsectionTitle}><h4>{locale === "zh" ? "已绑定设备" : "Linked devices"}</h4><Smartphone /></div>
          <div className={styles.memberList}>
            {family.devices.filter((device) => device.status === "active").map((device) => (
              <div key={device.id}>
                <span className={styles.memberAvatar}><Smartphone size={17} /></span>
                <div><strong>{device.displayName}</strong><span>{device.requiresRebind ? (locale === "zh" ? "孩子设备 · 需要重新绑定" : "Child device · Rebind required") : device.role === "child" ? (locale === "zh" ? "孩子设备" : "Child device") : (locale === "zh" ? "监护人设备" : "Guardian device")}</span><small>{formatDate(device.boundAt, locale)}</small></div>
                {family.currentGuardian.isCreator ? <button className={styles.archiveButton} disabled={memberBusy !== undefined} onClick={() => removeDevice(device)} type="button"><UserMinus />{memberBusy === device.id ? (locale === "zh" ? "撤销中…" : "Revoking…") : (locale === "zh" ? "撤销" : "Revoke")}</button> : null}
              </div>
            ))}
          </div>
        </section>
      </div>
      {memberMessage ? <p className={styles.childMutationMessage} role="status">{memberMessage}</p> : null}
      {family.currentGuardian.isCreator ? <section className={styles.dangerZone}><div><Trash2 /><div><strong>{locale === "zh" ? "删除家庭" : "Delete family"}</strong><p>{locale === "zh" ? "永久删除云端家庭、成员关系、设备绑定和同步数据，并让所有家庭手机退出。" : "Permanently delete the cloud family, memberships, device bindings, and synced data, and sign out every family phone."}</p></div></div><button disabled={deletingFamily} onClick={removeFamily} type="button">{deletingFamily ? (locale === "zh" ? "删除中…" : "Deleting…") : (locale === "zh" ? "删除家庭" : "Delete family")}</button></section> : null}
    </div>
  );
}

export function FamilyConsolePanel({ session }: { session: Session }) {
  const locale = useSyncExternalStore<Locale>(subscribeLocale, defaultLocale, () => "zh");
  const [view, setView] = useState<ViewState>({ kind: "loading" });
  const [section, setSection] = useState<ConsoleSection>("overview");
  const [refreshing, setRefreshing] = useState(false);
  const refreshInFlight = useRef(false);
  const [linkCode, setLinkCode] = useState("");
  const [linking, setLinking] = useState(false);
  const [linkError, setLinkError] = useState("");

  const load = useCallback(async (quiet = false) => {
    if (refreshInFlight.current) return;
    refreshInFlight.current = true;
    if (quiet) setRefreshing(true);
    else setView({ kind: "loading" });
    try {
      const family = await loadAccountFamily(session);
      setView(family ? { kind: "ready", console: family, refreshedAt: new Date() } : { kind: "unlinked" });
    } catch (error) {
      setView({ kind: "error", message: apiErrorMessage(error, locale) });
    } finally {
      setRefreshing(false);
      refreshInFlight.current = false;
    }
  }, [locale, session]);

  useEffect(() => {
    let cancelled = false;
    loadAccountFamily(session)
      .then((family) => {
        if (!cancelled) {
          setView(family ? { kind: "ready", console: family, refreshedAt: new Date() } : { kind: "unlinked" });
        }
      })
      .catch((error) => {
        if (!cancelled) setView({ kind: "error", message: apiErrorMessage(error, locale) });
      });
    return () => { cancelled = true; };
  }, [locale, session]);

  useEffect(() => {
    if (view.kind !== "ready") return;

    const refreshWhenVisible = () => {
      if (document.visibilityState === "visible") void load(true);
    };
    const interval = window.setInterval(refreshWhenVisible, 30_000);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [load, view.kind]);

  const changeLocale = (next: Locale) => {
    window.localStorage.setItem("octo-family-console-language", next);
    window.dispatchEvent(new Event("octo-family-console-language-change"));
  };

  async function submitLinkCode(event: FormEvent) {
    event.preventDefault();
    const code = linkCode.trim().toUpperCase();
    if (code.length < 4) {
      setLinkError(locale === "zh" ? "请输入家长 App 生成的完整链接码。" : "Enter the complete link code from the parent app.");
      return;
    }
    setLinking(true);
    setLinkError("");
    try {
      await linkAccountFamily(session, code);
      setLinkCode("");
      await load();
    } catch (error) {
      setLinkError(apiErrorMessage(error, locale));
    } finally {
      setLinking(false);
    }
  }

  const familySync = useMemo(() => {
    if (view.kind !== "ready") return undefined;
    const childTimes = view.console.children.flatMap((child) => [child.lastSyncedAt, child.activity?.recent[0]?.occurredAt]).filter((value): value is string => Boolean(value));
    return view.console.lastSyncedAt ?? childTimes.sort().at(-1);
  }, [view]);

  return (
    <section className={styles.familyConsole} id="family-console" aria-labelledby="family-console-title">
      <div className={styles.familyConsoleTopbar}>
        <div>
          <p className={styles.eyebrow}>{locale === "zh" ? "私有家庭云" : "PRIVATE FAMILY CLOUD"}</p>
          <h2 id="family-console-title">{locale === "zh" ? "家庭控制台" : "Family Console"}</h2>
          <p>{locale === "zh" ? "查看孩子设备同步的任务、积分、内容准备情况与 Screen Time 状态。" : "Review synced tasks, points, content readiness, and Screen Time status across child devices."}</p>
        </div>
        <div className={styles.familyConsoleActions}>
          <div className={styles.languageSwitch} role="group" aria-label={locale === "zh" ? "家庭控制台语言" : "Family Console language"}>
            <button className={locale === "zh" ? styles.languageActive : ""} onClick={() => changeLocale("zh")} type="button">中文</button>
            <button className={locale === "en" ? styles.languageActive : ""} onClick={() => changeLocale("en")} type="button">EN</button>
          </div>
          {view.kind === "ready" ? <button className={styles.refreshButton} disabled={refreshing} onClick={() => void load(true)} type="button"><RefreshCw className={refreshing ? styles.spin : ""} size={17} />{locale === "zh" ? "刷新" : "Refresh"}</button> : null}
        </div>
      </div>

      {view.kind === "loading" ? (
        <div className={styles.familyConsoleState} aria-live="polite"><RefreshCw className={styles.spin} /><h3>{locale === "zh" ? "正在读取家庭数据" : "Loading family data"}</h3><p>{locale === "zh" ? "正在安全连接家庭云。" : "Securely connecting to your family cloud."}</p></div>
      ) : view.kind === "error" ? (
        <div className={styles.familyConsoleState} role="alert"><AlertCircle /><h3>{locale === "zh" ? "暂时无法打开家庭控制台" : "Family Console is unavailable"}</h3><p>{view.message}</p><button className={styles.secondaryButton} onClick={() => void load()}><RefreshCw size={17} />{locale === "zh" ? "重试" : "Try again"}</button></div>
      ) : view.kind === "unlinked" ? (
        <div className={styles.familyLinkLayout}>
          <div className={styles.familyLinkIntro}>
            <div className={styles.familyLinkIcon}><Link2 /></div>
            <p className={styles.eyebrow}>{locale === "zh" ? "一次性安全关联" : "ONE-TIME SECURE LINK"}</p>
            <h3>{locale === "zh" ? "把已批准账号连接到家庭" : "Connect this approved account to your family"}</h3>
            <p>{locale === "zh" ? "在家长手机的章鱼老师 App 中生成一次性链接码，然后在右侧输入。孩子无需注册，链接码过期后不能重复使用。" : "Generate a one-time code in the Octo Teacher parent app, then enter it here. Children do not register, and expired codes cannot be reused."}</p>
            <ol>
              <li>{locale === "zh" ? "打开家长端的软件设置与家庭云。" : "Open Software Settings and Family Cloud in the parent app."}</li>
              <li>{locale === "zh" ? "选择“连接网页家庭控制台”。" : "Choose “Connect web Family Console.”"}</li>
              <li>{locale === "zh" ? "在代码有效期内完成输入。" : "Enter the code before it expires."}</li>
            </ol>
          </div>
          <form className={styles.familyLinkForm} onSubmit={submitLinkCode}>
            <KeyRound size={23} />
            <label htmlFor="family-link-code">{locale === "zh" ? "家庭链接码" : "Family link code"}</label>
            <input id="family-link-code" value={linkCode} onChange={(event) => setLinkCode(event.target.value.toUpperCase())} autoCapitalize="characters" autoComplete="one-time-code" spellCheck={false} maxLength={64} placeholder="ABCD-1234" />
            <button className={styles.primaryButton} disabled={linking}>{linking ? (locale === "zh" ? "正在连接…" : "Connecting…") : (locale === "zh" ? "连接家庭" : "Connect family")}<Link2 size={17} /></button>
            {linkError ? <p className={styles.formError} role="alert">{linkError}</p> : null}
          </form>
        </div>
      ) : (
        <div className={styles.familyConsoleBody}>
          <div className={styles.familySummary}>
            <div><UsersRound /><span>{locale === "zh" ? "家庭" : "Family"}</span><strong>{view.console.family.displayName}</strong></div>
            <div><Sparkles /><span>{locale === "zh" ? "家庭 AI" : "Family AI"}</span><strong>{view.console.ai.configured ? (locale === "zh" ? "已配置" : "Configured") : (locale === "zh" ? "未配置" : "Not configured")}</strong></div>
            <div><RefreshCw /><span>{locale === "zh" ? "设备最近同步" : "Latest device sync"}</span><strong>{formatDate(familySync, locale)}</strong></div>
            <div><CheckCircle2 /><span>{locale === "zh" ? "控制台自动刷新" : "Console auto-refresh"}</span><strong>{formatDate(view.refreshedAt, locale)}</strong></div>
          </div>

          <nav className={styles.consoleTabs} aria-label={locale === "zh" ? "家庭控制台视图" : "Family Console views"}>
            {([
              ["overview", <LayoutDashboard key="overview-icon" />, locale === "zh" ? "总览" : "Overview"],
              ["tasks", <ListChecks key="tasks-icon" />, locale === "zh" ? "任务与积分" : "Tasks & points"],
              ["learning", <TimerReset key="learning-icon" />, locale === "zh" ? "学习动态" : "Learning"],
              ["content", <Cloud key="content-icon" />, locale === "zh" ? "云内容" : "Cloud content"],
              ["family", <UsersRound key="family-icon" />, locale === "zh" ? "家庭与设备" : "Family & devices"],
            ] as Array<[ConsoleSection, React.ReactNode, string]>).map(([key, icon, label]) => <button aria-current={section === key ? "page" : undefined} className={section === key ? styles.consoleTabActive : ""} key={key} onClick={() => setSection(key)} type="button">{icon}<span>{label}</span></button>)}
          </nav>

          {view.console.children.length === 0 && section !== "family" ? (
            <div className={styles.familyConsoleState}><UsersRound /><h3>{locale === "zh" ? "家庭中还没有孩子设备" : "No child devices yet"}</h3><p>{locale === "zh" ? "请先在家长 App 中创建孩子并用二维码连接孩子手机。" : "Create a child in the parent app, then connect their device with a QR code."}</p></div>
          ) : section === "overview" ? (
            <div className={styles.childrenGrid}>{view.console.children.map((child) => (
              <ChildConsoleCard
                child={child}
                locale={locale}
                session={session}
                onChanged={() => load(true)}
                key={child.id}
              />
            ))}</div>
          ) : section === "tasks" ? (
            <TasksAndPointsView family={view.console} locale={locale} />
          ) : section === "learning" ? (
            <LearningView family={view.console} locale={locale} />
          ) : section === "content" ? (
            <CloudContentView family={view.console} locale={locale} />
          ) : (
            <FamilyManagementView family={view.console} locale={locale} session={session} onChanged={() => load(true)} />
          )}
        </div>
      )}

      <div className={styles.privacyBoundary}>
        <ShieldCheck size={20} />
        <div><strong>{locale === "zh" ? "隐私边界" : "Privacy boundary"}</strong><p>{locale === "zh" ? "家庭控制台不保存孩子原始聊天、照片、录音或 App 名称。Screen Time 仅保存绑定家庭策略所需的 Apple 不透明令牌与数量。" : "The Family Console does not store raw child chats, photos, audio, or app names. Screen Time stores only the opaque Apple tokens and counts required to bind a family policy."}</p></div>
      </div>
    </section>
  );
}

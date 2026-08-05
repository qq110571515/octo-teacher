import Image from "next/image";
import Link from "next/link";
import {
  ArrowRight,
  BookOpen,
  CheckCircle2,
  Code2,
  Database,
  ExternalLink,
  GitFork,
  HeartHandshake,
  LayoutDashboard,
  Server,
  ShieldCheck,
  Smartphone,
  TimerReset,
  UsersRound,
} from "lucide-react";
import styles from "./open-source.module.css";

const repositoryURL = "https://github.com/qq110571515/octo-teacher";

const pillars = [
  {
    icon: ShieldCheck,
    title: "Apple-native controls",
    body: "FamilyControls, ManagedSettings, and DeviceActivity provide the enforcement layer on supported Apple devices.",
  },
  {
    icon: TimerReset,
    title: "Earned access",
    body: "Children complete meaningful activities, earn growth points, and exchange them for bounded app-access windows.",
  },
  {
    icon: UsersRound,
    title: "A shared family system",
    body: "Guardians, child devices, tasks, rewards, and activity summaries are coordinated through one privacy-conscious family model.",
  },
];

const architecture = [
  { icon: Smartphone, label: "iOS app", detail: "SwiftUI, Screen Time extensions, local-first child and guardian experiences" },
  { icon: Server, label: "Platform API", detail: "TypeScript services for identity, family sync, policy commands, and audit trails" },
  { icon: LayoutDashboard, label: "Family Console", detail: "A separate guardian-facing web console for family operations and summaries" },
  { icon: Database, label: "Postgres", detail: "Durable family state with scoped sessions, migrations, and row-level boundaries" },
];

export default function Home() {
  return (
    <main className={styles.siteShell}>
      <header className={styles.header}>
        <Link className={styles.brand} href="/" aria-label="Octo Teacher home">
          <Image src="/brand/octo-teacher-logo.png" alt="" width={40} height={40} priority />
          <span>Octo Teacher</span>
        </Link>
        <nav className={styles.nav} aria-label="Main navigation">
          <a href="#principles">Principles</a>
          <a href="#architecture">Architecture</a>
          <a href="#contribute">Contribute</a>
        </nav>
        <div className={styles.headerActions}>
          <a className={styles.iconLink} href={repositoryURL} target="_blank" rel="noreferrer" aria-label="Open the Octo Teacher GitHub repository" title="GitHub repository">
            <Code2 size={20} />
          </a>
          <Link className={styles.consoleButton} href="/family">
            Family Console <ArrowRight size={17} />
          </Link>
        </div>
      </header>

      <section className={styles.hero}>
        <div className={styles.heroVisual} aria-hidden="true" />
        <div className={styles.heroInner}>
          <div className={styles.heroCopy}>
            <p className={styles.eyebrow}>OPEN SOURCE FAMILY TECHNOLOGY</p>
            <h1>Octo Teacher</h1>
            <p className={styles.heroLead}>
              A family growth system that turns learning, creativity, movement, and responsibility into healthy digital access.
            </p>
            <p className={styles.heroDetail}>
              Built in the open for families and developers who want child technology to be understandable, inspectable, and worth improving together.
            </p>
            <div className={styles.heroActions}>
              <a className={styles.primaryAction} href={repositoryURL} target="_blank" rel="noreferrer">
                <Code2 size={19} /> View source <ExternalLink size={15} />
              </a>
              <a className={styles.secondaryAction} href="#architecture">
                Explore the project <ArrowRight size={18} />
              </a>
            </div>
          </div>
        </div>
      </section>

      <section className={styles.signalBand} aria-label="Project status">
        <div><strong>MIT</strong><span>Open-source license</span></div>
        <div><strong>Swift + TypeScript</strong><span>Mobile, web, and API</span></div>
        <div><strong>Early stage</strong><span>Real devices, evolving architecture</span></div>
      </section>

      <section className={styles.principles} id="principles">
        <div className={styles.sectionIntro}>
          <p className={styles.eyebrow}>WHY OPEN SOURCE</p>
          <h2>Family technology should be inspectable.</h2>
          <p>
            Screen-time products shape household rules and children&apos;s daily lives. Octo Teacher is opening its implementation so those decisions can be questioned, tested, and improved in public.
          </p>
        </div>
        <div className={styles.pillarGrid}>
          {pillars.map(({ icon: Icon, title, body }) => (
            <article key={title}>
              <Icon size={25} aria-hidden="true" />
              <h3>{title}</h3>
              <p>{body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.architectureBand} id="architecture">
        <div className={styles.architectureInner}>
          <div className={styles.architectureHeading}>
            <p className={styles.eyebrow}>ONE REPOSITORY, FOUR SURFACES</p>
            <h2>Designed as a complete family loop.</h2>
            <p>The project combines device enforcement, guardian control, cloud coordination, and evidence-based development.</p>
          </div>
          <div className={styles.architectureGrid}>
            {architecture.map(({ icon: Icon, label, detail }, index) => (
              <article key={label}>
                <span className={styles.architectureIndex}>0{index + 1}</span>
                <Icon size={24} aria-hidden="true" />
                <h3>{label}</h3>
                <p>{detail}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className={styles.realitySection}>
        <div className={styles.sectionIntro}>
          <p className={styles.eyebrow}>PROJECT REALITY</p>
          <h2>Useful today. Still experimental.</h2>
          <p>Octo Teacher is working software under active development, not a finished parental-control product.</p>
        </div>
        <div className={styles.realityList}>
          <div><CheckCircle2 aria-hidden="true" /><strong>Implemented</strong><span>Family identity, device binding, task and point sync, Screen Time policy flows, and a guardian web console.</span></div>
          <div><GitFork aria-hidden="true" /><strong>In progress</strong><span>More reliable cross-device rule delivery, per-app activity summaries, onboarding, and migration paths for older clients.</span></div>
          <div><BookOpen aria-hidden="true" /><strong>Developer note</strong><span>Apple Screen Time capabilities require supported devices, entitlements, and real-device validation. Simulator-only results are not enough.</span></div>
        </div>
      </section>

      <section className={styles.contributeBand} id="contribute">
        <div>
          <p className={styles.eyebrow}>BUILD IT WITH US</p>
          <h2>Bring your scrutiny, not just your stars.</h2>
          <p>Architecture review, iOS reliability work, accessibility, privacy analysis, documentation, and focused bug reports are all valuable contributions.</p>
        </div>
        <div className={styles.contributeActions}>
          <a className={styles.primaryAction} href={`${repositoryURL}/blob/main/CONTRIBUTING.md`} target="_blank" rel="noreferrer">
            <HeartHandshake size={19} /> Contributing guide
          </a>
          <a className={styles.textLink} href={`${repositoryURL}/issues`} target="_blank" rel="noreferrer">
            Browse issues <ArrowRight size={17} />
          </a>
        </div>
      </section>

      <footer className={styles.footer}>
        <div className={styles.footerBrand}>
          <Image src="/brand/octo-teacher-logo.png" alt="" width={36} height={36} />
          <div><strong>Octo Teacher</strong><span>Open-source family technology</span></div>
        </div>
        <div className={styles.footerLinks}>
          <a href={repositoryURL} target="_blank" rel="noreferrer">GitHub</a>
          <Link href="/family">Family Console</Link>
          <a href={`${repositoryURL}/blob/main/LICENSE`} target="_blank" rel="noreferrer">License</a>
          <a href={`${repositoryURL}/blob/main/SECURITY.md`} target="_blank" rel="noreferrer">Security</a>
        </div>
      </footer>
    </main>
  );
}

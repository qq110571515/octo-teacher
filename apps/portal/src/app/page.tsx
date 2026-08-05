import Image from "next/image";
import Link from "next/link";
import {
  ArrowRight,
  BookOpen,
  CheckCircle2,
  Code2,
  Database,
  ExternalLink,
  Globe2,
  GitFork,
  GraduationCap,
  HeartHandshake,
  LayoutDashboard,
  MessageSquareText,
  Server,
  ShieldCheck,
  Sparkles,
  Smartphone,
  TimerReset,
  UsersRound,
} from "lucide-react";
import Guestbook from "./guestbook";
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

const transformations = [
  {
    from: "Passive consumption",
    to: "Active growth",
    body: "Learning, reading, movement, creativity, and real responsibility become visible parts of a child's digital life.",
  },
  {
    from: "Endless entertainment",
    to: "Earned recreation",
    body: "Entertainment is not treated as forbidden. It becomes a healthy choice unlocked by meaningful effort and bounded by clear family rules.",
  },
  {
    from: "Daily negotiation",
    to: "Shared agreements",
    body: "Parents set the boundaries, children understand the path, and the system applies the same transparent rules every day.",
  },
  {
    from: "Screen time",
    to: "Growth time",
    body: "The question changes from how long a child used a phone to what that powerful device helped the child become.",
  },
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
          <a href="#vision">Vision</a>
          <a href="#principles">Principles</a>
          <a href="#architecture">Architecture</a>
          <a href="#guestbook">Guestbook</a>
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
              We are building a future where a child&apos;s phone is no longer mainly an entertainment machine. It becomes a tool for learning, creativity, movement, responsibility, and human growth.
            </p>
            <p className={styles.heroDetail}>
              Octo Teacher connects real-world progress with healthy digital choice. Children earn bounded access through meaningful action, families replace daily conflict with clear agreements, and an open-source community can improve the model for children everywhere.
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
        <div><strong>A phone can teach</strong><span>Reframe the most influential device in childhood</span></div>
        <div><strong>Growth earns choice</strong><span>Build agency instead of dependence</span></div>
        <div><strong>Open to the world</strong><span>A public system families can inspect and improve</span></div>
      </section>

      <section className={styles.visionSection} id="vision">
        <div className={styles.visionStatement}>
          <p className={styles.eyebrow}>THE BIG IDEA</p>
          <h2>Change what childhood screens are for.</h2>
          <p className={styles.visionLead}>
            Billions of childhood hours are being shaped by devices optimized to hold attention. Our ambition is to redirect that force: to make the phone a daily companion for curiosity, capability, health, contribution, and self-direction.
          </p>
          <p>
            This is bigger than parental control. Octo Teacher imagines a new category of technology in which digital access supports development rather than competing with it. The long-term goal is to help change how children around the world use phones, how families talk about technology, and what the technology industry chooses to optimize for.
          </p>
        </div>
        <div className={styles.visionCallout}>
          <Globe2 size={32} aria-hidden="true" />
          <strong>From attention extraction to human development.</strong>
          <span>One family at a time, built openly enough to travel much further.</span>
        </div>
        <div className={styles.transformationGrid}>
          {transformations.map((item, index) => (
            <article key={item.from}>
              <span className={styles.transformationIndex}>0{index + 1}</span>
              <p className={styles.transformationFrom}>{item.from}</p>
              <ArrowRight size={20} aria-hidden="true" />
              <h3>{item.to}</h3>
              <p>{item.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.principles} id="principles">
        <div className={styles.sectionIntro}>
          <p className={styles.eyebrow}>WHY OPEN SOURCE</p>
          <h2>A mission this important should be built in public.</h2>
          <p>
            Technology that shapes children should not be a black box. Families, educators, researchers, designers, and developers should be able to question its assumptions, inspect its safeguards, test its effects, and improve it together.
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

      <section className={styles.founderBand} id="founder">
        <div className={styles.founderIdentity}>
          <span className={styles.founderMark}>LM</span>
          <div>
            <p className={styles.eyebrow}>FOUNDER AND MAINTAINER</p>
            <h2>Leo Ma</h2>
          </div>
        </div>
        <div className={styles.founderStory}>
          <Sparkles size={27} aria-hidden="true" />
          <p className={styles.founderLead}>
            I want to contribute to American society by helping families raise more curious, capable, healthy, and responsible children.
          </p>
          <p>
            America&apos;s future depends on people who can learn independently, create boldly, care for their communities, and use freedom with responsibility. If phones now shape a large part of childhood, then those devices should help cultivate these qualities instead of steadily weakening them.
          </p>
          <p>
            Octo Teacher is my attempt to turn that belief into practical public infrastructure. I am opening the work because the problem is larger than one family, one company, or one developer. I hope families and builders across America can help prove a healthier model, then share it with the world.
          </p>
          <blockquote>
            <GraduationCap size={26} aria-hidden="true" />
            <span>Build technology that leaves children stronger than it found them.</span>
          </blockquote>
        </div>
      </section>

      <section className={styles.guestbookBand} id="guestbook">
        <div className={styles.guestbookHeading}>
          <div>
            <p className={styles.eyebrow}>A PUBLIC CONVERSATION</p>
            <h2>Leave a note for Leo.</h2>
          </div>
          <MessageSquareText size={34} aria-hidden="true" />
        </div>
        <p className={styles.guestbookIntro}>
          Share a reaction, a hard question, or an idea for where Octo Teacher should go next. No account is required.
        </p>
        <Guestbook />
      </section>

      <section className={styles.contributeBand} id="contribute">
        <div>
          <p className={styles.eyebrow}>BUILD IT WITH US</p>
          <h2>Help build a healthier relationship between childhood and technology.</h2>
          <p>Families, educators, child-development researchers, designers, privacy advocates, and engineers all have something essential to contribute. Bring your experience, your scrutiny, and your willingness to test the idea in the real world.</p>
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

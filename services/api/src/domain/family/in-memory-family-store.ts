import type { ChildProfile, DeviceLink, Family, FamilyMember, UserAccount, UserRole } from "./types.js";

export class InMemoryFamilyStore {
  private readonly users = new Map<string, UserAccount>();
  private readonly families = new Map<string, Family>();
  private readonly members = new Map<string, FamilyMember>();
  private readonly children = new Map<string, ChildProfile>();
  private readonly deviceLinks = new Map<string, DeviceLink>();

  createGuardian(input: { id: string; email: string; displayName: string; createdAt: string }): UserAccount {
    const user: UserAccount = { ...input, role: "guardian" };
    this.users.set(user.id, user);
    return user;
  }

  createFamily(input: { id: string; name: string; guardianUserId: string; createdAt: string }): Family {
    if (!this.users.has(input.guardianUserId)) {
      throw new Error(`Guardian user does not exist: ${input.guardianUserId}`);
    }
    const family: Family = {
      id: input.id,
      name: input.name,
      createdByUserId: input.guardianUserId,
      createdAt: input.createdAt,
    };
    this.families.set(family.id, family);
    this.members.set(`member:${family.id}:${input.guardianUserId}`, {
      id: `member:${family.id}:${input.guardianUserId}`,
      familyId: family.id,
      userId: input.guardianUserId,
      role: "guardian",
      status: "active",
    });
    return family;
  }

  createChildProfile(input: {
    id: string;
    familyId: string;
    displayName: string;
    guardianUserId: string;
    birthYear?: number;
    createdAt: string;
  }): ChildProfile {
    this.assertGuardian(input.familyId, input.guardianUserId);
    const child: ChildProfile = {
      id: input.id,
      familyId: input.familyId,
      displayName: input.displayName,
      birthYear: input.birthYear,
      status: "active",
      guardianUserIds: [input.guardianUserId],
      createdAt: input.createdAt,
    };
    this.children.set(child.id, child);
    return child;
  }

  inviteMember(input: { id: string; familyId: string; userId: string; role: Exclude<UserRole, "operator">; invitedByUserId: string }): FamilyMember {
    this.assertGuardian(input.familyId, input.invitedByUserId);
    const member: FamilyMember = {
      id: input.id,
      familyId: input.familyId,
      userId: input.userId,
      role: input.role,
      status: "invited",
      invitedByUserId: input.invitedByUserId,
    };
    this.members.set(member.id, member);
    return member;
  }

  createDeviceLink(input: { id: string; familyId: string; childProfileId: string; devicePublicRef: string; guardianUserId: string; createdAt: string }): DeviceLink {
    this.assertGuardian(input.familyId, input.guardianUserId);
    const child = this.children.get(input.childProfileId);
    if (!child || child.familyId !== input.familyId) {
      throw new Error(`Child profile does not belong to family: ${input.childProfileId}`);
    }
    const link: DeviceLink = {
      id: input.id,
      familyId: input.familyId,
      childProfileId: input.childProfileId,
      devicePublicRef: input.devicePublicRef,
      status: "pending",
      createdAt: input.createdAt,
    };
    this.deviceLinks.set(link.id, link);
    return link;
  }

  listChildren(familyId: string): ChildProfile[] {
    return [...this.children.values()].filter((child) => child.familyId === familyId);
  }

  private assertGuardian(familyId: string, userId: string): void {
    const member = [...this.members.values()].find(
      (candidate) => candidate.familyId === familyId && candidate.userId === userId && candidate.role === "guardian" && candidate.status === "active",
    );
    if (!member) {
      throw new Error(`User is not an active guardian for family: ${userId}`);
    }
  }
}

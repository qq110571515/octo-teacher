export type UserRole = "guardian" | "child" | "relative" | "teacher" | "operator";
export type FamilyMemberStatus = "invited" | "active" | "removed";
export type ChildProfileStatus = "active" | "archived";

export type UserAccount = {
  id: string;
  email?: string;
  displayName: string;
  role: UserRole;
  createdAt: string;
};

export type Family = {
  id: string;
  name: string;
  createdByUserId: string;
  createdAt: string;
};

export type FamilyMember = {
  id: string;
  familyId: string;
  userId: string;
  role: UserRole;
  status: FamilyMemberStatus;
  invitedByUserId?: string;
};

export type ChildProfile = {
  id: string;
  familyId: string;
  displayName: string;
  birthYear?: number;
  status: ChildProfileStatus;
  guardianUserIds: string[];
  createdAt: string;
};

export type DeviceLink = {
  id: string;
  familyId: string;
  childProfileId: string;
  devicePublicRef: string;
  status: "pending" | "linked" | "revoked";
  createdAt: string;
};

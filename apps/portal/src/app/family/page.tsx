import type { Metadata } from "next";
import FamilyPortalPage from "../family-portal-page";

export const metadata: Metadata = {
  title: "Family Console · Octo Teacher",
  description: "Sign in to manage your Octo Teacher family.",
};

export default function FamilyPage() {
  return <FamilyPortalPage />;
}

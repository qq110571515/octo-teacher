import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Octo Teacher · Open-source family technology",
  description: "An open-source family growth system for healthier digital access.",
  icons: {
    icon: "/brand/octo-teacher-app-icon.png",
    apple: "/brand/octo-teacher-app-icon.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

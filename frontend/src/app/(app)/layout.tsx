import { Providers } from "@/components/providers";
import { Header } from "@/components/header";
import { Footer } from "@/components/footer";
import { LegalBanner } from "@/components/legal-banner";

export default function AppLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <Providers>
      <LegalBanner />
      <Header />
      <main className="flex-1">{children}</main>
      <Footer />
    </Providers>
  );
}

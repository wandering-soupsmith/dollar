import Link from "next/link";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";

export default function AppLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <>
      <div className="border-b border-hairline text-center py-2 px-4">
        <p className="label" style={{ letterSpacing: "0.1em" }}>
          Transactions execute via autonomous smart contracts.{" "}
          <Link href="/terms" className="text-muted hover:text-dollar-bright underline underline-offset-2">
            Terms
          </Link>
        </p>
      </div>
      <SiteHeader />
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </>
  );
}

export default function PrivacyPolicyPage() {
  return (
    <div className="max-w-[800px] mx-auto px-6 py-12">
      <h1 className="font-h1 text-white mb-2">Privacy Policy</h1>
      <p className="text-muted mb-8">Effective Date: January 2025</p>

      <div className="prose prose-invert prose-sm max-w-none space-y-6 text-muted">
        <h2 className="font-h2 text-white mt-8">1. Introduction</h2>
        <p>
          This Privacy Policy explains how personal data may be collected and processed in
          connection with websites, documentation, and user interfaces (the &quot;Interface&quot;)
          that facilitate interaction with the Dollar Store Protocol (the &quot;Protocol&quot;).
        </p>
        <p>
          This Privacy Policy does not apply to the Protocol itself or to any smart contracts
          deployed on public blockchain networks. The Protocol is decentralized, autonomous
          software and does not collect or process personal data.
        </p>

        <h2 className="font-h2 text-white mt-8">2. Who This Policy Applies To</h2>
        <p>This Privacy Policy applies to users who access or interact with the Interface.</p>
        <p>It does not apply to:</p>
        <ul className="list-disc pl-6 space-y-2">
          <li>public blockchain networks,</li>
          <li>third-party wallets or services,</li>
          <li>third-party interfaces not published by Buckets, LLC.</li>
        </ul>

        <h2 className="font-h2 text-white mt-8">3. What Data May Be Collected</h2>
        <p>When you use the Interface, the following categories of data may be collected:</p>

        <h3 className="font-h3 text-white mt-4">(a) Technical and Usage Data</h3>
        <ul className="list-disc pl-6 space-y-2">
          <li>IP address or approximate location derived from IP,</li>
          <li>browser type, operating system, and device information,</li>
          <li>logs related to access, errors, or security events.</li>
        </ul>

        <h3 className="font-h3 text-white mt-4">(b) Wallet and Blockchain-Related Data</h3>
        <p>
          Public wallet addresses only if you choose to connect a wallet or submit such
          information through the Interface.
        </p>
        <p>
          The Interface does not monitor or analyze blockchain activity beyond what is publicly
          visible on the blockchain.
        </p>

        <h2 className="font-h2 text-white mt-8">4. What Is Not Collected</h2>
        <p>The Interface does not collect:</p>
        <ul className="list-disc pl-6 space-y-2">
          <li>names or government-issued identifiers,</li>
          <li>private keys, seed phrases, or passwords,</li>
          <li>financial account information,</li>
          <li>biometric or precise location data,</li>
          <li>identity verification or KYC/AML information.</li>
        </ul>

        <h2 className="font-h2 text-white mt-8">5. How Data Is Used</h2>
        <p>
          Any personal data collected through the Interface is used solely to operate and
          maintain the Interface. Personal data is not used for advertising, profiling, or
          marketing purposes.
        </p>

        <h2 className="font-h2 text-white mt-8">6. Infrastructure Providers and Buckets, LLC</h2>
        <p>The Interface may be hosted or maintained by Buckets, LLC or third-party providers.</p>
        <p>Buckets, LLC:</p>
        <ul className="list-disc pl-6 space-y-2">
          <li>does not operate or control the Dollar Store Protocol,</li>
          <li>does not provide services to users of the Protocol,</li>
          <li>does not custody digital assets or private keys.</li>
        </ul>
        <p>
          No contractual, fiduciary, or service relationship is created between users and
          Buckets, LLC by virtue of Interface use.
        </p>

        <h2 className="font-h2 text-white mt-8">7. Cookies and Similar Technologies</h2>
        <p>
          The Interface may use cookies or similar technologies necessary for functionality,
          security, and performance.
        </p>
        <p>
          The Interface does not use advertising cookies or engage in cross-site tracking.
        </p>

        <h2 className="font-h2 text-white mt-8">8. Changes to This Privacy Policy</h2>
        <p>
          This Privacy Policy may be updated from time to time. The &quot;Effective Date&quot;
          reflects the most recent revision.
        </p>
      </div>
    </div>
  );
}

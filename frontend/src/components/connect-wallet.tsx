"use client";

import { useAccount, useConnect, useDisconnect, useChainId } from "wagmi";
import { useState } from "react";

export function ConnectWallet() {
  const { address, isConnected } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const [showMenu, setShowMenu] = useState(false);

  const formatAddress = (addr: string) =>
    `${addr.slice(0, 6)}...${addr.slice(-4)}`;

  const getNetworkName = (id: number) => {
    switch (id) {
      case 1:
        return "Mainnet";
      case 11155111:
        return "Sepolia";
      default:
        return "Unknown";
    }
  };

  if (isConnected && address) {
    return (
      <div className="relative">
        <button
          onClick={() => setShowMenu(!showMenu)}
          className="flex items-center gap-2 px-4 py-2 bg-deep-green hover:bg-hover border border-border rounded-sm"
        >
          <span className="w-2 h-2 rounded-full bg-dollar-green" />
          <span className="text-sm tabular-nums">{formatAddress(address)}</span>
          <span className="font-caption text-muted">{getNetworkName(chainId)}</span>
        </button>

        {showMenu && (
          <div className="absolute right-0 mt-2 w-48 bg-deep-green rounded-md shadow-md border border-border overflow-hidden z-50">
            <button
              onClick={() => {
                disconnect();
                setShowMenu(false);
              }}
              className="w-full px-4 py-3 text-left text-sm hover:bg-hover text-error"
            >
              Disconnect
            </button>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="relative">
      <button
        onClick={() => setShowMenu(!showMenu)}
        disabled={isPending}
        className="px-6 py-3 bg-dollar-green hover:bg-dollar-green-light disabled:bg-disabled-bg disabled:text-muted disabled:cursor-not-allowed rounded-sm text-black font-medium text-sm"
      >
        {isPending ? "Connecting..." : "Connect Wallet"}
      </button>

      {showMenu && !isPending && (
        <div className="absolute right-0 mt-2 w-64 bg-deep-green rounded-md shadow-md border border-border overflow-hidden z-50">
          <div className="p-3 border-b border-border">
            <p className="font-caption text-muted uppercase tracking-wider">Select a wallet</p>
          </div>
          {connectors.map((connector) => (
            <button
              key={connector.uid}
              onClick={() => {
                connect({ connector });
                setShowMenu(false);
              }}
              className="w-full px-4 py-3 text-left text-sm hover:bg-hover flex items-center gap-3"
            >
              <span className="w-6 h-6 rounded bg-border flex items-center justify-center font-caption">
                {connector.name.slice(0, 2)}
              </span>
              {connector.name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

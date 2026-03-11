import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia, foundry } from 'wagmi/chains';

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'demo';
const targetChainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID || 31337);

const targetChain = targetChainId === 11155111 ? sepolia : foundry;

export const config = getDefaultConfig({
  appName: 'Bundl Index Protocol',
  projectId,
  chains: [targetChain],
  ssr: true,
});

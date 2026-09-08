import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  title: 'BEYOND THE BASIN | PoolCore',
  description: '深水之外：探索明暗交错的室内泳池、回廊与浴场。',
};
export default function RootLayout({ children }: Readonly<{children: React.ReactNode}>) {
  return <html lang="zh-CN"><body>{children}</body></html>;
}

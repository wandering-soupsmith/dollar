import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

// Geo-blocking disabled until mainnet launch
const GEO_BLOCKING_ENABLED = false

// Countries to block (ISO 3166-1 alpha-2 codes)
const BLOCKED_COUNTRIES = ['US']

export function middleware(request: NextRequest) {
  // Geo-blocking disabled for testnet
  if (!GEO_BLOCKING_ENABLED) {
    return NextResponse.next()
  }

  // Get country from various possible headers (set by CDN/hosting provider)
  const country =
    request.headers.get('x-vercel-ip-country') ||
    request.headers.get('cf-ipcountry') || // Cloudflare
    request.headers.get('x-country-code')  // Generic

  // Skip blocking for the blocked page itself and static assets
  if (
    request.nextUrl.pathname === '/blocked' ||
    request.nextUrl.pathname.startsWith('/_next') ||
    request.nextUrl.pathname.startsWith('/api') ||
    request.nextUrl.pathname.includes('.')
  ) {
    return NextResponse.next()
  }

  // Block if country is in blocked list
  if (country && BLOCKED_COUNTRIES.includes(country)) {
    return NextResponse.redirect(new URL('/blocked', request.url))
  }

  return NextResponse.next()
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     */
    '/((?!_next/static|_next/image|favicon.ico).*)',
  ],
}

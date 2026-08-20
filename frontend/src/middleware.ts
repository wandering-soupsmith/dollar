import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { canonicalSymbol } from '@/config/assets'
import { DARK_SEGMENT } from '@/config/one-pager-theme'

// Geo-blocking enabled for mainnet
const GEO_BLOCKING_ENABLED = true

// Countries to block (ISO 3166-1 alpha-2 codes)
// US + OFAC sanctioned countries
const BLOCKED_COUNTRIES = [
  'US', // United States
  'CU', // Cuba
  'IR', // Iran
  'KP', // North Korea
  'SY', // Syria
  'RU', // Russia
  'BY', // Belarus
]

// Marketing site hostnames (no app subdomain)
const MARKETING_HOSTNAMES = [
  'dollarstore.world',
  'www.dollarstore.world',
]

// App hostnames
const APP_HOSTNAMES = [
  'app.dollarstore.world',
]

export function middleware(request: NextRequest) {
  const hostname = request.headers.get('host') || ''
  const pathname = request.nextUrl.pathname

  // Skip static assets
  if (
    pathname.startsWith('/_next') ||
    pathname.startsWith('/api') ||
    pathname.includes('.')
  ) {
    return NextResponse.next()
  }

  // The shared asset route is what /<SYMBOL> rewrites onto, and it is also where the generated OG
  // images live. It must resolve on every host, so it never goes through the marketing rewrite.
  if (pathname.startsWith('/asset/')) {
    return NextResponse.next()
  }

  // Per-asset landing pages. The printed one-pagers point at dollarstore.world/<SYMBOL>, but the
  // same link has to work on the app host and on localhost, so the rewrite happens before the
  // marketing/app split and one route serves them all. `/<SYMBOL>/dark` selects the dark variant.
  // Only whitelisted symbols are rewritten, which is what keeps /terms, /markets and friends from
  // being swallowed by a catch-all.
  const segments = pathname.split('/').filter(Boolean)
  const isAssetPath =
    segments.length === 1 ||
    (segments.length === 2 && segments[1].toLowerCase() === DARK_SEGMENT)

  if (isAssetPath) {
    const symbol = canonicalSymbol(segments[0])
    if (symbol) {
      const dark = segments.length === 2
      const canonicalPath = dark ? `/${symbol}/${DARK_SEGMENT}` : `/${symbol}`

      // Send every casing to one canonical URL, then render it from the shared route.
      if (pathname !== canonicalPath) {
        const url = request.nextUrl.clone()
        url.pathname = canonicalPath
        return NextResponse.redirect(url, 308)
      }

      const url = request.nextUrl.clone()
      url.pathname = `/asset/${symbol}${dark ? `/${DARK_SEGMENT}` : ''}`
      return NextResponse.rewrite(url)
    }
  }

  // Check if this is the app site first (before marketing, since marketing hostnames are substrings)
  const isAppSite = APP_HOSTNAMES.some(h => hostname.includes(h)) || hostname.includes('localhost')

  // Marketing site: exact match on root domain (not app subdomain)
  const isMarketingSite = !isAppSite && MARKETING_HOSTNAMES.some(h => hostname.includes(h))

  // Marketing site: rewrite to /marketing/* routes
  if (isMarketingSite && !pathname.startsWith('/marketing')) {
    const url = request.nextUrl.clone()
    url.pathname = `/marketing${pathname === '/' ? '' : pathname}`
    return NextResponse.rewrite(url)
  }

  // App site: apply geo-blocking (when enabled)
  if (isAppSite) {
    // Skip blocking for the blocked page itself
    if (pathname === '/blocked') {
      return NextResponse.next()
    }

    // Geo-blocking disabled for testnet
    if (!GEO_BLOCKING_ENABLED) {
      return NextResponse.next()
    }

    // Get country from various possible headers (set by CDN/hosting provider)
    const country =
      request.headers.get('x-vercel-ip-country') ||
      request.headers.get('cf-ipcountry') || // Cloudflare
      request.headers.get('x-country-code')  // Generic

    // Block if country is in blocked list
    if (country && BLOCKED_COUNTRIES.includes(country)) {
      return NextResponse.redirect(new URL('/blocked', request.url))
    }
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

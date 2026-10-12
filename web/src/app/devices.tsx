/**
 * Vector render of the Switch 2, drawn from the product's proportions.
 * `Switch2Render` is the detailed version for the Connect screen;
 * `Switch2Icon` is simplified for small sizes.
 */

export function Switch2Render({ height = 160 }: { height?: number }) {
  const w = (height * 200) / 420;
  return (
    <svg width={w} height={height} viewBox="0 0 200 420" role="img" aria-label="Dr. Dabber Switch 2">
      <defs>
        <linearGradient id="s2-body" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#15171a" /><stop offset="0.28" stopColor="#3a3e45" /><stop offset="0.55" stopColor="#2a2d32" /><stop offset="1" stopColor="#101214" />
        </linearGradient>
        <linearGradient id="s2-cap" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#1c1e22" /><stop offset="0.4" stopColor="#4a4e56" /><stop offset="1" stopColor="#1a1c20" />
        </linearGradient>
        <linearGradient id="s2-cup" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#8d8a83" /><stop offset="0.5" stopColor="#e2ded5" /><stop offset="1" stopColor="#8d8a83" />
        </linearGradient>
        <radialGradient id="s2-glass" cx="0.38" cy="0.32" r="0.75">
          <stop offset="0" stopColor="#ffffff" stopOpacity="0.55" /><stop offset="0.5" stopColor="#dbe6f0" stopOpacity="0.18" /><stop offset="1" stopColor="#9fb3c4" stopOpacity="0.08" />
        </radialGradient>
        <filter id="s2-glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.2" /></filter>
      </defs>

      {/* glass bubbler */}
      <path d="M 86 36 Q 100 30 114 36 L 116 46 Q 100 52 84 46 Z" fill="url(#s2-glass)" stroke="rgba(255,255,255,0.55)" strokeWidth="1.2" />
      <path d="M 86 46 C 60 60, 58 104, 74 112 L 126 112 C 142 104, 140 60, 114 46 Z" fill="url(#s2-glass)" stroke="rgba(255,255,255,0.5)" strokeWidth="1.2" />
      <path d="M 92 78 C 96 70, 104 70, 108 78 L 108 110 L 92 110 Z" fill="rgba(255,255,255,0.12)" stroke="rgba(255,255,255,0.35)" strokeWidth="1" />
      <ellipse cx="86" cy="68" rx="6" ry="14" fill="rgba(255,255,255,0.35)" transform="rotate(-18 86 68)" />

      {/* cap with logo band */}
      <rect x="60" y="108" width="80" height="22" rx="8" fill="url(#s2-cap)" />
      <rect x="60" y="108" width="80" height="4" rx="2" fill="rgba(255,255,255,0.18)" />
      <text x="100" y="124" textAnchor="middle" fontSize="9" fontWeight="700" fontFamily="system-ui, sans-serif" fill="#d6dae0" letterSpacing="0.3">Dr.Dabber</text>

      {/* body */}
      <rect x="62" y="126" width="76" height="268" rx="30" fill="url(#s2-body)" />
      <rect x="62" y="126" width="76" height="268" rx="30" fill="none" stroke="rgba(255,255,255,0.08)" />
      <rect x="72" y="134" width="6" height="250" rx="3" fill="rgba(255,255,255,0.08)" />

      {/* cup window with LED edge */}
      <rect x="78" y="150" width="44" height="86" rx="7" fill="#07080a" />
      <rect x="78" y="150" width="44" height="86" rx="7" fill="none" stroke="rgba(255,255,255,0.07)" />
      <rect x="84" y="178" width="32" height="50" rx="3" fill="url(#s2-cup)" />
      <ellipse cx="100" cy="178" rx="16" ry="4" fill="#efece5" />
      <ellipse cx="100" cy="178" rx="11" ry="2.6" fill="#9c988f" />
      <path d="M 80 149 H 120" stroke="#3fd6f2" strokeWidth="3" strokeLinecap="round" filter="url(#s2-glow)" opacity="0.9" />
      <path d="M 80 149 H 120" stroke="#9fefff" strokeWidth="1.5" strokeLinecap="round" />

      {/* power button */}
      <circle cx="100" cy="268" r="13" fill="#121417" stroke="#3fd6f2" strokeWidth="2.2" />
      <circle cx="100" cy="268" r="13" fill="none" stroke="#3fd6f2" strokeWidth="4" opacity="0.35" filter="url(#s2-glow)" />
      <path d="M 104 262 C 104 258, 98 258, 98 263 L 98 272 C 98 275, 102 275, 102 272 L 102 266 Z" fill="#3fd6f2" />

      {/* +/- rocker */}
      <rect x="87" y="292" width="26" height="52" rx="9" fill="#101215" stroke="#2f3338" strokeWidth="1.2" />
      <path d="M 100 302 V 314 M 94 308 H 106" stroke="#d6dae0" strokeWidth="2" strokeLinecap="round" />
      <path d="M 94 330 H 106" stroke="#d6dae0" strokeWidth="2" strokeLinecap="round" />

      {/* foot with light ring */}
      <rect x="54" y="386" width="92" height="24" rx="10" fill="#111316" />
      <rect x="54" y="386" width="92" height="24" rx="10" fill="none" stroke="rgba(255,255,255,0.08)" />
      <path d="M 58 392 H 142" stroke="#3fd6f2" strokeWidth="3" strokeLinecap="round" opacity="0.9" filter="url(#s2-glow)" />
      <path d="M 58 392 H 142" stroke="#bff6ff" strokeWidth="1.2" strokeLinecap="round" />
      <ellipse cx="100" cy="412" rx="46" ry="6" fill="rgba(0,0,0,0.35)" />
    </svg>
  );
}

export function Switch2Icon({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9.5 3.5c0-1 5-1 5 0v1.5c0 1-5 1-5 0z" />
      <rect x="8" y="6" width="8" height="15" rx="3.5" />
      <rect x="10" y="8.5" width="4" height="5" rx="1" fill="currentColor" opacity="0.35" stroke="none" />
      <circle cx="12" cy="16.5" r="1.3" fill="currentColor" stroke="none" />
    </svg>
  );
}


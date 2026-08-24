import { useState, useEffect } from "react";
import { LiquidMetalButton } from "@/components/ui/liquid-metal-button";
import AnimatedRadio from "@/components/ui/animated-radio";
import { TiltCard } from "@/components/ui/tilt-card";
import { ButtonSoftGlow } from "@/components/ui/button-soft-glow";
import { BotanicalBackground } from "@/components/ui/botanical-background";

// Site-wide backdrop — fixed full-viewport, sits behind everything
// (z-0) so the page's normal scrolling/layout is untouched; app
// content renders in a separate sibling on top. Dark botanical
// foliage framing the edges with a guaranteed-dark centre for the
// glass cards to sit on (see botanical-background.tsx).
const SiteBackground = () => <BotanicalBackground />;

// ─── Design Tokens ───────────────────────────────────────────────
// Glassmorphism design system — surfaces are translucent frosted
// panels over the site-wide gradient background (see
// SiteBackground) rather than opaque fills. `white`/`bg` keep their
// old names since they're referenced ~150 times as "the card
// surface" / "the recessed inner surface" — only their values
// changed, so every existing card/table-header/input picks up the
// glass look for free instead of needing a per-site rewrite.
const C = {
  // Recessed inner surfaces sit a hair LIGHTER than the card — that
  // is how depth reads on a dark theme (inverse of a light one).
  bg: "rgba(255,255,255,0.075)",
  // Liquid glass, centred on rgba(255,255,255,0.08) with a shallow
  // drift so light travels across the pane rather than sitting flat.
  white: "linear-gradient(135deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.068) 48%, rgba(255,255,255,0.088) 100%)",
  border: "rgba(255,255,255,0.18)",
  borderDark: "rgba(255,255,255,0.2)",
  // 400-level tints — 600-level accents are unreadable on charcoal.
  primary: "#60a5fa",
  primaryLight: "rgba(96,165,250,0.16)",
  primaryDark: "#3b82f6",
  green: "#4ade80",
  greenLight: "rgba(74,222,128,0.16)",
  red: "#f87171",
  redLight: "rgba(248,113,113,0.16)",
  amber: "#fbbf24",
  amberLight: "rgba(251,191,36,0.16)",
  purple: "#c084fc",
  purpleLight: "rgba(192,132,252,0.16)",
  text: "#ffffff",
  textSub: "#a8aeaa",
  textMuted: "#7c827e",
  gold: "#d4af37",
  // Chrome sits deeper than the cards so they float above the frame.
  sidebarBg: "linear-gradient(180deg, rgba(23,27,25,0.7) 0%, rgba(8,11,10,0.8) 100%)",
  topbarBg: "linear-gradient(180deg, rgba(23,27,25,0.66) 0%, rgba(17,21,19,0.74) 100%)",
  // The visible 1px edge is `border` (0.18); these carry only the
  // soft top/left inner highlight + outer drop. No inset ring — with
  // the border at 0.18 it would read as a double outline.
  shadow: "0 8px 32px rgba(0,0,0,0.5), 0 2px 8px rgba(0,0,0,0.32), inset 1px 1px 0 rgba(255,255,255,0.12), inset 0 8px 24px rgba(255,255,255,0.03)",
  shadowMd: "0 12px 44px rgba(0,0,0,0.55), 0 3px 10px rgba(0,0,0,0.36), inset 1px 1px 0 rgba(255,255,255,0.14), inset 0 10px 28px rgba(255,255,255,0.035)",
  shadowLg: "0 24px 70px rgba(0,0,0,0.62), 0 4px 14px rgba(0,0,0,0.42), inset 1px 1px 0 rgba(255,255,255,0.16), inset 0 12px 34px rgba(255,255,255,0.04)",
};

// ─── Mock Data ───────────────────────────────────────────────────
// ─── API Helper ──────────────────────────────────────────────────
const apiGet = async (path) => {
  const token = localStorage.getItem("admin_token");
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { "Authorization": `Bearer ${token}` }
  });
  return res.json();
};

const apiPut = async (path, body) => {
  const token = localStorage.getItem("admin_token");
  const res = await fetch(`${API_BASE}${path}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  return res.json();
};

// Returns { ok, data } rather than bare JSON: refund approve /
// reject legitimately return 409 (already decided) and 400
// (missing reason), and the caller must be able to tell those
// apart from success instead of silently treating them as done.
const apiPost = async (path, body) => {
  const token = localStorage.getItem("admin_token");
  const res = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
    body: JSON.stringify(body || {}),
  });
  let data = {};
  try { data = await res.json(); } catch { /* empty body */ }
  return { ok: res.ok, status: res.status, data };
};

// ─── Helpers ─────────────────────────────────────────────────────
const fmt = (n) => "₹" + n.toLocaleString("en-IN");

// Backend also enforces this (requireSuperAdmin on the approve/
// reject/reverse/note routes) — this is UI convenience so a
// staff-role admin isn't shown a button that will 403.
const isSuperAdmin = () => localStorage.getItem("admin_role") === "super_admin";

const statusMeta = {
  confirmed: { color: C.green, bg: C.greenLight, label: "Confirmed" },
  pending: { color: C.amber, bg: C.amberLight, label: "Pending" },
  checked_in: { color: C.primary, bg: C.primaryLight, label: "Checked In" },
  completed: { color: C.textSub, bg: "#f9fafb", label: "Completed" },
  cancelled: { color: C.red, bg: C.redLight, label: "Cancelled" },
  active: { color: C.green, bg: C.greenLight, label: "Active" },
  blocked: { color: C.red, bg: C.redLight, label: "Blocked" },
  inactive: { color: C.textMuted, bg: "#f9fafb", label: "Inactive" },
};

const Badge = ({ status }) => {
  const m = statusMeta[status] || statusMeta.completed;
  return (
    <span style={{ background: m.bg, color: m.color, padding: "3px 10px", borderRadius: 24, fontSize: 11, fontWeight: 600, whiteSpace: "nowrap" }}>
      {m.label}
    </span>
  );
};

// ─── Avatar ───────────────────────────────────────────────────────
const Avatar = ({ name, size = 32 }) => {
  const initials = name.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase();
  const colors = [C.primary, C.green, C.purple, C.amber, "#0891b2"];
  const color = colors[name.charCodeAt(0) % colors.length];
  return (
    <div style={{ width: size, height: size, borderRadius: "50%", background: color + "20", color, display: "flex", alignItems: "center", justifyContent: "center", fontSize: size * 0.35, fontWeight: 700, flexShrink: 0 }}>
      {initials}
    </div>
  );
};

// ─── Stat Card ────────────────────────────────────────────────────
const StatCard = ({ icon, label, value, sub, trend, color = C.primary }) => (
  <TiltCard className="rounded-[20px]" style={{ flex: 1, minWidth: 170 }}>
    <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: "20px 22px", boxShadow: C.shadow }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 14 }}>
        {/* Accent chip stands in for the old emoji tile — keeps each
            card's colour coding without a glyph. */}
        <div style={{ background: color, opacity: 0.85, width: 28, height: 4, borderRadius: 99 }} />
        {trend && <div style={{ color: C.green, fontSize: 12, fontWeight: 600, background: C.greenLight, padding: "2px 8px", borderRadius: 20 }}>↑ {trend}</div>}
      </div>
      <div style={{ color: C.textSub, fontSize: 12, fontWeight: 500, marginBottom: 4 }}>{label}</div>
      <div style={{ color: C.text, fontSize: 24, fontWeight: 800, letterSpacing: -0.5 }}>{value}</div>
      {sub && <div style={{ color: C.textMuted, fontSize: 12, marginTop: 3 }}>{sub}</div>}
    </div>
  </TiltCard>
);

// ─── Input style ─────────────────────────────────────────────────
const inpStyle = {
  background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, color: C.text,
  borderRadius: 8, padding: "9px 13px", fontSize: 13, width: "100%",
  boxSizing: "border-box", fontFamily: "inherit", outline: "none",
  transition: "border-color 0.15s",
};

// ─── Login ────────────────────────────────────────────────────────
// Backend base URL. Override without editing this file by putting
// VITE_API_BASE=... in kumbh-admin/.env.local (Vite only reads
// vars prefixed with VITE_, exposed via import.meta.env, and only
// at build/start time).
//
// Default is the local backend started by
// kumbh_backend/run-local.ps1. The gateway is on 18090, not 8080
// or 8090 — both are taken on this dev machine (kumbh-local.exe
// and com.docker.backend respectively).
//
// This panel runs in a desktop browser, so plain localhost works;
// no adb tunnel is involved.
const API_BASE =
  import.meta.env.VITE_API_BASE || "http://localhost:18090/api/v1";

// Production / staging:
//   https://kumbh-gateway.onrender.com/api/v1
//   https://d3dmb495g7jwhi.cloudfront.net/api/v1

const Login = ({ onLogin }) => {
  const [user, setUser] = useState(""); const [pass, setPass] = useState(""); const [err, setErr] = useState(""); const [loading, setLoading] = useState(false);
  const attempt = async () => {
    if (!user || !pass) { setErr("Please enter username and password"); return; }
    setLoading(true); setErr("");
    try {
      const res = await fetch(`${API_BASE}/auth/admin/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: user, password: pass }),
      });
      const data = await res.json();
      if (res.ok && data.token) {
        localStorage.setItem("admin_token", data.token);
        localStorage.setItem("admin_username", data.username);
        localStorage.setItem("admin_role", data.role || "staff");
        onLogin(data.token);
      } else {
        setErr(data.error || "Invalid username or password");
      }
    } catch (e) {
      setErr("Cannot connect to server. Make sure backend is running.");
    }
    setLoading(false);
  };
  return (
    <>
      <SiteBackground />
      <div style={{ position: "relative", zIndex: 1, minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "'Inter', sans-serif" }}>
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
        <div style={{ width: 400 }}>
        {/* Header */}
        <div style={{ textAlign: "center", marginBottom: 28 }}>
          <img src="/logo.svg" alt="Kumbh Tent" style={{ height: 64, marginBottom: 10 }} />
          <div style={{ color: C.textSub, fontSize: 14, marginTop: 4 }}>Sign in to manage your dashboard</div>
        </div>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 18, padding: "32px 28px", boxShadow: C.shadowLg }}>
          <div style={{ marginBottom: 16 }}>
            <label style={{ color: C.text, fontSize: 13, fontWeight: 600, display: "block", marginBottom: 6 }}>Username</label>
            <input style={inpStyle} placeholder="Enter username" value={user} onChange={e => setUser(e.target.value)} />
          </div>
          <div style={{ marginBottom: 20 }}>
            <label style={{ color: C.text, fontSize: 13, fontWeight: 600, display: "block", marginBottom: 6 }}>Password</label>
            <input style={inpStyle} type="password" placeholder="Enter password" value={pass} onChange={e => setPass(e.target.value)} onKeyDown={e => e.key === "Enter" && attempt()} />
          </div>
          {err && <div style={{ background: C.redLight, color: C.red, borderRadius: 8, padding: "9px 13px", fontSize: 13, marginBottom: 14, fontWeight: 500 }}>{err}</div>}
          <ButtonSoftGlow onClick={attempt} disabled={loading} tone="primary" fullWidth>{loading ? "Signing in..." : "Sign In →"}</ButtonSoftGlow>
        </div>
        </div>
      </div>
    </>
  );
};

// ─── Sidebar ──────────────────────────────────────────────────────
// Grouped into sections so the ~24-item menu built up across the
// finance phases stays scannable instead of one flat list.
const NAV_SECTIONS = [
  {
    section: "Overview",
    items: [
      { id: "dashboard", label: "Rollup Dashboard" },
    ],
  },
  {
    section: "Booking Operations",
    items: [
      { id: "tents", label: "Tents" },
      { id: "bookings", label: "Bookings" },
      { id: "users", label: "Users" },
      { id: "coupons", label: "Coupons" },
      { id: "notifications", label: "Notifications" },
      { id: "inventory", label: "Inventory" },
      { id: "eticket", label: "E-Tickets" },
      { id: "qrscanner", label: "QR Check-in" },
    ],
  },
  {
    section: "Finance & Accounting",
    items: [
      { id: "finance", label: "Finance Overview" },
      { id: "payments", label: "Payments" },
      { id: "refunds", label: "Refunds" },
      { id: "invoices", label: "Invoices" },
      { id: "expenses", label: "Expenses" },
      { id: "vendorpayables", label: "Vendor Payables" },
      { id: "customerreceivables", label: "Customer Receivables" },
      { id: "reconciliation", label: "Reconciliation" },
      { id: "ledger", label: "Ledger" },
      { id: "bankaccounts", label: "Bank & Cash" },
      { id: "currency", label: "Currency" },
      { id: "gst", label: "Tax/GST" },
      { id: "revenue", label: "Revenue" },
      { id: "pnl", label: "Profit & Loss" },
      { id: "reports", label: "Financial Reports" },
    ],
  },
  {
    section: "Administration",
    items: [
      { id: "auditlog", label: "Audit Log" },
      { id: "settings", label: "Settings" },
    ],
  },
];
const Sidebar = ({ active, onNav, onLogout }) => (
  // height (not minHeight) + overflow hidden: with minHeight the
  // sidebar simply grew past the viewport, so the nav's overflow was
  // unreachable. Logo and user block are flexShrink:0 so only the
  // nav list scrolls.
  <div style={{ width: 230, background: C.sidebarBg, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", borderRight: `1px solid ${C.border}`, display: "flex", flexDirection: "column", height: "100vh", position: "fixed", left: 0, top: 0, boxShadow: "1px 0 0 rgba(255,255,255,0.04)", overflow: "visible", zIndex: 20 }}>
    {/* Brand — GlassCard treatment (components/ui/glass-card.tsx),
        scaled to the sidebar slot: same layered 3D structure
        (frosted inner pane + depth circles + hover rotate3d), with
        the KUMBH logo and gold wordmark as the content. Tilt is
        kept modest because the sidebar clips overflow. */}
    <div style={{ padding: "14px 12px", flexShrink: 0 }}>
      <div className="group h-[104px] w-full [perspective:900px]">
        <div
          className="relative h-full rounded-[26px] shadow-2xl transition-all duration-500 ease-in-out [transform-style:preserve-3d] group-hover:[box-shadow:rgba(0,0,0,0.45)_26px_42px_24px_-34px,rgba(0,0,0,0.18)_0px_20px_26px_0px] group-hover:[transform:rotate3d(1,1,0,32deg)]"
          style={{ background: "linear-gradient(135deg, #123528 0%, #07120F 55%, #020706 100%)" }}
        >
          {/* Frosted inner pane — emerald-tinted to sit in the site's
              botanical palette, with a gold lower edge tying it to
              the KUMBH wordmark. */}
          <div
            className="absolute inset-2 rounded-[30px] backdrop-blur-sm [transform-style:preserve-3d] [transform:translate3d(0,0,25px)]"
            style={{
              background: "linear-gradient(180deg, rgba(255,255,255,0.19) 0%, rgba(31,122,86,0.12) 58%, rgba(255,255,255,0.04) 100%)",
              borderBottom: "1px solid rgba(212,175,55,0.34)",
              borderLeft: "1px solid rgba(255,255,255,0.18)",
            }}
          />

          <div className="absolute top-0 right-0 [transform-style:preserve-3d]">
            {[
              { size: 76, pos: 5, z: 20, delay: "0s", bg: "rgba(31,122,86,0.17)" },
              { size: 58, pos: 8, z: 40, delay: "0.4s", bg: "rgba(26,92,66,0.22)" },
              { size: 40, pos: 13, z: 60, delay: "0.8s", bg: "rgba(212,175,55,0.16)" },
            ].map((c, i) => (
              <div
                key={i}
                className="absolute aspect-square rounded-full shadow-[rgba(2,7,6,0.35)_-10px_10px_20px_0px] transition-all duration-500 ease-in-out"
                style={{ width: c.size, top: c.pos, right: c.pos, background: c.bg, transform: `translate3d(0,0,${c.z}px)`, transitionDelay: c.delay }}
              />
            ))}

            {/* BT medallion — rides highest in the stack. Wrapper owns
                the Z depth + hover lift; the inner .kt-bt owns the
                looping float/glow, so the two never fight. */}
            <div
              className="absolute transition-all duration-500 ease-in-out [transform:translate3d(0,0,100px)] [transition-delay:1.2s] group-hover:[transform:translate3d(0,0,126px)]"
              style={{ top: 20, right: 20 }}
            >
              <div
                className="kt-bt grid aspect-square w-[42px] place-content-center rounded-full"
                style={{ background: "linear-gradient(145deg, #f0d572 0%, #d4af37 55%, #a8842a 100%)" }}
              >
                <span style={{ color: "#07120F", fontSize: 15, fontWeight: 900, letterSpacing: 0.5, lineHeight: 1 }}>BT</span>
              </div>
            </div>
          </div>

          <div className="absolute inset-0 flex flex-col justify-center px-5 [transform:translate3d(0,0,26px)]">
            <img src="/logo.svg" alt="Kumbh Tent" style={{ height: 38, width: "auto" }} />
            <div style={{ color: C.gold, fontSize: 10, fontWeight: 700, letterSpacing: 1.2, marginTop: 6, textTransform: "uppercase" }}>Admin Panel</div>
          </div>
        </div>
      </div>
    </div>
    {/* Nav */}
    {/* minHeight:0 is required — a flex child defaults to min-content
        height and refuses to shrink, which silently kills overflow. */}
    <nav className="kt-scroll" style={{ flex: 1, minHeight: 0, overflowY: "auto", padding: "12px 10px" }}>
      {NAV_SECTIONS.map(section => (
        <div key={section.section} style={{ marginBottom: 14 }}>
          <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 700, letterSpacing: 0.8, padding: "4px 10px 8px", textTransform: "uppercase" }}>{section.section}</div>
          <AnimatedRadio
            className="justify-start"
            name={`nav-${section.section}`}
            value={active}
            onChange={onNav}
            options={section.items.map(n => ({
              id: `nav-${n.id}`,
              value: n.id,
              label: (
                <span style={{ display: "flex", alignItems: "center", fontSize: 13, fontWeight: active === n.id ? 700 : 500 }}>
                  {n.label}
                </span>
              ),
            }))}
          />
        </div>
      ))}
    </nav>
    {/* User */}
    <div style={{ padding: "12px 10px", borderTop: `1px solid ${C.border}`, flexShrink: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 10px", background: C.bg, borderRadius: 10, marginBottom: 6 }}>
        <Avatar name="Admin User" size={30} />
        <div>
          <div style={{ color: C.text, fontSize: 12, fontWeight: 700 }}>Admin User</div>
          <div style={{ color: C.textMuted, fontSize: 10 }}>Super Admin</div>
        </div>
      </div>
      <LiquidMetalButton label={<>Sign Out</>} onClick={onLogout} tone="red" active size="sm" fullWidth />
    </div>
  </div>
);

// ─── Top Bar ──────────────────────────────────────────────────────
const TopBar = ({ page }) => (
  <div style={{ height: 60, background: C.topbarBg, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", borderBottom: `1px solid ${C.border}`, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 28px", position: "sticky", top: 0, zIndex: 10 }}>
    <div>
      <div style={{ color: C.text, fontSize: 16, fontWeight: 700, textTransform: "capitalize" }}>{page}</div>
      <div style={{ color: C.textMuted, fontSize: 11 }}>{new Date().toLocaleDateString("en-IN", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}</div>
    </div>
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{ background: C.greenLight, color: C.green, padding: "4px 10px", borderRadius: 24, fontSize: 11, fontWeight: 600 }}>● All Systems Online</div>
    </div>
  </div>
);

// ─── Modal ────────────────────────────────────────────────────────
const Modal = ({ title, onClose, children }) => (
  <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.62)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100, backdropFilter: "blur(8px)" }}>
    <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 18, padding: 28, width: 420, boxShadow: C.shadowLg, maxHeight: "90vh", overflowY: "auto" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 22 }}>
        <div style={{ color: C.text, fontWeight: 800, fontSize: 17 }}>{title}</div>
        <LiquidMetalButton label="✕" onClick={onClose} size="sm" width={30} title="Close" />
      </div>
      {children}
    </div>
  </div>
);

const FormField = ({ label, children }) => (
  <div style={{ marginBottom: 14 }}>
    <label style={{ color: C.text, fontSize: 12, fontWeight: 600, display: "block", marginBottom: 6 }}>{label}</label>
    {children}
  </div>
);

const BtnPrimary = ({ onClick, children, style = {}, disabled, tone }) => {
  const { flex, width, background, ...rest } = style;
  return (
    <ButtonSoftGlow
      onClick={onClick}
      disabled={disabled}
      tone={tone || (background === C.red ? "red" : "primary")}
      fullWidth={flex === 1 || width === "100%"}
      style={{ flex, ...rest }}
    >
      {children}
    </ButtonSoftGlow>
  );
};
const BtnSecondary = ({ onClick, children, style = {}, disabled, tone = "neutral" }) => {
  const { flex, width, ...rest } = style;
  return (
    <LiquidMetalButton
      label={children}
      onClick={onClick}
      disabled={disabled}
      tone={tone}
      size="sm"
      fullWidth={flex === 1 || width === "100%"}
      style={{ flex, ...rest }}
    />
  );
};

// Glass pill for lightweight chrome controls (Snan Calendar,
// Refresh) — same liquid-glass material as the cards so the
// toolbar reads as part of the same surface system.
const GlassButton = ({ onClick, children, active, style = {} }) => (
  <button
    onClick={onClick}
    style={{
      background: active ? "rgba(255,255,255,0.16)" : C.white,
      backdropFilter: "blur(26px) saturate(190%) brightness(1.12)",
      WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)",
      border: `1px solid ${active ? "rgba(255,255,255,0.3)" : C.border}`,
      boxShadow: "0 4px 16px rgba(0,0,0,0.4), inset 1px 1px 0 rgba(255,255,255,0.12)",
      color: C.text, borderRadius: 999, padding: "8px 16px", fontSize: 13,
      fontWeight: 600, cursor: "pointer", fontFamily: "inherit",
      display: "inline-flex", alignItems: "center", gap: 6,
      transition: "background 0.18s ease, border-color 0.18s ease",
      ...style,
    }}
  >
    {children}
  </button>
);

// Filter/tab/segment chip — used for every "All / Pending / Paid /
// ..." style selector throughout the finance & booking screens.
const Chip = ({ active, onClick, children, tone = "primary", style = {} }) => {
  const { flex, width, ...rest } = style;
  return (
    <LiquidMetalButton
      label={children} onClick={onClick} size="sm" tone={tone} active={!!active}
      fullWidth={flex === 1 || width === "100%"} style={{ flex, ...rest }}
    />
  );
};

// Small colored action pill for table rows (Confirm/Cancel/Reverse/
// Mark Paid/etc) — replaces the old flat light-background buttons.
const RowAction = ({ onClick, children, tone = "primary", disabled, style = {} }) => {
  const { flex, width, ...rest } = style;
  return (
    <LiquidMetalButton
      label={children} onClick={onClick} size="sm" tone={tone} active disabled={disabled}
      fullWidth={flex === 1 || width === "100%"} style={{ flex, ...rest }}
    />
  );
};

// ─── Kumbh 2027 Snan Calendar ─────────────────────────────────────
// Amrit (Shahi) Snan days are the three peak crowd days — they drive
// tent demand, so they are flagged separately from the Parva Snans.
const SNAN_EVENTS = [
  { date: "2027-07-17", day: "Saturday",  name: "Karka Sankranti",                 note: "Opening of the main bathing period", place: "Nashik", amrit: false },
  { date: "2027-07-18", day: "Sunday",    name: "Guru Purnima",                    note: "Important religious bathing day",    place: "Nashik / Trimbakeshwar", amrit: false },
  { date: "2027-07-29", day: "Thursday",  name: "Nagar Pradakshina",               note: "Major Kumbh procession",             place: "Nashik", amrit: false },
  { date: "2027-08-02", day: "Monday",    name: "1st Amrit Snan – Ashadh Amavasya",note: "First royal bathing ceremony",       place: "Nashik + Trimbakeshwar", amrit: true },
  { date: "2027-08-06", day: "Friday",    name: "Nag Panchami",                    note: "Auspicious Snan",                    place: "Trimbakeshwar / Nashik", amrit: false },
  { date: "2027-08-12", day: "Thursday",  name: "Shravan Putrada Ekadashi",        note: "Auspicious Snan",                    place: "Nashik / Trimbak", amrit: false },
  { date: "2027-08-17", day: "Tuesday",   name: "Shravan Purnima / Raksha Bandhan",note: "Important Purnima Snan",             place: "Nashik / Trimbak", amrit: false },
  { date: "2027-08-31", day: "Tuesday",   name: "2nd Amrit Snan – Shravan Amavasya",note: "Peak Snan — largest crowds",        place: "Nashik + Trimbakeshwar", amrit: true },
  { date: "2027-09-05", day: "Sunday",    name: "Rishi Panchami",                  note: "Important Parva Snan",               place: "Nashik + Trimbak", amrit: false },
  { date: "2027-09-11", day: "Saturday",  name: "3rd Amrit Snan – Vaishnava",      note: "Vaishnava Akhadas",                  place: "Nashik / Ramkund", amrit: true },
  { date: "2027-09-12", day: "Sunday",    name: "3rd Amrit Snan – Shaiva",         note: "Shaiva Akhadas",                     place: "Trimbakeshwar / Kushavarta", amrit: true },
  { date: "2027-09-15", day: "Wednesday", name: "Bhadrapada Purnima",              note: "Important Purnima Snan",             place: "Nashik + Trimbak", amrit: false },
];

const snanDate = (iso) => new Date(`${iso}T00:00:00`);
const fmtSnan = (iso) => snanDate(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
const daysUntil = (iso) => Math.ceil((snanDate(iso) - new Date()) / 86400000);

const SnanBanner = () => {
  const items = SNAN_EVENTS.map(e => `${e.amrit ? "" : ""} ${fmtSnan(e.date)} · ${e.name} · ${e.place}`);
  const strip = (
    <div style={{ display: "flex", gap: 34, paddingRight: 34, whiteSpace: "nowrap" }}>
      {items.map((t, i) => <span key={i} style={{ fontSize: 13, fontWeight: 600 }}>{t}</span>)}
    </div>
  );
  return (
    <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, color: C.text, borderRadius: 24, padding: "10px 0", marginBottom: 16, overflow: "hidden", display: "flex", alignItems: "center", boxShadow: C.shadow }}>
      <style>{`@keyframes snanMarquee { from { transform: translateX(0) } to { transform: translateX(-50%) } }`}</style>
      <div style={{ background: "rgba(212,175,55,0.16)", border: "1px solid rgba(212,175,55,0.42)", color: C.gold, padding: "4px 12px", borderRadius: 24, fontSize: 12, fontWeight: 800, margin: "0 14px", flexShrink: 0, letterSpacing: 0.4 }}>KUMBH 2027</div>
      <div style={{ overflow: "hidden", flex: 1 }}>
        {/* Duplicated strip so the -50% translate loops seamlessly */}
        <div style={{ display: "flex", width: "max-content", animation: "snanMarquee 45s linear infinite" }}>
          {strip}{strip}
        </div>
      </div>
    </div>
  );
};

const SnanCalendar = ({ onClose }) => {
  const upcoming = SNAN_EVENTS.filter(e => daysUntil(e.date) >= 0);
  return (
    <div style={{ position: "absolute", top: 46, right: 0, width: 400, maxHeight: 460, overflowY: "auto", background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadowLg, zIndex: 50 }}>
      <div style={{ position: "sticky", top: 0, background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div style={{ color: C.text, fontWeight: 800, fontSize: 14 }}>Kumbh 2027 Snan Calendar</div>
          <div style={{ color: C.textMuted, fontSize: 12 }}>17 Jul – 15 Sep 2027 · Nashik & Trimbakeshwar</div>
        </div>
        <span onClick={onClose} style={{ cursor: "pointer", color: C.textMuted, fontSize: 18, lineHeight: 1 }}>×</span>
      </div>
      {(upcoming.length ? upcoming : SNAN_EVENTS).map(e => {
        const d = daysUntil(e.date);
        return (
          <div key={e.date} style={{ display: "flex", gap: 12, padding: "12px 18px", borderBottom: `1px solid ${C.border}`, background: e.amrit ? C.primaryLight : C.white }}>
            <div style={{ textAlign: "center", minWidth: 46 }}>
              <div style={{ color: e.amrit ? C.primary : C.text, fontWeight: 800, fontSize: 17 }}>{snanDate(e.date).getDate()}</div>
              <div style={{ color: C.textMuted, fontSize: 11, textTransform: "uppercase" }}>{snanDate(e.date).toLocaleString("en-IN", { month: "short" })}</div>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ color: C.text, fontSize: 13, fontWeight: 700 }}>{e.name}{e.amrit && <span style={{ color: C.red, marginLeft: 6, fontSize: 11 }}>★ Amrit Snan</span>}</div>
              <div style={{ color: C.textSub, fontSize: 12, marginTop: 2 }}>{e.day} · {e.note}</div>
              <div style={{ color: C.textMuted, fontSize: 12 }}>{e.place}</div>
            </div>
            {d >= 0 && <div style={{ color: C.textMuted, fontSize: 11, whiteSpace: "nowrap" }}>{d === 0 ? "Today" : `in ${d}d`}</div>}
          </div>
        );
      })}
    </div>
  );
};

// ─── Dashboard ────────────────────────────────────────────────────
const Dashboard = ({ onNav }) => {
  const [stats, setStats] = useState({ total_bookings: 0, active_bookings: 0, total_revenue: 0, today_revenue: 0, total_users: 0 });
  const [revenue, setRevenue] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [calOpen, setCalOpen] = useState(false);
  const nextSnan = SNAN_EVENTS.find(e => daysUntil(e.date) >= 0);

  const load = async () => {
    try {
      const [s, r, b, u] = await Promise.all([
        apiGet("/admin/stats"),
        apiGet("/admin/revenue/weekly"),
        apiGet("/admin/bookings"),
        apiGet("/admin/users"),
      ]);
      if (s && s.total_bookings !== undefined) {
        // Fix total_users from auth service (booking service can't see users table)
        setStats({ ...s, total_users: u?.total || u?.users?.length || 0 });
      }
      if (r?.revenue) setRevenue(r.revenue);
      if (b?.bookings) setBookings(b.bookings.slice(0, 4));
    } catch(e) { console.error(e); }
    setLoading(false);
  };

  // eslint-disable-next-line
  useEffect(() => { load(); const t = setInterval(load, 30000); return () => clearInterval(t); }, []);

  const maxRev = revenue.length ? Math.max(...revenue.map(r => r.amount)) : 1;
  const tentData = [{ name: "Regular", pct: 37, color: C.green }, { name: "Luxury", pct: 39, color: C.primary }, { name: "Premium", pct: 24, color: C.purple }];
  if (loading) return <div style={{ color: C.textMuted, padding: 40, textAlign: "center" }}>Loading dashboard...</div>;
  return (
    <div>
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 22, fontWeight: 800 }}>Dashboard</div>
          <div style={{ color: C.textMuted, fontSize: 13, marginTop: 2 }}>{new Date().toDateString()}</div>
        </div>
        <div style={{ display: "flex", gap: 10, alignItems: "center", position: "relative" }}>
          <GlassButton onClick={() => setCalOpen(o => !o)} active={calOpen}>
            Snan Calendar {nextSnan && <>· {fmtSnan(nextSnan.date)}</>}
          </GlassButton>
          <GlassButton onClick={() => { setLoading(true); load(); }}>Refresh</GlassButton>
          {calOpen && <SnanCalendar onClose={() => setCalOpen(false)} />}
        </div>
      </div>
      {/* Kumbh 2027 Snan ticker */}
      <SnanBanner />
      {/* Stats Row */}
      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 22 }}>
        <StatCard icon="" label="Total Bookings" value={stats.total_bookings} sub={`${stats.active_bookings} currently active`} trend="12%" color={C.primary} />
        <StatCard icon="" label="Total Revenue" value={fmt(stats.total_revenue || 0)} sub={`${fmt(stats.today_revenue || 0)} today`} trend="8%" color={C.green} />
        <StatCard icon="" label="Total Users" value={stats.total_users || 0} sub="Registered users" trend="5%" color={C.purple} />
        <StatCard icon="" label="Active Bookings" value={stats.active_bookings || 0} sub="Confirmed & checked in" color={C.amber} />
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1.6fr 1fr", gap: 16, marginBottom: 16 }}>
        {/* Revenue Chart */}
        <TiltCard className="rounded-[20px]" max={6}>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 22, boxShadow: C.shadow }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
            <div>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 14 }}>Weekly Revenue</div>
              <div style={{ color: C.textMuted, fontSize: 12 }}>Last 7 days performance</div>
            </div>
            <div style={{ color: C.primary, fontSize: 12, fontWeight: 600 }}>{fmt(291000)} total</div>
          </div>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 10, height: 130 }}>
            {(revenue.length ? revenue : [{day:"Mon",amount:0},{day:"Tue",amount:0},{day:"Wed",amount:0},{day:"Thu",amount:0},{day:"Fri",amount:0},{day:"Sat",amount:0},{day:"Sun",amount:0}]).map((r, i) => (
              <div key={r.day} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 500 }}>{(r.amount / 1000).toFixed(0)}k</div>
                <div style={{ width: "100%", position: "relative" }}>
                  <div style={{ width: "100%", height: (r.amount / maxRev) * 100, background: i === 5 ? C.primary : C.primaryLight, borderRadius: "6px 6px 0 0", minHeight: 6, transition: "height 0.3s", border: i === 5 ? "none" : `1px solid ${C.primary}30` }} />
                </div>
                <div style={{ color: i === 5 ? C.primary : C.textMuted, fontSize: 11, fontWeight: i === 5 ? 700 : 400 }}>{r.day}</div>
              </div>
            ))}
          </div>
        </div>
        </TiltCard>

        {/* Tent split */}
        <TiltCard className="rounded-[20px]" max={6}>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 22, boxShadow: C.shadow }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 4 }}>Bookings by Tent</div>
          <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 20 }}>Distribution this month</div>
          {tentData.map(t => (
            <div key={t.name} style={{ marginBottom: 16 }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 6 }}>
                <div style={{ color: C.text, fontSize: 13, fontWeight: 600 }}>{t.name}</div>
                <div style={{ color: t.color, fontWeight: 700, fontSize: 13 }}>{t.pct}%</div>
              </div>
              <div style={{ background: C.bg, borderRadius: 6, height: 8, overflow: "hidden" }}>
                <div style={{ background: t.color, borderRadius: 6, height: 8, width: `${t.pct}%` }} />
              </div>
            </div>
          ))}
        </div>
        </TiltCard>
      </div>

      {/* Recent Bookings */}
      <TiltCard className="rounded-[20px]" max={4}>
      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "16px 22px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14 }}>Recent Bookings</div>
          <span onClick={() => onNav && onNav("bookings")} style={{ color: C.primary, fontSize: 12, fontWeight: 600, cursor: "pointer", background: C.primaryLight, padding: "4px 12px", borderRadius: 20 }}>View all →</span>
        </div>
        {bookings.length === 0 && <div style={{ color: C.textMuted, padding: "20px 22px", fontSize: 13 }}>No bookings yet</div>}
        {bookings.map((b, i) => (
          <div key={b.booking_ref} style={{ display: "flex", alignItems: "center", gap: 12, padding: "13px 22px", borderBottom: i < bookings.length - 1 ? `1px solid ${C.border}` : "none" }}>
            <Avatar name={b.guest_name || b.phone || "Guest"} size={36} />
            <div style={{ flex: 1 }}>
              <div style={{ color: C.text, fontSize: 13, fontWeight: 600 }}>{b.guest_name || b.phone}</div>
              <div style={{ color: C.textMuted, fontSize: 12 }}>{b.tent_name} · {b.check_in} → {b.check_out}</div>
            </div>
            <div style={{ textAlign: "right" }}>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 13 }}>{fmt(b.total_amount || 0)}</div>
              <Badge status={b.status} />
            </div>
          </div>
        ))}
      </div>
      </TiltCard>
    </div>
  );
};

// ─── Tents ────────────────────────────────────────────────────────
const Tents = () => {
  const [tents, setTents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(false);
  const [editModal, setEditModal] = useState(false);
  const [editTent, setEditTent] = useState(null);
  const [form, setForm] = useState({ name: "", class: "standard", price: "", units: "" });
  const classColors = { standard: C.green, luxury: C.primary, premium: C.purple };

  const loadTents = () => {
    apiGet("/admin/tents").then(d => {
      if (d?.tents) setTents(d.tents);
      setLoading(false);
    }).catch(() => setLoading(false));
  };
  useEffect(() => { loadTents(); }, []);

  const openEdit = (t) => { setEditTent({ ...t }); setEditModal(true); };

  const saveEdit = async () => {
    if (!editTent.name || !editTent.price) return;
    const isActive = editTent.is_active;
    await fetch(`${API_BASE}/admin/tents/${editTent.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
      body: JSON.stringify({ name: editTent.name, price: +editTent.price, total_units: +editTent.total_units, class: editTent.class, is_active: isActive }),
    });
    setEditModal(false); setEditTent(null); loadTents();
  };

  // eslint-disable-next-line
  const toggleActive = async (t) => {
    await fetch(`${API_BASE}/admin/tents/${t.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
      body: JSON.stringify({ is_active: !t.is_active }),
    });
    loadTents();
  };

  // eslint-disable-next-line
  const deleteTent = async (id) => {
    await fetch(`${API_BASE}/admin/tents/${id}`, {
      method: "DELETE",
      headers: { "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
    });
    loadTents();
  };

  const save = async () => {
    if (!form.name || !form.price) return;
    await fetch(`${API_BASE}/admin/tents`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
      body: JSON.stringify({ name: form.name, class: form.class, price: +form.price, total_units: +form.units || 33 }),
    });
    setModal(false); setForm({ name: "", class: "standard", price: "", units: "" }); loadTents();
  };
  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 18, fontWeight: 800 }}>Tent Management</div>
          <div style={{ color: C.textSub, fontSize: 13 }}>{tents.length} tent types configured</div>
        </div>
        <BtnPrimary onClick={() => setModal(true)}>+ Add Tent</BtnPrimary>
      </div>
      {loading && <div style={{ color: C.textMuted, padding: 40, textAlign: "center" }}>Loading tents...</div>}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(300px, 1fr))", gap: 16 }}>
        {tents.map(t => {
          const cc = classColors[t.class] || C.primary;
          return (
            <div key={t.id} style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, overflow: "hidden", boxShadow: C.shadow }}>
              {/* Header band */}
              <div style={{ height: 6, background: cc }} />
              <div style={{ padding: 20 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 14 }}>
                  <div>
                    <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>{t.name}</div>
                    <span style={{ background: cc + "15", color: cc, padding: "2px 8px", borderRadius: 24, fontSize: 11, fontWeight: 700 }}>{t.class.toUpperCase()}</span>
                  </div>
                  <Badge status={t.active ? "active" : "inactive"} />
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 16 }}>
                  {[["Price/Night", fmt(t.price)], ["Units", t.units], ["Rating", `${t.rating}`], ["Bookings", t.bookings]].map(([l, v]) => (
                    <div key={l} style={{ background: C.bg, borderRadius: 8, padding: "8px 12px" }}>
                      <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 600, textTransform: "uppercase" }}>{l}</div>
                      <div style={{ color: C.text, fontSize: 14, fontWeight: 700, marginTop: 2 }}>{v}</div>
                    </div>
                  ))}
                </div>
                <div style={{ display: "flex", gap: 8 }}>
                  <RowAction onClick={() => openEdit(t)} tone="primary" style={{ flex: 1 }}>Edit</RowAction>
                  <RowAction onClick={() => setTents(tents.map(x => x.id === t.id ? { ...x, active: !x.active } : x))} tone={t.active ? "red" : "green"} style={{ flex: 1 }}>
                    {t.active ? "Deactivate" : "Activate"}
                  </RowAction>
                  <RowAction onClick={() => setTents(tents.filter(x => x.id !== t.id))} tone="neutral" style={{ flex: 1 }}>Delete</RowAction>
                </div>
              </div>
            </div>
          );
        })}
      </div>
      {editModal && editTent && (
        <Modal title={`Edit — ${editTent.name}`} onClose={() => setEditModal(false)}>
          <div style={{ background: C.amberLight, border: `1px solid ${C.amber}33`, borderRadius: 8, padding: "10px 13px", marginBottom: 16, fontSize: 12, color: C.amber, fontWeight: 600 }}>
            Changing price will apply to new bookings only
          </div>
          <FormField label="Tent Name">
            <input style={inpStyle} value={editTent.name||""} onChange={e => setEditTent({ ...editTent, name: e.target.value })} />
          </FormField>
          <FormField label="Class">
            <select style={inpStyle} value={editTent.class||"standard"} onChange={e => setEditTent({ ...editTent, class: e.target.value })}>
              <option value="standard">Standard</option><option value="luxury">Luxury</option><option value="premium">Premium</option>
            </select>
          </FormField>
          <FormField label="Price per Night (₹)">
            <input style={inpStyle} type="number" value={editTent.price||""} onChange={e => setEditTent({ ...editTent, price: e.target.value })} />
          </FormField>
          <FormField label="Total Units">
            <input style={inpStyle} type="number" value={editTent.total_units||""} onChange={e => setEditTent({ ...editTent, total_units: e.target.value })} />
          </FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setEditModal(false)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={saveEdit} style={{ flex: 1 }}>Save Changes</BtnPrimary>
          </div>
        </Modal>
      )}
      {modal && (
        <Modal title="Add New Tent" onClose={() => setModal(false)}>
          <FormField label="Tent Name"><input style={inpStyle} placeholder="e.g. Deluxe Capsule Tent" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></FormField>
          <FormField label="Class">
            <select style={inpStyle} value={form.class} onChange={e => setForm({ ...form, class: e.target.value })}>
              <option value="standard">Standard</option><option value="luxury">Luxury</option><option value="premium">Premium</option>
            </select>
          </FormField>
          <FormField label="Price per Night (₹)"><input style={inpStyle} type="number" placeholder="e.g. 3500" value={form.price} onChange={e => setForm({ ...form, price: e.target.value })} /></FormField>
          <FormField label="Total Units"><input style={inpStyle} type="number" placeholder="e.g. 33" value={form.units} onChange={e => setForm({ ...form, units: e.target.value })} /></FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setModal(false)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={save} style={{ flex: 1 }}>Save Tent</BtnPrimary>
          </div>
        </Modal>
      )}
    </div>
  );
};

// ─── Bookings ─────────────────────────────────────────────────────
const Bookings = () => {
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [clearing, setClearing] = useState(false);
  const [clearMsg, setClearMsg] = useState(null);
  const [acctRef, setAcctRef] = useState(null);
  const [acct, setAcct] = useState(null);
  const [acctLoading, setAcctLoading] = useState(false);
  const [acctLog, setAcctLog] = useState([]);
  const statuses = ["all", "confirmed", "pending", "checked_in", "completed", "cancelled"];

  const openAccounting = async (ref) => {
    setAcctRef(ref);
    setAcct(null);
    setAcctLog([]);
    setAcctLoading(true);
    apiGet(`/admin/finance/bookings/${ref}/audit-log`).then(d => setAcctLog(d?.audit_log || [])).catch(() => {});
    try {
      const d = await apiGet(`/admin/finance/bookings/${ref}/accounting`);
      setAcct(d);
    } catch (e) { /* leave acct null — modal shows an error state */ }
    setAcctLoading(false);
  };

  useEffect(() => {
    apiGet("/admin/bookings").then(d => {
      if (d?.bookings) setBookings(d.bookings);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, []);

  const updateStatus = async (ref, status) => {
    await apiPut(`/admin/bookings/${ref}/status`, { status });
    setBookings(bookings.map(b => b.booking_ref === ref ? { ...b, status } : b));
  };

  const clearCancelled = async () => {
    setClearing(true);
    try {
      const res = await fetch(`${API_BASE}/admin/bookings/cancelled`, {
        method: "DELETE",
        headers: { "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
      });
      const data = await res.json();
      setClearMsg(data.message || "Done");
      setBookings(prev => prev.filter(b => b.status !== "cancelled"));
      setTimeout(() => setClearMsg(null), 3000);
    } catch(e) { setClearMsg("Failed"); }
    setClearing(false);
  };

  const clearAllCancelled = async () => {
    if (!window.confirm("Delete ALL cancelled bookings? This cannot be undone!")) return;
    setClearing(true);
    try {
      const res = await fetch(`${API_BASE}/admin/bookings/cancelled/all`, {
        method: "DELETE",
        headers: { "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
      });
      const data = await res.json();
      setClearMsg(data.message || "Done");
      setBookings(prev => prev.filter(b => b.status !== "cancelled"));
      setTimeout(() => setClearMsg(null), 3000);
    } catch(e) { setClearMsg("Failed"); }
    setClearing(false);
  };

  const filtered = bookings.filter(b => (filter === "all" || b.status === filter) &&
    ((b.guest_name || "").toLowerCase().includes(search.toLowerCase()) ||
     (b.phone || "").includes(search) ||
     (b.booking_ref || "").includes(search)));
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 16px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "13px 16px", borderBottom: `1px solid ${C.border}` };
  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div style={{ color: C.text, fontSize: 18, fontWeight: 800 }}>Bookings</div>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          {clearMsg && <span style={{ color: C.green, fontSize: 13, fontWeight: 600 }}>{clearMsg}</span>}
          <LiquidMetalButton label={clearing ? "Clearing..." : "Clear Old Cancelled (30d+)"} onClick={clearCancelled} disabled={clearing} tone="amber" active size="sm" />
          <LiquidMetalButton label={clearing ? "Clearing..." : "Clear All Cancelled"} onClick={clearAllCancelled} disabled={clearing} tone="red" active size="sm" />
        </div>
      </div>
      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "16px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder=" Search guest name or booking ID..." style={{ ...inpStyle, flex: 1, minWidth: 200 }} />
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {statuses.map(s => (
              <Chip key={s} active={filter === s} onClick={() => setFilter(s)}>{s === "all" ? "All" : s.replace("_", " ")}</Chip>
            ))}
          </div>
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>{["Booking ID", "Guest", "Tent", "Check-in", "Check-out", "Amount", "Status", "Actions"].map(h => <th key={h} style={thS}>{h}</th>)}</tr>
            </thead>
            <tbody>
              {loading && <tr><td colSpan={8} style={{ textAlign: "center", padding: 40, color: C.textMuted }}>Loading bookings...</td></tr>}
              {!loading && filtered.map(b => (
                <tr key={b.booking_ref} onMouseEnter={e => e.currentTarget.style.background = C.bg} onMouseLeave={e => e.currentTarget.style.background = "transparent"} style={{ transition: "background 0.1s" }}>
                  <td style={{ ...tdS, color: C.primary, fontWeight: 700, fontFamily: "monospace", fontSize: 12 }}>{b.booking_ref}</td>
                  <td style={tdS}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <Avatar name={b.guest_name || b.phone || "G"} size={28} />
                      <div>
                        <div style={{ fontWeight: 600 }}>{b.guest_name || "—"}</div>
                        <div style={{ color: C.textMuted, fontSize: 11 }}>{b.phone}</div>
                      </div>
                    </div>
                  </td>
                  <td style={{ ...tdS, color: C.textSub }}>{b.tent_name}</td>
                  <td style={{ ...tdS, color: C.textSub }}>{b.check_in}</td>
                  <td style={{ ...tdS, color: C.textSub }}>{b.check_out}</td>
                  <td style={{ ...tdS, fontWeight: 700 }}>{fmt(b.total_amount || 0)}</td>
                  <td style={tdS}><Badge status={b.status} /></td>
                  <td style={tdS}>
                    <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                      {b.status === "pending" && <RowAction onClick={() => updateStatus(b.booking_ref, "confirmed")} tone="green">Confirm</RowAction>}
                      {b.status === "confirmed" && <RowAction onClick={() => updateStatus(b.booking_ref, "checked_in")} tone="primary">Check In</RowAction>}
                      {b.status === "checked_in" && <RowAction onClick={() => updateStatus(b.booking_ref, "completed")} tone="purple">Complete</RowAction>}
                      {!["cancelled","completed"].includes(b.status) && <RowAction onClick={() => updateStatus(b.booking_ref, "cancelled")} tone="red">Cancel</RowAction>}
                      <RowAction onClick={() => openAccounting(b.booking_ref)} tone="purple">Accounting</RowAction>
                    </div>
                  </td>
                </tr>
              ))}
              {!loading && filtered.length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 40, color: C.textMuted }}>No bookings found</td></tr>}
            </tbody>
          </table>
        </div>
      </div>

      {acctRef && (
        <Modal title={`Accounting — ${acctRef}`} onClose={() => setAcctRef(null)}>
          {acctLoading && <div style={{ color: C.textMuted, padding: 20, textAlign: "center" }}>Loading...</div>}
          {!acctLoading && !acct && <div style={{ color: C.red, padding: 20, textAlign: "center" }}>Could not load accounting details.</div>}
          {!acctLoading && acct && (
            <div>
              {[
                ["Customer", acct.customer],
                ["Country", acct.country],
                ["Tent", acct.tent_name],
                ["Booking Value", fmt(acct.booking_value)],
                ["Paid", fmt(acct.paid)],
                ["Outstanding", fmt(acct.outstanding)],
                ["Payment Status", acct.payment_status],
                ["Refund", acct.refund_amount > 0 ? `${fmt(acct.refund_amount)} (${acct.refund_status})` : "—"],
                ...(acct.refund_approval_reason || acct.refund_rejection_reason
                  ? [["Refund Reason", acct.refund_approval_reason || acct.refund_rejection_reason]]
                  : []),
                ...(acct.refund_reviewed_by ? [["Reviewed By", acct.refund_reviewed_by]] : []),
                ["Gateway Charges", "— (Phase 4)"],
              ].map(([label, value]) => (
                <div key={label} style={{ display: "flex", justifyContent: "space-between", padding: "9px 0", borderBottom: `1px solid ${C.border}` }}>
                  <div style={{ color: C.textMuted, fontSize: 12 }}>{label}</div>
                  <div style={{ color: C.text, fontSize: 13, fontWeight: 700 }}>{value}</div>
                </div>
              ))}

              {acctLog.length > 0 && (
                <div style={{ marginTop: 16 }}>
                  <div style={{ color: C.textSub, fontSize: 11, fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.5, marginBottom: 8 }}>Audit Trail</div>
                  <div style={{ maxHeight: 180, overflowY: "auto" }}>
                    {acctLog.map((e, i) => (
                      <div key={i} style={{ fontSize: 11, padding: "6px 0", borderBottom: i < acctLog.length - 1 ? `1px solid ${C.border}` : "none" }}>
                        <div style={{ display: "flex", justifyContent: "space-between" }}>
                          <span style={{ fontWeight: 700, color: C.text }}>{e.event}</span>
                          <span style={{ color: C.textMuted }}>{e.created_at}</span>
                        </div>
                        <div style={{ color: C.textMuted }}>
                          {e.triggered_by}{e.amount > 0 ? ` · ${fmt(e.amount)}` : ""}{e.note ? ` · ${e.note}` : ""}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <BtnSecondary onClick={() => setAcctRef(null)} style={{ width: "100%", marginTop: 16 }}>Close</BtnSecondary>
            </div>
          )}
        </Modal>
      )}
    </div>
  );
};


// ─── Users ────────────────────────────────────────────────────────
const Users = () => {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiGet("/admin/users").then(d => {
      if (d?.users) setUsers(d.users);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, []);

  const toggleBlock = async (phone, currentStatus) => {
    const action = currentStatus === "active" ? "block" : "unblock";
    await apiPut(`/admin/users/${encodeURIComponent(phone)}/block`, { action });
    setUsers(users.map(u => u.phone === phone ? { ...u, status: action === "block" ? "blocked" : "active" } : u));
  };
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 16px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "13px 16px", borderBottom: `1px solid ${C.border}` };
  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 18, fontWeight: 800 }}>Users</div>
          <div style={{ color: C.textSub, fontSize: 13 }}>{users.length} registered users</div>
        </div>
      </div>
      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead><tr>{["User", "Phone", "Bookings", "Total Spent", "Joined", "Status", "Actions"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
          <tbody>
            {loading && <tr><td colSpan={7} style={{ textAlign: "center", padding: 40, color: C.textMuted }}>Loading users...</td></tr>}
            {!loading && users.map((u, i) => (
              <tr key={u.phone} onMouseEnter={e => e.currentTarget.style.background = C.bg} onMouseLeave={e => e.currentTarget.style.background = "transparent"} style={{ transition: "background 0.1s" }}>
                <td style={tdS}>
                  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <Avatar name={u.name || u.phone || "U"} size={32} />
                    <div><div style={{ fontWeight: 700 }}>{u.name || "—"}</div><div style={{ color: C.textMuted, fontSize: 11 }}>{u.email || "No email"}</div></div>
                  </div>
                </td>
                <td style={{ ...tdS, color: C.textSub, fontFamily: "monospace", fontSize: 12 }}>{u.phone}</td>
                <td style={{ ...tdS, fontWeight: 600 }}>{u.booking_count}</td>
                <td style={{ ...tdS, fontWeight: 700, color: C.green }}>{fmt(u.total_spent || 0)}</td>
                <td style={{ ...tdS, color: C.textSub }}>{u.created_at ? new Date(u.created_at).toLocaleDateString("en-IN") : "—"}</td>
                <td style={tdS}><Badge status={u.status || "active"} /></td>
                <td style={tdS}>
                  <RowAction onClick={() => toggleBlock(u.phone, u.status)} tone={u.status === "active" ? "red" : "green"}>
                    {u.status === "active" ? "Block" : "Unblock"}
                  </RowAction>
                </td>
              </tr>
            ))}
            {!loading && users.length === 0 && <tr><td colSpan={7} style={{ textAlign: "center", padding: 40, color: C.textMuted }}>No users found</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  );
};

// ─── Coupons ──────────────────────────────────────────────────────
const Coupons = () => {
  const [coupons, setCoupons] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(false);
  const [form, setForm] = useState({ code: "", discount: "", type: "percent", limit: "", expiry: "" });

  const loadCoupons = () => {
    apiGet("/admin/coupons").then(d => {
      if (d?.coupons) setCoupons(d.coupons);
      setLoading(false);
    }).catch(() => setLoading(false));
  };
  useEffect(() => { loadCoupons(); }, []);

  const toggleCoupon = async (id) => {
    await fetch(`${API_BASE}/admin/coupons/${id}/toggle`, {
      method: "PUT", headers: { "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
    });
    loadCoupons();
  };

  const deleteCoupon = async (id) => {
    await fetch(`${API_BASE}/admin/coupons/${id}`, {
      method: "DELETE", headers: { "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
    });
    loadCoupons();
  };

  const save = async () => {
    if (!form.code || !form.discount) return;
    const discount = form.type === "percent" ? +form.discount / 100 : +form.discount;
    await fetch(`${API_BASE}/admin/coupons`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
      body: JSON.stringify({ code: form.code, discount, max_uses: +form.limit || 100, expires_at: form.expiry }),
    });
    setModal(false); setForm({ code: "", discount: "", type: "percent", limit: "", expiry: "" }); loadCoupons();
  };
  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 18, fontWeight: 800 }}>Coupons</div>
          <div style={{ color: C.textSub, fontSize: 13 }}>{coupons.length} coupon codes</div>
        </div>
        <BtnPrimary onClick={() => setModal(true)}>+ Create Coupon</BtnPrimary>
      </div>
      {loading && <div style={{ color: C.textMuted, padding: 40, textAlign: "center" }}>Loading coupons...</div>}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(290px, 1fr))", gap: 14 }}>
        {coupons.map(c => (
          <div key={c.id} style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, overflow: "hidden", boxShadow: C.shadow }}>
            <div style={{ padding: "18px 20px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div style={{ background: C.primaryLight, color: C.primary, padding: "5px 12px", borderRadius: 8, fontFamily: "monospace", fontWeight: 800, fontSize: 14, letterSpacing: 1 }}>{c.code}</div>
              <Badge status={c.is_active ? "active" : "inactive"} />
            </div>
            <div style={{ padding: "16px 20px" }}>
              <div style={{ color: C.text, fontSize: 26, fontWeight: 800, marginBottom: 12 }}>
                {c.discount < 1 ? `${Math.round(c.discount * 100)}% OFF` : `${fmt(c.discount)} OFF`}
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", color: C.textSub, fontSize: 12, marginBottom: 8 }}>
                <span>Used: <b style={{ color: C.text }}>{c.used_count}/{c.max_uses}</b></span>
                <span>Expires: <b style={{ color: C.text }}>{c.expires_at ? new Date(c.expires_at).toLocaleDateString("en-IN") : "—"}</b></span>
              </div>
              <div style={{ background: C.bg, borderRadius: 99, height: 6, overflow: "hidden", marginBottom: 14 }}>
                <div style={{ background: c.used_count / c.max_uses > 0.8 ? C.red : C.primary, height: 6, width: `${Math.min((c.used_count / c.max_uses) * 100, 100)}%`, borderRadius: 99 }} />
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <RowAction onClick={() => toggleCoupon(c.id)} tone={c.is_active ? "red" : "green"} style={{ flex: 1 }}>
                  {c.is_active ? "Deactivate" : "Activate"}
                </RowAction>
                <RowAction onClick={() => deleteCoupon(c.id)} tone="neutral" style={{ flex: 1 }}>Delete</RowAction>
              </div>
            </div>
          </div>
        ))}
      </div>
      {modal && (
        <Modal title="Create Coupon" onClose={() => setModal(false)}>
          <FormField label="Coupon Code"><input style={inpStyle} placeholder="e.g. KUMBH30" value={form.code} onChange={e => setForm({ ...form, code: e.target.value.toUpperCase() })} /></FormField>
          <FormField label="Discount Type">
            <select style={inpStyle} value={form.type} onChange={e => setForm({ ...form, type: e.target.value })}>
              <option value="percent">Percentage (%)</option><option value="flat">Flat Amount (₹)</option>
            </select>
          </FormField>
          <FormField label={`Discount Value (${form.type === "percent" ? "%" : "₹"})`}><input style={inpStyle} type="number" placeholder={form.type === "percent" ? "e.g. 20" : "e.g. 500"} value={form.discount} onChange={e => setForm({ ...form, discount: e.target.value })} /></FormField>
          <FormField label="Usage Limit"><input style={inpStyle} type="number" placeholder="e.g. 100" value={form.limit} onChange={e => setForm({ ...form, limit: e.target.value })} /></FormField>
          <FormField label="Expiry Date"><input style={inpStyle} type="date" value={form.expiry} onChange={e => setForm({ ...form, expiry: e.target.value })} /></FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setModal(false)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={save} style={{ flex: 1 }}>Create Coupon</BtnPrimary>
          </div>
        </Modal>
      )}
    </div>
  );
};

// ─── Finance & Accounting (Phase 1) ────────────────────────────────
//
// Foundation: real-time totals from bookings/payments/refunds, and
// a per-booking accounting drill-down. Operating Expenses and
// Payment Gateway Charges aren't tracked anywhere in the backend
// yet (Phase 3/4 of the finance module) — those two cards show a
// "not yet tracked" note instead of a fabricated number.
// Small horizontal-bar mini-chart shared by the rollup dashboard's
// below-the-fold section — no charting library, just divs.
const MiniBarChart = ({ title, sub, rows, colorFor }) => {
  const max = rows.length ? Math.max(...rows.map(r => r.value), 1) : 1;
  return (
    <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 20, boxShadow: C.shadow }}>
      <div style={{ color: C.text, fontWeight: 700, fontSize: 14 }}>{title}</div>
      {sub && <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 14 }}>{sub}</div>}
      {rows.length === 0 && <div style={{ color: C.textMuted, fontSize: 12, padding: "16px 0" }}>No data yet</div>}
      {rows.map((r, i) => (
        <div key={r.label} style={{ marginBottom: 12 }}>
          <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
            <div style={{ color: C.textSub, fontSize: 12, fontWeight: 600 }}>{r.label}</div>
            <div style={{ color: C.text, fontSize: 12, fontWeight: 700 }}>{r.display || fmt(r.value)}</div>
          </div>
          <div style={{ background: C.bg, borderRadius: 6, height: 8, overflow: "hidden" }}>
            <div style={{ background: colorFor ? colorFor(r, i) : C.primary, borderRadius: 6, height: 8, width: `${Math.max(2, (r.value / max) * 100)}%` }} />
          </div>
        </div>
      ))}
    </div>
  );
};

const Finance = () => {
  const [stats, setStats] = useState(null);
  const [revenue, setRevenue] = useState([]);
  const [expenseByCategory, setExpenseByCategory] = useState([]);
  const [paymentStatus, setPaymentStatus] = useState([]);
  const [currencyRevenue, setCurrencyRevenue] = useState([]);
  const [gatewayRows, setGatewayRows] = useState([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    try {
      const [dash, rev, exp, pay, fx, gw] = await Promise.all([
        apiGet("/admin/finance/dashboard"),
        apiGet("/admin/revenue/weekly"),
        apiGet("/admin/expenses"),
        apiGet("/admin/payments"),
        apiGet("/admin/finance/fx-report"),
        apiGet("/admin/gateway-summary"),
      ]);
      if (dash) setStats(dash);
      if (rev?.revenue) setRevenue(rev.revenue);

      const byCat = {};
      (exp?.expenses || []).forEach(e => { byCat[e.category] = (byCat[e.category] || 0) + e.amount + e.tax; });
      setExpenseByCategory(Object.entries(byCat).map(([label, value]) => ({ label, value })).sort((a, b) => b.value - a.value));

      const counts = pay?.status_counts || {};
      setPaymentStatus(Object.entries(counts).filter(([, v]) => v > 0).map(([label, v]) => ({ label, value: v, display: String(v) })));

      const foreignByCcy = {};
      (fx?.bookings || []).forEach(r => {
        foreignByCcy[r.currency] = (foreignByCcy[r.currency] || 0) + (r.inr_value_at_booking || 0);
      });
      const foreignTotal = Object.values(foreignByCcy).reduce((a, b) => a + b, 0);
      const inrTotal = Math.max(0, (dash?.gross_booking_value || 0) - foreignTotal);
      const ccyRows = [{ label: "INR", value: inrTotal }, ...Object.entries(foreignByCcy).map(([label, value]) => ({ label, value }))];
      setCurrencyRevenue(ccyRows.filter(r => r.value > 0));

      setGatewayRows((gw?.providers || []).map(p => ({ label: p.gateway || p.payment_mode, value: p.gross_collection || p.GrossCollection || 0, display: `${fmt(p.gross_collection || 0)} · fee ${fmt(p.gateway_fee || 0)}` })));
    } catch (e) { console.error(e); }
    setLoading(false);
  };
  // eslint-disable-next-line
  useEffect(() => { load(); const t = setInterval(load, 30000); return () => clearInterval(t); }, []);

  if (loading || !stats) return <div style={{ color: C.textMuted, padding: 40, textAlign: "center" }}>Loading finance dashboard...</div>;

  const maxRev = revenue.length ? Math.max(...revenue.map(r => r.amount), 1) : 1;

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 22, fontWeight: 800 }}>Finance & Accounting</div>
          <div style={{ color: C.textMuted, fontSize: 13, marginTop: 2 }}>Booking → Revenue → Payment → Outstanding → Refund → Expenses → Gateway → P&L</div>
        </div>
        <GlassButton onClick={() => { setLoading(true); load(); }}>Refresh</GlassButton>
      </div>

      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 14 }}>
        <StatCard icon="" label="Total Booking Revenue" value={fmt(stats.gross_booking_value)} color={C.primary} />
        <StatCard icon="" label="Amount Received" value={fmt(stats.amount_received)} color={C.green} />
        <StatCard icon="" label="Outstanding" value={fmt(stats.outstanding)} color={C.amber} />
        <StatCard icon="" label="Refunds" value={fmt(stats.refunds)} color={C.red} />
      </div>
      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 22 }}>
        <StatCard icon="" label="Total Expenses" value={fmt(stats.operating_expenses)} color={C.textSub} />
        <StatCard icon="" label="Gateway Charges" value={fmt(stats.gateway_charges)} color={C.textSub} />
        <StatCard icon="" label="Net Revenue" value={fmt(stats.net_revenue)} color={C.purple} />
        <StatCard icon="" label="Operating Profit" value={fmt(stats.operating_profit)} color={stats.operating_profit >= 0 ? C.green : C.red} />
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 20, boxShadow: C.shadow }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 2 }}>Revenue — last 7 days</div>
          <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 16 }}>Confirmed booking value collected per day</div>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 10, height: 110 }}>
            {(revenue.length ? revenue : [{ day: "Mon", amount: 0 }, { day: "Tue", amount: 0 }, { day: "Wed", amount: 0 }, { day: "Thu", amount: 0 }, { day: "Fri", amount: 0 }, { day: "Sat", amount: 0 }, { day: "Sun", amount: 0 }]).map(r => (
              <div key={r.day} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                <div style={{ color: C.textMuted, fontSize: 10 }}>{(r.amount / 1000).toFixed(1)}k</div>
                <div style={{ width: "100%", height: (r.amount / maxRev) * 80, background: C.primaryLight, borderRadius: "6px 6px 0 0", minHeight: 4, border: `1px solid ${C.primary}30` }} />
                <div style={{ color: C.textMuted, fontSize: 11 }}>{r.day}</div>
              </div>
            ))}
          </div>
        </div>

        <MiniBarChart title="Expenses by category" sub="Operating expense split, net of reversals" rows={expenseByCategory} colorFor={() => C.amber} />
        <MiniBarChart title="Payment status mix" sub="Bookings by current payment status" rows={paymentStatus} colorFor={(r) => STATUS_COLORS[r.label] || C.primary} />
        <MiniBarChart title="Currency-wise revenue" sub="Booking value in ₹, foreign bookings at locked rate" rows={currencyRevenue} colorFor={() => C.purple} />
        <MiniBarChart title="Gateway reconciliation" sub="Gross collection per gateway/mode, net of fees" rows={gatewayRows} colorFor={() => C.green} />
      </div>
    </div>
  );
};

// ─── Customer Payment Tracking (Phase 2) ───────────────────────────
//
// Per-booking payment status (Paid / Partial / Pending / Refunded /
// Cancelled) and a way to record a manual payment — including a
// PARTIAL amount, which is what makes "Partial" reachable at all
// today (the Razorpay checkout only ever collects the full amount
// in one shot; cash/UPI/bank-transfer collected at the tent can be
// partial).
const STATUS_COLORS = {
  Paid: C.green, Partial: C.amber, Pending: C.textMuted, Refunded: C.purple, Cancelled: C.red,
};

const PaymentTracking = () => {
  const [data, setData] = useState({ payments: [], total_received: 0, total_pending: 0, total_refunded: 0, status_counts: {} });
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("all");
  const [recordFor, setRecordFor] = useState(null); // booking_ref
  const [form, setForm] = useState({ amount: "", payment_mode: "cash", transaction_id: "", note: "" });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState(null);

  const load = () => {
    setLoading(true);
    apiGet("/admin/payments").then(d => { setData(d || {}); setLoading(false); }).catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const admin = localStorage.getItem("admin_username") || "admin";

  const openRecord = (ref) => {
    setRecordFor(ref);
    setForm({ amount: "", payment_mode: "cash", transaction_id: "", note: "" });
    setErr(null);
  };

  const submitPayment = async () => {
    if (saving) return; // guard against double-submit — BtnPrimary doesn't forward `disabled`
    const amount = parseFloat(form.amount);
    if (!amount || amount <= 0) { setErr("Enter a valid amount"); return; }
    setSaving(true); setErr(null);
    const { ok, data: res } = await apiPost(`/admin/bookings/${recordFor}/payments`, {
      amount, payment_mode: form.payment_mode, transaction_id: form.transaction_id,
      note: form.note, recorded_by: admin,
    });
    setSaving(false);
    if (!ok) { setErr(res.error || "Failed to record payment"); return; }
    setRecordFor(null);
    load();
  };

  const rows = data.payments || [];
  const filtered = filter === "all" ? rows : rows.filter(r => r.status === filter);
  const FILTERS = ["all", "Pending", "Partial", "Paid", "Refunded", "Cancelled"];
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 20 }}>Customer Payment Tracking</div>
      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 20 }}>
        <StatCard icon="" label="Total Received" value={fmt(data.total_received || 0)} color={C.green} />
        <StatCard icon="" label="Total Pending" value={fmt(data.total_pending || 0)} color={C.amber} />
        <StatCard icon="" label="Total Refunded" value={fmt(data.total_refunded || 0)} color={C.purple} />
        <StatCard icon="" label="Partial Payments" value={data.status_counts?.Partial || 0} color={C.amber} />
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", gap: 6, flexWrap: "wrap" }}>
          {FILTERS.map(s => (
            <Chip key={s} active={filter === s} onClick={() => setFilter(s)}>{s === "all" ? "All" : s}</Chip>
          ))}
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>{["Booking", "Customer", "Tent", "Total Value", "Received", "Pending", "Refunded", "Status", "Action"].map(h => <th key={h} style={thS}>{h}</th>)}</tr>
            </thead>
            <tbody>
              {loading && <tr><td colSpan={9} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && filtered.length === 0 && <tr><td colSpan={9} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>No bookings found</td></tr>}
              {!loading && filtered.map(r => (
                <tr key={r.booking_ref}>
                  <td style={{ ...tdS, color: C.primary, fontWeight: 700, fontFamily: "monospace", fontSize: 12 }}>{r.booking_ref}</td>
                  <td style={tdS}>{r.customer}</td>
                  <td style={{ ...tdS, color: C.textSub }}>{r.tent_name}</td>
                  <td style={tdS}>{fmt(r.total_value)}</td>
                  <td style={{ ...tdS, color: C.green }}>{fmt(r.received)}</td>
                  <td style={{ ...tdS, color: r.pending > 0 ? C.amber : C.textMuted }}>{fmt(r.pending)}</td>
                  <td style={{ ...tdS, color: C.purple }}>{r.refund_processed > 0 ? fmt(r.refund_processed) : "—"}</td>
                  <td style={tdS}>
                    <span style={{ background: (STATUS_COLORS[r.status] || C.textMuted) + "18", color: STATUS_COLORS[r.status] || C.textMuted, padding: "3px 10px", borderRadius: 24, fontSize: 11, fontWeight: 700 }}>{r.status}</span>
                  </td>
                  <td style={tdS}>
                    {["Pending", "Partial"].includes(r.status) && (
                      <RowAction onClick={() => openRecord(r.booking_ref)} tone="green">+ Record Payment</RowAction>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {recordFor && (
        <Modal title={`Record Payment — ${recordFor}`} onClose={() => setRecordFor(null)}>
          {err && <div style={{ background: C.redLight, color: C.red, padding: "8px 12px", borderRadius: 8, fontSize: 12, marginBottom: 14 }}>{err}</div>}
          <FormField label="Amount (₹)">
            <input type="number" style={inpStyle} value={form.amount} onChange={e => setForm({ ...form, amount: e.target.value })} placeholder="e.g. 5000" />
          </FormField>
          <FormField label="Payment Mode">
            <select style={inpStyle} value={form.payment_mode} onChange={e => setForm({ ...form, payment_mode: e.target.value })}>
              <option value="cash">Cash</option>
              <option value="upi">UPI</option>
              <option value="card">Card</option>
              <option value="bank_transfer">Bank Transfer</option>
              <option value="other">Other</option>
            </select>
          </FormField>
          <FormField label="Transaction ID (optional)">
            <input style={inpStyle} value={form.transaction_id} onChange={e => setForm({ ...form, transaction_id: e.target.value })} placeholder="UTR / reference no." />
          </FormField>
          <FormField label="Note (optional)">
            <input style={inpStyle} value={form.note} onChange={e => setForm({ ...form, note: e.target.value })} placeholder="e.g. partial deposit at tent" />
          </FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setRecordFor(null)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={submitPayment} style={{ flex: 1 }} disabled={saving}>{saving ? "Saving..." : "Record Payment"}</BtnPrimary>
          </div>
        </Modal>
      )}
    </div>
  );
};

// ─── Operating Expenses (Phase 3) ───────────────────────────────────
//
// No edit action anywhere here on purpose — a mistaken entry is
// corrected with "Reverse", which posts a negative-amount row
// referencing the original rather than changing it. That's the
// same "never edit, only reverse" rule the refund workflow uses.
const EXPENSE_CATEGORIES = [
  "Tent Maintenance", "Transportation", "Staff Salary", "Cleaning", "Electricity",
  "Marketing", "Rent", "Insurance", "Equipment", "Repair", "Other",
];

const Expenses = () => {
  const [data, setData] = useState({ expenses: [], net_total: 0, total: 0 });
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(false);
  const [form, setForm] = useState({ expense_date: new Date().toISOString().slice(0, 10), category: "Tent Maintenance", amount: "", tax: "", payment_mode: "cash", attachment_url: "", note: "", vendor_name: "", payable_status: "paid" });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState(null);
  const [reversing, setReversing] = useState(null); // expense row

  const load = () => {
    setLoading(true);
    apiGet("/admin/expenses").then(d => { setData(d || {}); setLoading(false); }).catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const admin = localStorage.getItem("admin_username") || "admin";

  const save = async () => {
    if (saving) return;
    const amount = parseFloat(form.amount);
    if (!form.expense_date || !form.category || !amount || amount <= 0) { setErr("Date, category and a positive amount are required"); return; }
    setSaving(true); setErr(null);
    const { ok, data: res } = await apiPost("/admin/expenses", {
      expense_date: form.expense_date, category: form.category, amount,
      tax: parseFloat(form.tax) || 0, payment_mode: form.payment_mode,
      attachment_url: form.attachment_url, note: form.note, approved_by: admin,
      vendor_name: form.vendor_name, payable_status: form.payable_status,
    });
    setSaving(false);
    if (!ok) { setErr(res.error || "Failed to save expense"); return; }
    setModal(false);
    setForm({ expense_date: new Date().toISOString().slice(0, 10), category: "Tent Maintenance", amount: "", tax: "", payment_mode: "cash", attachment_url: "", note: "", vendor_name: "", payable_status: "paid" });
    load();
  };

  const doReverse = async () => {
    const reason = window.prompt("Reason for reversing this expense:", "");
    if (!reason) return;
    await apiPost(`/admin/expenses/${reversing.id}/reverse`, { reason, approved_by: admin });
    setReversing(null);
    load();
  };

  const rows = data.expenses || [];
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 18, fontWeight: 800 }}>Operating Expenses</div>
          <div style={{ color: C.textMuted, fontSize: 13 }}>Net total: {fmt(data.net_total || 0)} ({data.total || 0} entries)</div>
        </div>
        <BtnPrimary onClick={() => setModal(true)}>+ Add Expense</BtnPrimary>
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr>{["Date", "Category", "Vendor", "Amount", "Tax", "Mode", "Payable", "Approved By", "Note", "Action"].map(h => <th key={h} style={thS}>{h}</th>)}</tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={10} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>Loading...</td></tr>}
            {!loading && rows.length === 0 && <tr><td colSpan={10} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>No expenses recorded yet</td></tr>}
            {!loading && rows.map(r => (
              <tr key={r.id} style={r.reversal_of_id ? { background: C.redLight + "40" } : undefined}>
                <td style={tdS}>{r.expense_date}</td>
                <td style={tdS}>{r.category}{r.reversal_of_id && <span style={{ color: C.red, fontSize: 10, fontWeight: 700, marginLeft: 6 }}>REVERSAL</span>}</td>
                <td style={{ ...tdS, color: C.textSub }}>{r.vendor_name || "—"}</td>
                <td style={{ ...tdS, color: r.amount < 0 ? C.red : C.text, fontWeight: 700 }}>{fmt(r.amount)}</td>
                <td style={tdS}>{fmt(r.tax)}</td>
                <td style={{ ...tdS, color: C.textSub, textTransform: "uppercase", fontSize: 11 }}>{r.payment_mode}</td>
                <td style={tdS}>
                  {!r.reversal_of_id && (
                    <span style={{ background: (r.payable_status === "unpaid" ? C.amber : C.green) + "18", color: r.payable_status === "unpaid" ? C.amber : C.green, padding: "3px 10px", borderRadius: 24, fontSize: 11, fontWeight: 700 }}>
                      {r.payable_status === "unpaid" ? "Unpaid" : "Paid"}
                    </span>
                  )}
                </td>
                <td style={tdS}>{r.approved_by}</td>
                <td style={{ ...tdS, color: C.textMuted, fontSize: 12 }}>{r.note || "—"}</td>
                <td style={tdS}>
                  {!r.reversal_of_id && (isSuperAdmin() ? (
                    <RowAction onClick={() => setReversing(r)} tone="red">Reverse</RowAction>
                  ) : (
                    <span style={{ color: C.textMuted, fontSize: 11 }}>—</span>
                  ))}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {modal && (
        <Modal title="Add Expense" onClose={() => setModal(false)}>
          {err && <div style={{ background: C.redLight, color: C.red, padding: "8px 12px", borderRadius: 8, fontSize: 12, marginBottom: 14 }}>{err}</div>}
          <FormField label="Expense Date"><input type="date" style={inpStyle} value={form.expense_date} onChange={e => setForm({ ...form, expense_date: e.target.value })} /></FormField>
          <FormField label="Category">
            <select style={inpStyle} value={form.category} onChange={e => setForm({ ...form, category: e.target.value })}>
              {EXPENSE_CATEGORIES.map(cat => <option key={cat} value={cat}>{cat}</option>)}
            </select>
          </FormField>
          <FormField label="Vendor Name (optional)"><input style={inpStyle} value={form.vendor_name} onChange={e => setForm({ ...form, vendor_name: e.target.value })} placeholder="e.g. Acme Tent Supplies" /></FormField>
          <FormField label="Amount (₹)"><input type="number" style={inpStyle} value={form.amount} onChange={e => setForm({ ...form, amount: e.target.value })} placeholder="e.g. 2500" /></FormField>
          <FormField label="Tax (₹, optional)"><input type="number" style={inpStyle} value={form.tax} onChange={e => setForm({ ...form, tax: e.target.value })} placeholder="e.g. 450" /></FormField>
          <FormField label="Payable Status">
            <select style={inpStyle} value={form.payable_status} onChange={e => setForm({ ...form, payable_status: e.target.value })}>
              <option value="paid">Already Paid</option>
              <option value="unpaid">Unpaid — owed to vendor (shows in Vendor Payables)</option>
            </select>
          </FormField>
          <FormField label={form.payable_status === "unpaid" ? "Intended Payment Mode" : "Payment Mode"}>
            <select style={inpStyle} value={form.payment_mode} onChange={e => setForm({ ...form, payment_mode: e.target.value })}>
              <option value="cash">Cash</option><option value="upi">UPI</option><option value="card">Card</option>
              <option value="bank_transfer">Bank Transfer</option><option value="cheque">Cheque</option><option value="other">Other</option>
            </select>
          </FormField>
          <FormField label="Attachment / Bill URL (optional)"><input style={inpStyle} value={form.attachment_url} onChange={e => setForm({ ...form, attachment_url: e.target.value })} placeholder="link to receipt/bill" /></FormField>
          <FormField label="Note (optional)"><input style={inpStyle} value={form.note} onChange={e => setForm({ ...form, note: e.target.value })} /></FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setModal(false)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={save} style={{ flex: 1 }}>{saving ? "Saving..." : "Save Expense"}</BtnPrimary>
          </div>
        </Modal>
      )}

      {reversing && (
        <Modal title={`Reverse Expense`} onClose={() => setReversing(null)}>
          <div style={{ fontSize: 13, color: C.textSub, marginBottom: 16 }}>
            This posts a negative-amount entry that cancels out <b>{fmt(reversing.amount)}</b> ({reversing.category}, {reversing.expense_date}) — the original row is kept as-is for the audit trail.
          </div>
          <div style={{ display: "flex", gap: 10 }}>
            <BtnSecondary onClick={() => setReversing(null)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={doReverse} style={{ flex: 1, background: C.red }}>Reverse It</BtnPrimary>
          </div>
        </Modal>
      )}
    </div>
  );
};

// ─── Vendor Payables ─────────────────────────────────────────────
//
// Expenses recorded as payable_status='unpaid' — money owed to a
// vendor but not yet sent. Distinct from Operating Expenses, which
// shows everything incurred regardless of settlement. Marking one
// paid here settles the Accounts Payable liability (see
// booking-service/expenses.go's adminMarkExpensePaid).
const VendorPayables = () => {
  const [data, setData] = useState({ payables: [], total: 0, total_due: 0 });
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(null);
  const [payMode, setPayMode] = useState("bank_transfer");
  const [saving, setSaving] = useState(false);

  const load = () => {
    setLoading(true);
    apiGet("/admin/vendor-payables").then(d => { setData(d || {}); setLoading(false); }).catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const admin = localStorage.getItem("admin_username") || "admin";

  const markPaid = async () => {
    if (saving) return;
    setSaving(true);
    await apiPost(`/admin/expenses/${paying.id}/mark-paid`, { payment_mode: payMode, paid_by: admin });
    setSaving(false);
    setPaying(null);
    load();
  };

  const rows = data.payables || [];
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 18, fontWeight: 800 }}>Vendor Payables</div>
          <div style={{ color: C.textMuted, fontSize: 13 }}>Money owed to vendors, not yet paid out</div>
        </div>
        <StatCard icon="" label="Total Payable" value={fmt(data.total_due || 0)} sub={`${data.total || 0} outstanding`} color={C.amber} />
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr>{["Date", "Vendor", "Category", "Amount Due", "Days Outstanding", "Approved By", "Note", "Action"].map(h => <th key={h} style={thS}>{h}</th>)}</tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={8} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>Loading...</td></tr>}
            {!loading && rows.length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>No outstanding payables — everything is settled</td></tr>}
            {!loading && rows.map(r => (
              <tr key={r.id}>
                <td style={tdS}>{r.expense_date}</td>
                <td style={{ ...tdS, fontWeight: 600 }}>{r.vendor_name}</td>
                <td style={tdS}>{r.category}</td>
                <td style={{ ...tdS, color: C.amber, fontWeight: 700 }}>{fmt(r.amount_due)}</td>
                <td style={{ ...tdS, color: r.days_outstanding > 30 ? C.red : C.textSub }}>{r.days_outstanding} days</td>
                <td style={tdS}>{r.approved_by}</td>
                <td style={{ ...tdS, color: C.textMuted, fontSize: 12 }}>{r.note || "—"}</td>
                <td style={tdS}>
                  <RowAction onClick={() => { setPaying(r); setPayMode(r.intended_payment_mode || "bank_transfer"); }} tone="green">Mark Paid</RowAction>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {paying && (
        <Modal title={`Settle Payable — ${paying.vendor_name}`} onClose={() => setPaying(null)}>
          <div style={{ fontSize: 13, color: C.textSub, marginBottom: 16 }}>
            Marks <b>{fmt(paying.amount_due)}</b> ({paying.category}, {paying.expense_date}) as paid and posts the settlement to the ledger.
          </div>
          <FormField label="Paid Via">
            <select style={inpStyle} value={payMode} onChange={e => setPayMode(e.target.value)}>
              <option value="cash">Cash</option><option value="upi">UPI</option><option value="card">Card</option>
              <option value="bank_transfer">Bank Transfer</option><option value="cheque">Cheque</option><option value="other">Other</option>
            </select>
          </FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setPaying(null)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={markPaid} style={{ flex: 1 }}>{saving ? "Saving..." : "Mark Paid"}</BtnPrimary>
          </div>
        </Modal>
      )}
    </div>
  );
};

// ─── Customer Receivables ────────────────────────────────────────
//
// Accounts-receivable view of the same underlying data as the
// Payments screen — bookings with money still owed, bucketed by
// how long it's been outstanding (aging), for collections
// follow-up rather than per-booking payment recording.
const CustomerReceivables = () => {
  const [data, setData] = useState({ receivables: [], total: 0, total_due: 0, aging_buckets: {} });
  const [loading, setLoading] = useState(true);
  const [bucket, setBucket] = useState("all");

  useEffect(() => {
    apiGet("/admin/customer-receivables").then(d => { setData(d || {}); setLoading(false); }).catch(() => setLoading(false));
  }, []);

  const rows = data.receivables || [];
  const filtered = bucket === "all" ? rows : rows.filter(r => r.aging_bucket === bucket);
  const buckets = ["0-7 days", "8-30 days", "31+ days"];
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Customer Receivables</div>
      <div style={{ color: C.textMuted, fontSize: 13, marginBottom: 16 }}>Bookings with money still owed, aged by days outstanding</div>

      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 20 }}>
        <StatCard icon="" label="Total Receivable" value={fmt(data.total_due || 0)} sub={`${data.total || 0} bookings`} color={C.amber} />
        {buckets.map(b => (
          <StatCard key={b} icon="" label={b} value={fmt(data.aging_buckets?.[b] || 0)} color={b === "31+ days" ? C.red : C.textSub} />
        ))}
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", gap: 6, flexWrap: "wrap" }}>
          {["all", ...buckets].map(b => (
            <Chip key={b} active={bucket === b} onClick={() => setBucket(b)}>{b === "all" ? "All" : b}</Chip>
          ))}
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>{["Booking", "Customer", "Tent", "Total Value", "Received", "Due", "Booked On", "Aging"].map(h => <th key={h} style={thS}>{h}</th>)}</tr>
            </thead>
            <tbody>
              {loading && <tr><td colSpan={8} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && filtered.length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>Nothing outstanding</td></tr>}
              {!loading && filtered.map(r => (
                <tr key={r.booking_ref}>
                  <td style={{ ...tdS, color: C.primary, fontWeight: 700, fontFamily: "monospace", fontSize: 12 }}>{r.booking_ref}</td>
                  <td style={tdS}>{r.customer}</td>
                  <td style={{ ...tdS, color: C.textSub }}>{r.tent_name}</td>
                  <td style={tdS}>{fmt(r.total_value)}</td>
                  <td style={{ ...tdS, color: C.green }}>{fmt(r.received)}</td>
                  <td style={{ ...tdS, color: C.amber, fontWeight: 700 }}>{fmt(r.due)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{r.booked_at}</td>
                  <td style={tdS}>
                    <span style={{ background: (r.aging_bucket === "31+ days" ? C.red : C.amber) + "18", color: r.aging_bucket === "31+ days" ? C.red : C.amber, padding: "3px 10px", borderRadius: 24, fontSize: 11, fontWeight: 700 }}>{r.aging_bucket}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

// ─── Multi-Currency / Exchange Rates + FX Report (Phase 3) ──────────
//
// Updating a rate here only affects NEW bookings from this point
// on — every existing booking keeps the rate it locked in at
// booking time, forever. That's the hard rule the backend enforces
// (see kumbh_backend/booking-service/currency.go); this screen
// never offers a way to touch a past booking's rate.
const Currency = () => {
  const [rates, setRates] = useState([]);
  const [fx, setFx] = useState({ bookings: [], total_gain_loss: 0 });
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(null); // currency_code
  const [newRate, setNewRate] = useState("");

  const load = () => {
    setLoading(true);
    Promise.all([apiGet("/admin/exchange-rates"), apiGet("/admin/finance/fx-report")])
      .then(([r, f]) => { setRates(r?.rates || []); setFx(f || {}); setLoading(false); })
      .catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const admin = localStorage.getItem("admin_username") || "admin";

  const saveRate = async (code) => {
    const rate = parseFloat(newRate);
    if (!rate || rate <= 0) return;
    await apiPut(`/admin/exchange-rates/${code}`, { rate_to_inr: rate, updated_by: admin });
    setEditing(null); setNewRate("");
    load();
  };

  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Currency & Exchange Rates</div>
      <div style={{ color: C.textMuted, fontSize: 13, marginBottom: 20 }}>Rates apply to new bookings only — past bookings keep the rate they locked in at booking time.</div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, marginBottom: 24 }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, fontWeight: 700, fontSize: 14, color: C.text }}>Current Rates (→ INR)</div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Currency", "Rate to INR", "Last Updated", "Updated By", "Action"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={5} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && rates.map(r => (
                <tr key={r.currency_code}>
                  <td style={{ ...tdS, fontWeight: 700 }}>{r.currency_code}</td>
                  <td style={tdS}>
                    {editing === r.currency_code
                      ? <input type="number" autoFocus style={{ ...inpStyle, width: 100 }} value={newRate} onChange={e => setNewRate(e.target.value)} />
                      : `₹${r.rate_to_inr}`}
                  </td>
                  <td style={{ ...tdS, color: C.textMuted }}>{r.updated_at}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{r.updated_by || "—"}</td>
                  <td style={tdS}>
                    {editing === r.currency_code ? (
                      <div style={{ display: "flex", gap: 6 }}>
                        <RowAction onClick={() => saveRate(r.currency_code)} tone="green">Save</RowAction>
                        <RowAction onClick={() => setEditing(null)} tone="neutral">Cancel</RowAction>
                      </div>
                    ) : (
                      <RowAction onClick={() => { setEditing(r.currency_code); setNewRate(String(r.rate_to_inr)); }} tone="primary">Update</RowAction>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 14, color: C.text }}>Foreign Exchange Gain/Loss</div>
            <div style={{ color: C.textMuted, fontSize: 11 }}>Booked rate vs. today's rate, per foreign-currency booking</div>
          </div>
          <div style={{ fontWeight: 800, fontSize: 16, color: (fx.total_gain_loss || 0) >= 0 ? C.green : C.red }}>
            {(fx.total_gain_loss || 0) >= 0 ? "+" : ""}{fmt(fx.total_gain_loss || 0)}
          </div>
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Booking", "Currency", "Foreign Amount", "Booked Rate", "Current Rate", "INR @ Booking", "INR @ Today", "Gain/Loss"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {!loading && (fx.bookings || []).length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>No foreign-currency bookings yet</td></tr>}
              {(fx.bookings || []).map(b => (
                <tr key={b.booking_ref}>
                  <td style={{ ...tdS, color: C.primary, fontWeight: 700, fontFamily: "monospace", fontSize: 12 }}>{b.booking_ref}</td>
                  <td style={tdS}>{b.currency}</td>
                  <td style={tdS}>{b.foreign_amount.toLocaleString()}</td>
                  <td style={tdS}>₹{b.booked_rate}</td>
                  <td style={tdS}>₹{b.current_rate}</td>
                  <td style={tdS}>{fmt(b.inr_value_at_booking)}</td>
                  <td style={tdS}>{fmt(b.inr_value_at_current_rate)}</td>
                  <td style={{ ...tdS, fontWeight: 700, color: b.gain_loss >= 0 ? C.green : C.red }}>{b.gain_loss >= 0 ? "+" : ""}{fmt(b.gain_loss)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

// ─── Payment Gateway Settlement & Reconciliation (Phase 4) ──────────
//
// The three-way match: Booking Amount ↔ Payment Gateway Record ↔
// Bank Settlement. There's no live Razorpay Settlement API hooked
// up here (this server has no public HTTPS endpoint), so "bank
// settlement" is what an accountant enters after reading the
// actual bank statement — the Record Settlement action below.
const RECON_STATUS_META = {
  matched:  { emoji: "", label: "Matched",  color: C.green },
  partial:  { emoji: "", label: "Partial",  color: C.amber },
  mismatch: { emoji: "", label: "Mismatch", color: C.red },
  pending:  { emoji: "", label: "Pending",  color: C.textMuted },
};

const Reconciliation = () => {
  const [summary, setSummary] = useState([]);
  const [recon, setRecon] = useState({ reconciliation: [], status_counts: {} });
  const [exceptions, setExceptions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState("all"); // all | exceptions
  const [settling, setSettling] = useState(null); // booking_ref
  const [form, setForm] = useState({ settlement_id: "", settlement_date: new Date().toISOString().slice(0, 10), amount: "" });
  const [err, setErr] = useState(null);

  const load = () => {
    setLoading(true);
    Promise.all([
      apiGet("/admin/gateway-summary"),
      apiGet("/admin/reconciliation"),
      apiGet("/admin/reconciliation/exceptions"),
    ]).then(([s, r, e]) => {
      setSummary(s?.providers || []);
      setRecon(r || {});
      setExceptions(e?.exceptions || []);
      setLoading(false);
    }).catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const admin = localStorage.getItem("admin_username") || "admin";

  const openSettle = (ref) => {
    setSettling(ref);
    setForm({ settlement_id: "", settlement_date: new Date().toISOString().slice(0, 10), amount: "" });
    setErr(null);
  };

  const submitSettlement = async () => {
    const amount = parseFloat(form.amount);
    if (!amount || amount <= 0) { setErr("Enter a valid amount"); return; }
    const { ok, data: res } = await apiPost(`/admin/bookings/${settling}/bank-settlement`, {
      gateway: "razorpay", settlement_id: form.settlement_id,
      settlement_date: form.settlement_date, amount, recorded_by: admin,
    });
    if (!ok) { setErr(res.error || "Failed to record settlement"); return; }
    setSettling(null);
    load();
  };

  const rows = tab === "exceptions" ? exceptions : (recon.reconciliation || []);
  const counts = recon.status_counts || {};
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Payment Gateway Settlement & Reconciliation</div>
      <div style={{ color: C.textMuted, fontSize: 13, marginBottom: 20 }}>Booking Amount ↔ Payment Gateway Record ↔ Bank Settlement</div>

      {/* Gateway Summary */}
      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, marginBottom: 20 }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, fontWeight: 700, fontSize: 14, color: C.text }}>Payment Gateway Summary</div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Gateway", "Transactions", "Gross Collection", "Gateway Fee", "Tax on Fee", "Net Settlement", "Failed Txns", "Failed Amount"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={8} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && summary.length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>No transactions yet</td></tr>}
              {!loading && summary.map(p => (
                <tr key={p.gateway}>
                  <td style={{ ...tdS, fontWeight: 700, textTransform: "capitalize" }}>{p.gateway}</td>
                  <td style={tdS}>{p.transactions}</td>
                  <td style={tdS}>{fmt(p.gross_collection)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{fmt(p.gateway_fee)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{fmt(p.tax_on_fee)}</td>
                  <td style={{ ...tdS, fontWeight: 700, color: C.green }}>{fmt(p.net_settlement)}</td>
                  <td style={{ ...tdS, color: p.failed_transactions > 0 ? C.red : C.textMuted }}>{p.failed_transactions}</td>
                  <td style={{ ...tdS, color: p.failed_transactions > 0 ? C.red : C.textMuted }}>{fmt(p.failed_amount)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Status cards */}
      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 20 }}>
        {Object.entries(RECON_STATUS_META).map(([key, meta]) => (
          <StatCard key={key} icon={meta.emoji} label={meta.label} value={counts[key] || 0} color={meta.color} />
        ))}
      </div>

      {/* Reconciliation table */}
      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", gap: 6 }}>
          <Chip active={tab === "all"} onClick={() => setTab("all")}>All</Chip>
          <Chip active={tab === "exceptions"} onClick={() => setTab("exceptions")} tone="red">
            Exceptions {exceptions.length > 0 ? `(${exceptions.length})` : ""}
          </Chip>
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Booking", "Booking Amt", "Gateway Amt", "Fee+Tax", "Expected Net", "Bank Settled", "Settlement Ref", "Status", "Action"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {!loading && rows.length === 0 && <tr><td colSpan={9} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>{tab === "exceptions" ? "No mismatches — all clear" : "No gateway payments yet"}</td></tr>}
              {rows.map(r => {
                const meta = RECON_STATUS_META[r.status] || RECON_STATUS_META.pending;
                return (
                  <tr key={r.booking_ref} style={r.status === "mismatch" ? { background: C.redLight + "40" } : undefined}>
                    <td style={{ ...tdS, color: C.primary, fontWeight: 700, fontFamily: "monospace", fontSize: 12 }}>{r.booking_ref}</td>
                    <td style={tdS}>{fmt(r.booking_amount)}</td>
                    <td style={tdS}>{fmt(r.gateway_amount)}</td>
                    <td style={{ ...tdS, color: C.textMuted }}>{fmt(r.gateway_fee_and_tax)}</td>
                    <td style={tdS}>{fmt(r.expected_net_settlement)}</td>
                    <td style={tdS}>{r.bank_settled_amount > 0 ? fmt(r.bank_settled_amount) : "—"}</td>
                    <td style={{ ...tdS, color: C.textMuted, fontSize: 11 }}>{r.settlement_id || "—"}</td>
                    <td style={tdS}>
                      <span style={{ background: meta.color + "18", color: meta.color, padding: "3px 10px", borderRadius: 24, fontSize: 11, fontWeight: 700 }}>{meta.emoji} {meta.label}</span>
                    </td>
                    <td style={tdS}>
                      {(r.status === "partial") && (
                        <RowAction onClick={() => openSettle(r.booking_ref)} tone="primary">Record Settlement</RowAction>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {settling && (
        <Modal title={`Record Bank Settlement — ${settling}`} onClose={() => setSettling(null)}>
          {err && <div style={{ background: C.redLight, color: C.red, padding: "8px 12px", borderRadius: 8, fontSize: 12, marginBottom: 14 }}>{err}</div>}
          <FormField label="Settlement Date"><input type="date" style={inpStyle} value={form.settlement_date} onChange={e => setForm({ ...form, settlement_date: e.target.value })} /></FormField>
          <FormField label="Settlement ID / Bank UTR"><input style={inpStyle} value={form.settlement_id} onChange={e => setForm({ ...form, settlement_id: e.target.value })} placeholder="e.g. UTR reference" /></FormField>
          <FormField label="Amount Actually Deposited (₹)"><input type="number" style={inpStyle} value={form.amount} onChange={e => setForm({ ...form, amount: e.target.value })} placeholder="from the bank statement" /></FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setSettling(null)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={submitSettlement} style={{ flex: 1 }}>Record Settlement</BtnPrimary>
          </div>
        </Modal>
      )}
    </div>
  );
};

// ─── Shared period-report table (Phase 5: P&L + GST) ────────────────
const PERIODS = [
  { id: "daily", label: "Daily" },
  { id: "weekly", label: "Weekly" },
  { id: "monthly", label: "Monthly" },
  { id: "yearly", label: "Yearly" },
];

const PeriodPicker = ({ period, setPeriod }) => (
  <div style={{ display: "flex", gap: 6 }}>
    {PERIODS.map(p => (
      <Chip key={p.id} active={period === p.id} onClick={() => setPeriod(p.id)}>{p.label}</Chip>
    ))}
  </div>
);

// ─── Profit & Loss (Phase 5) ────────────────────────────────────────
const ProfitAndLoss = () => {
  const [period, setPeriod] = useState("monthly");
  const [data, setData] = useState({ rows: [], note: "" });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    apiGet(`/admin/finance/pnl?period=${period}`).then(d => { setData(d || {}); setLoading(false); }).catch(() => setLoading(false));
  }, [period]);

  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };
  const rows = data.rows || [];

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Profit & Loss</div>
      <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 16, maxWidth: 700 }}>{data.note}</div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ fontWeight: 700, fontSize: 14, color: C.text }}>Net Revenue − Total Expenses = Net Operating Profit</div>
          <PeriodPicker period={period} setPeriod={setPeriod} />
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Period", "Gross Booking Value", "Refunds", "Net Revenue", "Operating Expenses", "Gateway Charges", "Total Expenses", "Net Operating Profit"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={8} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && rows.length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>No data for this period</td></tr>}
              {!loading && rows.map(r => (
                <tr key={r.period}>
                  <td style={{ ...tdS, fontWeight: 700 }}>{r.period}</td>
                  <td style={tdS}>{fmt(r.gross_booking_value)}</td>
                  <td style={{ ...tdS, color: C.red }}>{r.refunds > 0 ? `− ${fmt(r.refunds)}` : "—"}</td>
                  <td style={tdS}>{fmt(r.net_revenue)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{fmt(r.operating_expenses)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{fmt(r.gateway_charges)}</td>
                  <td style={tdS}>{fmt(r.total_expenses)}</td>
                  <td style={{ ...tdS, fontWeight: 800, color: r.net_operating_profit >= 0 ? C.green : C.red }}>{fmt(r.net_operating_profit)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

// ─── Tax / GST Report (Phase 5) ─────────────────────────────────────
const GSTReport = () => {
  const [period, setPeriod] = useState("monthly");
  const [data, setData] = useState({ rows: [], note: "" });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    apiGet(`/admin/finance/gst-report?period=${period}`).then(d => { setData(d || {}); setLoading(false); }).catch(() => setLoading(false));
  }, [period]);

  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };
  const rows = data.rows || [];

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Tax / GST Report</div>
      <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 16, maxWidth: 700 }}>{data.note}</div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ fontWeight: 700, fontSize: 14, color: C.text }}>GST Collected vs Input Tax Credit</div>
          <PeriodPicker period={period} setPeriod={setPeriod} />
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Period", "Taxable Value", "GST Collected", "CGST", "SGST", "IGST", "Input Tax Credit", "Net GST Payable", "Foreign Bookings"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={9} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && rows.length === 0 && <tr><td colSpan={9} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>No data for this period</td></tr>}
              {!loading && rows.map(r => (
                <tr key={r.period}>
                  <td style={{ ...tdS, fontWeight: 700 }}>{r.period}</td>
                  <td style={tdS}>{fmt(r.taxable_value)}</td>
                  <td style={tdS}>{fmt(r.gst_collected)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{fmt(r.cgst)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{fmt(r.sgst)}</td>
                  <td style={{ ...tdS, color: C.textMuted }}>{fmt(r.igst)}</td>
                  <td style={{ ...tdS, color: C.green }}>{fmt(r.input_tax_credit)}</td>
                  <td style={{ ...tdS, fontWeight: 800 }}>{fmt(r.net_gst_payable)}</td>
                  <td style={tdS}>{r.foreign_booking_count > 0 ? <span style={{ background: C.amberLight, color: C.amber, padding: "3px 8px", borderRadius: 12, fontSize: 11, fontWeight: 700 }}>{r.foreign_booking_count} — verify with CA</span> : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

// ─── Invoice Management + Credit/Debit Notes (Phase 5) ──────────────
//
// Auto-generated on booking confirmation — no create/edit form
// here on purpose. View / Download PDF / Email / Print (Print
// just opens the PDF, letting the browser's own PDF viewer print
// it), plus issuing a credit or debit note against an invoice.
const Invoices = () => {
  const [invoices, setInvoices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [viewing, setViewing] = useState(null); // invoice id
  const [detail, setDetail] = useState(null);
  const [noting, setNoting] = useState(null); // { invoiceId, type }
  const [noteForm, setNoteForm] = useState({ amount: "", reason: "" });
  const [notice, setNotice] = useState(null);

  const load = () => {
    setLoading(true);
    apiGet("/admin/invoices").then(d => { setInvoices(d?.invoices || []); setLoading(false); }).catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const admin = localStorage.getItem("admin_username") || "admin";

  const openView = async (id) => {
    setViewing(id);
    setDetail(null);
    const d = await apiGet(`/admin/invoices/${id}`);
    setDetail(d);
  };

  const downloadPDF = (id, invoiceNumber) => {
    window.open(`${API_BASE}/admin/invoices/${id}/pdf`, "_blank");
  };

  const emailInvoice = async (id) => {
    const { ok, data: res } = await apiPost(`/admin/invoices/${id}/email`, {});
    setNotice(ok ? { kind: "ok", text: `Emailed to ${res.to}` } : { kind: "err", text: res.error || "Failed to email invoice" });
    setTimeout(() => setNotice(null), 4000);
  };

  const openNote = (invoiceId, type) => {
    setNoting({ invoiceId, type });
    setNoteForm({ amount: "", reason: "" });
  };

  const submitNote = async () => {
    const amount = parseFloat(noteForm.amount);
    if (!amount || amount <= 0 || !noteForm.reason.trim()) return;
    const path = noting.type === "credit" ? "credit-note" : "debit-note";
    await apiPost(`/admin/invoices/${noting.invoiceId}/${path}`, { amount, reason: noteForm.reason, issued_by: admin });
    setNoting(null);
    if (viewing === noting.invoiceId) openView(viewing);
    load();
  };

  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <div>
          <div style={{ color: C.text, fontSize: 18, fontWeight: 800 }}>Invoices</div>
          <div style={{ color: C.textMuted, fontSize: 13 }}>Auto-generated on booking confirmation — {invoices.length} total</div>
        </div>
        {notice && <span style={{ color: notice.kind === "ok" ? C.green : C.red, fontSize: 13, fontWeight: 600 }}>{notice.kind === "ok" ? "" : ""} {notice.text}</span>}
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead><tr>{["Invoice No", "Booking", "Customer", "Tent", "Total", "Payment Status", "Issued", "Actions"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
          <tbody>
            {loading && <tr><td colSpan={8} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>Loading...</td></tr>}
            {!loading && invoices.length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>No invoices yet</td></tr>}
            {!loading && invoices.map(inv => (
              <tr key={inv.id}>
                <td style={{ ...tdS, color: C.primary, fontWeight: 700, fontFamily: "monospace", fontSize: 12 }}>{inv.invoice_number}</td>
                <td style={{ ...tdS, fontFamily: "monospace", fontSize: 12 }}>{inv.booking_ref}</td>
                <td style={tdS}>{inv.customer_name}</td>
                <td style={{ ...tdS, color: C.textSub }}>{inv.tent_name}</td>
                <td style={{ ...tdS, fontWeight: 700 }}>{inv.currency} {inv.total_amount}</td>
                <td style={tdS}>
                  <span style={{ background: (STATUS_COLORS[inv.payment_status_at_issue] || C.textMuted) + "18", color: STATUS_COLORS[inv.payment_status_at_issue] || C.textMuted, padding: "3px 10px", borderRadius: 24, fontSize: 11, fontWeight: 700 }}>{inv.payment_status_at_issue}</span>
                </td>
                <td style={{ ...tdS, color: C.textMuted, fontSize: 12 }}>{inv.created_at?.slice(0, 10)}</td>
                <td style={tdS}>
                  <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                    <RowAction onClick={() => openView(inv.id)} tone="primary">View</RowAction>
                    <RowAction onClick={() => downloadPDF(inv.id)} tone="green">PDF</RowAction>
                    <RowAction onClick={() => emailInvoice(inv.id)} tone="purple">Email</RowAction>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {viewing && (
        <Modal title={detail ? detail.invoice_number : "Loading..."} onClose={() => setViewing(null)}>
          {!detail && <div style={{ color: C.textMuted, padding: 20, textAlign: "center" }}>Loading...</div>}
          {detail && (
            <div>
              {[
                ["Customer", detail.customer_name],
                ["Phone", detail.customer_phone],
                ["Billing Country", detail.billing_country],
                ["Tent", detail.tent_name],
                ["Stay Period", `${detail.check_in} → ${detail.check_out}`],
                ["Base Amount", fmt(detail.base_amount)],
                ["Tax (GST)", fmt(detail.tax)],
                ["Total", `${detail.currency} ${detail.total_amount}`],
                ["Payment Status (at issue)", detail.payment_status_at_issue],
              ].map(([label, value]) => (
                <div key={label} style={{ display: "flex", justifyContent: "space-between", padding: "7px 0", borderBottom: `1px solid ${C.border}` }}>
                  <div style={{ color: C.textMuted, fontSize: 12 }}>{label}</div>
                  <div style={{ color: C.text, fontSize: 13, fontWeight: 700 }}>{value}</div>
                </div>
              ))}

              {detail.notes.length > 0 && (
                <div style={{ marginTop: 12 }}>
                  <div style={{ color: C.textSub, fontSize: 11, fontWeight: 700, textTransform: "uppercase", marginBottom: 6 }}>Credit / Debit Notes</div>
                  {detail.notes.map(n => (
                    <div key={n.note_number} style={{ fontSize: 12, padding: "5px 0", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between" }}>
                      <span style={{ color: n.note_type === "credit" ? C.red : C.amber, fontWeight: 700 }}>{n.note_number} ({n.note_type})</span>
                      <span>{n.note_type === "credit" ? "−" : "+"}{fmt(n.amount)}</span>
                    </div>
                  ))}
                </div>
              )}

              <div style={{ display: "flex", justifyContent: "space-between", padding: "10px 0", marginTop: 8, borderTop: `2px solid ${C.border}` }}>
                <div style={{ fontWeight: 800, fontSize: 14 }}>Adjusted Total</div>
                <div style={{ fontWeight: 800, fontSize: 14, color: C.green }}>{fmt(detail.adjusted_total)}</div>
              </div>

              <div style={{ display: "flex", gap: 8, marginTop: 16, flexWrap: "wrap" }}>
                <BtnSecondary onClick={() => downloadPDF(detail.id)}>Download PDF</BtnSecondary>
                <BtnSecondary onClick={() => emailInvoice(detail.id)}>Email</BtnSecondary>
                {isSuperAdmin() && <BtnSecondary onClick={() => openNote(detail.id, "credit")}>− Credit Note</BtnSecondary>}
                {isSuperAdmin() && <BtnSecondary onClick={() => openNote(detail.id, "debit")}>+ Debit Note</BtnSecondary>}
              </div>
              {!isSuperAdmin() && <div style={{ color: C.textMuted, fontSize: 11, marginTop: 6 }}>Credit/debit notes require super admin.</div>}
            </div>
          )}
        </Modal>
      )}

      {noting && (
        <Modal title={`Issue ${noting.type === "credit" ? "Credit" : "Debit"} Note`} onClose={() => setNoting(null)}>
          <FormField label="Amount (₹)"><input type="number" style={inpStyle} value={noteForm.amount} onChange={e => setNoteForm({ ...noteForm, amount: e.target.value })} /></FormField>
          <FormField label="Reason"><input style={inpStyle} value={noteForm.reason} onChange={e => setNoteForm({ ...noteForm, reason: e.target.value })} placeholder="required" /></FormField>
          <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
            <BtnSecondary onClick={() => setNoting(null)} style={{ flex: 1 }}>Cancel</BtnSecondary>
            <BtnPrimary onClick={submitNote} style={{ flex: 1 }}>Issue Note</BtnPrimary>
          </div>
        </Modal>
      )}
    </div>
  );
};

// ─── Double-entry Ledger (Phase 6) ──────────────────────────────────
//
// Read-only, on purpose — every row here comes from a real
// booking payment, refund, or expense elsewhere in the app.
// There's no "add ledger entry" button because there must never
// be one; a system-generated ledger is the whole point.
const Ledger = () => {
  const [data, setData] = useState({ entries: [], total_debit: 0, total_credit: 0, balanced: true });
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("all");

  useEffect(() => {
    apiGet("/admin/ledger").then(d => { setData(d || {}); setLoading(false); }).catch(() => setLoading(false));
  }, []);

  const entries = data.entries || [];
  const types = ["all", ...Array.from(new Set(entries.map(e => e.reference_type)))];
  const filtered = filter === "all" ? entries : entries.filter(e => e.reference_type === filter);
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Ledger</div>
      <div style={{ color: C.textMuted, fontSize: 13, marginBottom: 16 }}>System-generated double-entry — every posting is exactly one debit row and one credit row for the same amount.</div>

      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 20 }}>
        <StatCard icon="↘" label="Total Debit" value={fmt(data.total_debit || 0)} color={C.primary} />
        <StatCard icon="↗" label="Total Credit" value={fmt(data.total_credit || 0)} color={C.purple} />
        <StatCard icon={data.balanced ? "" : ""} label="Books" value={data.balanced ? "Balanced" : "Out of balance"} color={data.balanced ? C.green : C.red} />
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", gap: 6, flexWrap: "wrap" }}>
          {types.map(t => (
            <Chip key={t} active={filter === t} onClick={() => setFilter(t)}>{t.replace(/_/g, " ")}</Chip>
          ))}
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Date", "Type", "Reference", "Account", "Debit", "Credit", "Narration"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={7} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && filtered.length === 0 && <tr><td colSpan={7} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>No ledger entries yet</td></tr>}
              {!loading && filtered.map((e, i) => (
                <tr key={i}>
                  <td style={tdS}>{e.entry_date}</td>
                  <td style={{ ...tdS, textTransform: "capitalize", color: C.textSub }}>{e.reference_type.replace(/_/g, " ")}</td>
                  <td style={{ ...tdS, fontFamily: "monospace", fontSize: 12 }}>{e.reference_id}</td>
                  <td style={{ ...tdS, fontWeight: 600 }}>{e.account}</td>
                  <td style={{ ...tdS, color: e.debit > 0 ? C.primary : C.textMuted }}>{e.debit > 0 ? fmt(e.debit) : "—"}</td>
                  <td style={{ ...tdS, color: e.credit > 0 ? C.purple : C.textMuted }}>{e.credit > 0 ? fmt(e.credit) : "—"}</td>
                  <td style={{ ...tdS, color: C.textMuted, fontSize: 12 }}>{e.narration || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

// ─── Bank / Cash Management (Phase 6) ───────────────────────────────
const BankAccounts = () => {
  const [accounts, setAccounts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiGet("/admin/bank-accounts").then(d => { setAccounts(d?.accounts || []); setLoading(false); }).catch(() => setLoading(false));
  }, []);

  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Bank & Cash Management</div>
      <div style={{ color: C.textMuted, fontSize: 13, marginBottom: 16 }}>Credits/Debits use banking language — money IN is a Credit here, money OUT is a Debit (the reverse of the ledger's own Dr/Cr for an asset account).</div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead><tr>{["Account", "Type", "Opening Balance", "Credits (In)", "Debits (Out)", "Closing Balance"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
          <tbody>
            {loading && <tr><td colSpan={6} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>Loading...</td></tr>}
            {!loading && accounts.map(a => (
              <tr key={a.id}>
                <td style={{ ...tdS, fontWeight: 700 }}>{a.account_name}</td>
                <td style={{ ...tdS, color: C.textSub, textTransform: "capitalize" }}>{a.account_type}</td>
                <td style={tdS}>{fmt(a.opening_balance)}</td>
                <td style={{ ...tdS, color: C.green }}>{fmt(a.money_in)}</td>
                <td style={{ ...tdS, color: C.red }}>{fmt(a.money_out)}</td>
                <td style={{ ...tdS, fontWeight: 800 }}>{fmt(a.closing_balance)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

// ─── Reports (Phase 6) — Excel (CSV) + PDF export ───────────────────
const REPORT_TYPES = [
  { id: "sales", label: "Sales, Booking & Payment Report" },
  { id: "outstanding-refund", label: "Outstanding & Refund Report" },
  { id: "expense-gst", label: "Expense & GST Report" },
  { id: "invoice-settlement", label: "Invoice & Settlement Report" },
  { id: "bank-reconciliation", label: "Bank Reconciliation Report" },
  { id: "currency-tax", label: "Currency & Tax Report" },
];

const Reports = () => {
  const download = (type, format) => {
    // A plain window.open can't carry an Authorization header;
    // these admin report routes don't require one at the gateway
    // (same as every other /admin/* route in this panel), so a
    // direct URL works. If that ever changes, this needs to
    // switch to a fetch()+blob download instead.
    window.open(`${API_BASE}/admin/reports/${type}?format=${format}`, "_blank");
  };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Reports</div>
      <div style={{ color: C.textMuted, fontSize: 13, marginBottom: 20 }}>Exports as CSV (opens directly in Excel) or PDF.</div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(280px,1fr))", gap: 16 }}>
        {REPORT_TYPES.map(r => (
          <div key={r.id} style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 20, boxShadow: C.shadow }}>
            <div style={{ fontWeight: 700, fontSize: 14, color: C.text, marginBottom: 14 }}>{r.label}</div>
            <div style={{ display: "flex", gap: 8 }}>
              <BtnSecondary onClick={() => download(r.id, "csv")} style={{ flex: 1 }}>Excel (CSV)</BtnSecondary>
              <BtnSecondary onClick={() => download(r.id, "pdf")} style={{ flex: 1 }}>PDF</BtnSecondary>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

// ─── Revenue Summary (Phase 2) ──────────────────────────────────────
//
// Gross Booking Value → (−) GST (pass-through, excluded from Net
// Sales) → (−) Refunds → = Net Sales. Cancelled bookings tracked
// as their own column so they never inflate revenue.
const RevenueSummary = () => {
  const [groupBy, setGroupBy] = useState("month");
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    apiGet(`/admin/revenue/summary?group_by=${groupBy}`)
      .then(d => { setRows(d?.rows || []); setLoading(false); })
      .catch(() => setLoading(false));
  }, [groupBy]);

  const GROUPS = [
    { id: "month", label: "Date / Month" },
    { id: "country", label: "Country" },
    { id: "tent", label: "Tent" },
    { id: "booking", label: "Booking" },
  ];
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow, marginTop: 20 }}>
      <div style={{ padding: "16px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 10 }}>
        <div>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14 }}>Revenue Summary</div>
          <div style={{ color: C.textMuted, fontSize: 11 }}>Gross Booking Value − GST (pass-through) − Refunds = Net Sales</div>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          {GROUPS.map(g => (
            <Chip key={g.id} active={groupBy === g.id} onClick={() => setGroupBy(g.id)}>{g.label}</Chip>
          ))}
        </div>
      </div>
      <div style={{ overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr>{[GROUPS.find(g => g.id === groupBy)?.label, "Bookings", "Gross Value", "GST (pass-through)", "Refunds", "Net Sales", "Cancelled"].map(h => <th key={h} style={thS}>{h}</th>)}</tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={7} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>Loading...</td></tr>}
            {!loading && rows.length === 0 && <tr><td colSpan={7} style={{ textAlign: "center", padding: 30, color: C.textMuted }}>No revenue recorded yet</td></tr>}
            {!loading && rows.map(r => (
              <tr key={r.group}>
                <td style={{ ...tdS, fontWeight: 700 }}>{r.group}</td>
                <td style={tdS}>{r.booking_count}</td>
                <td style={tdS}>{fmt(r.gross_booking_value)}</td>
                <td style={{ ...tdS, color: C.textMuted }}>{fmt(r.gst_collected)}</td>
                <td style={{ ...tdS, color: C.red }}>{r.refunds > 0 ? `− ${fmt(r.refunds)}` : "—"}</td>
                <td style={{ ...tdS, fontWeight: 800, color: C.green }}>{fmt(r.net_sales)}</td>
                <td style={{ ...tdS, color: C.textMuted }}>{r.cancelled_count > 0 ? `${r.cancelled_count} (${fmt(r.cancelled_value)})` : "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

// ─── Revenue ──────────────────────────────────────────────────────
const Revenue = () => {
  const [stats, setStats] = useState({ total_revenue: 0, today_revenue: 0 });
  const [revenue, setRevenue] = useState([]);
  useEffect(() => {
    apiGet("/admin/stats").then(d => { if(d) setStats(d); });
    apiGet("/admin/revenue/weekly").then(d => { if(d?.revenue) setRevenue(d.revenue); });
  }, []);
  const maxRev = revenue.length ? Math.max(...revenue.map(r => r.amount)) : 1;
  const tentRev = [{ name: "Regular Capsule", revenue: 320000, color: C.green }, { name: "Luxury Capsule", revenue: 603000, color: C.primary }, { name: "Premium Capsule", revenue: 600000, color: C.purple }];
  const total = tentRev.reduce((a, b) => a + b.revenue, 0);
  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 20 }}>Revenue Analytics</div>
      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 20 }}>
        <StatCard icon="" label="Total Revenue" value={fmt(stats.total_revenue||0)} trend="18%" color={C.green} />
        <StatCard icon="" label="This Week" value={fmt(revenue.reduce((a,r)=>a+r.amount,0))} trend="6%" color={C.primary} />
        <StatCard icon="" label="Today" value={fmt(stats.today_revenue||0)} color={C.amber} />
        <StatCard icon="" label="Avg per Booking" value={fmt(3752)} color={C.purple} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1.4fr 1fr", gap: 16 }}>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 22, boxShadow: C.shadow }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 4 }}>Weekly Revenue Trend</div>
          <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 20 }}>Revenue generated per day</div>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 10, height: 150 }}>
            {(revenue.length ? revenue : [{day:"—",amount:0}]).map((r, i) => (
              <div key={r.day} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                <div style={{ color: C.textMuted, fontSize: 10 }}>{(r.amount / 1000).toFixed(0)}k</div>
                <div style={{ width: "100%", height: (r.amount / maxRev) * 120, background: i === 5 ? C.primary : C.primaryLight, borderRadius: "6px 6px 0 0", minHeight: 4 }} />
                <div style={{ color: i === 5 ? C.primary : C.textMuted, fontSize: 11, fontWeight: i === 5 ? 700 : 400 }}>{r.day}</div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 22, boxShadow: C.shadow }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 4 }}>Revenue by Tent Type</div>
          <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 20 }}>Total: {fmt(total)}</div>
          {tentRev.map(t => (
            <div key={t.name} style={{ marginBottom: 18 }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 6 }}>
                <div style={{ color: C.text, fontSize: 13, fontWeight: 600 }}>{t.name}</div>
                <div style={{ color: t.color, fontWeight: 700, fontSize: 13 }}>{fmt(t.revenue)}</div>
              </div>
              <div style={{ background: C.bg, borderRadius: 99, height: 8, overflow: "hidden" }}>
                <div style={{ background: t.color, height: 8, width: `${(t.revenue / total) * 100}%`, borderRadius: 99 }} />
              </div>
              <div style={{ color: C.textMuted, fontSize: 11, marginTop: 3 }}>{((t.revenue / total) * 100).toFixed(1)}% of total revenue</div>
            </div>
          ))}
        </div>
      </div>
      <RevenueSummary />
    </div>
  );
};

// ─── Notifications ────────────────────────────────────────────────
const Notifications = () => {
  const [title, setTitle] = useState(""); const [msg, setMsg] = useState(""); const [target, setTarget] = useState("all"); const [sent, setSent] = useState(false); const [loading, setLoading] = useState(false); const [sentCount, setSentCount] = useState(0);
  const send = async () => {
    if (!title || !msg) return;
    setLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/notifications/send`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
        body: JSON.stringify({ title, body: msg, target }),
      });
      const data = await res.json();
      setSentCount(data.sent || 0);
      setSent(true);
      setTimeout(() => setSent(false), 4000);
      setTitle(""); setMsg("");
    } catch(e) {
      setSent(true); setSentCount(0);
      setTimeout(() => setSent(false), 3000);
    }
    setLoading(false);
  };
  const templates = [
    { label: "Welcome Offer", title: "Special Welcome Discount!", msg: "Book your first tent and get 20% off with code WELCOME20!" },
    { label: "Booking Reminder", title: "Your Check-in is Tomorrow", msg: "Don't forget! Your Kumbh Tent check-in is scheduled for tomorrow. Have a safe journey!" },
    { label: "Surge Alert", title: "High Demand — Book Now!", msg: "Tent prices are rising due to peak season. Book now to secure your spot!" },
    { label: "New Tent Available", title: "New Premium Tent Added!", msg: "We've added a new Premium Capsule Tent. Book now for an exclusive experience!" },
  ];
  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 20 }}>Push Notifications</div>
      {sent && <div style={{ background: C.greenLight, border: `1px solid ${C.green}44`, color: C.green, borderRadius: 10, padding: "11px 16px", marginBottom: 16, fontWeight: 600, fontSize: 13 }}>Notification sent to {sentCount} users!</div>}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 22, boxShadow: C.shadow }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 18 }}>Compose Notification</div>
          <FormField label="Target Audience">
            <div style={{ display: "flex", gap: 8 }}>
              {[["all", "All Users"], ["active", "Active"], ["new", "New Users"]].map(([val, lbl]) => (
                <Chip key={val} active={target === val} onClick={() => setTarget(val)} style={{ flex: 1 }}>{lbl}</Chip>
              ))}
            </div>
          </FormField>
          <FormField label="Title"><input style={inpStyle} placeholder="Notification title..." value={title} onChange={e => setTitle(e.target.value)} /></FormField>
          <FormField label="Message">
            <textarea style={{ ...inpStyle, minHeight: 90, resize: "vertical" }} placeholder="Write your message here..." value={msg} onChange={e => setMsg(e.target.value)} />
          </FormField>
          <ButtonSoftGlow onClick={send} disabled={loading} tone="primary" fullWidth>{loading ? "Sending..." : "Send Notification"}</ButtonSoftGlow>
        </div>
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 22, boxShadow: C.shadow }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 6 }}>Quick Templates</div>
          <div style={{ color: C.textMuted, fontSize: 12, marginBottom: 16 }}>Click to auto-fill the form</div>
          {templates.map(t => (
            <div key={t.label} onClick={() => { setTitle(t.title); setMsg(t.msg); }}
              style={{ border: `1px solid ${C.border}`, borderRadius: 10, padding: "13px 14px", marginBottom: 10, cursor: "pointer", transition: "all 0.12s" }}
              onMouseEnter={e => { e.currentTarget.style.borderColor = C.primary; e.currentTarget.style.background = C.primaryLight; }}
              onMouseLeave={e => { e.currentTarget.style.borderColor = C.border; e.currentTarget.style.background = C.white; }}>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 13, marginBottom: 3 }}>{t.label}</div>
              <div style={{ color: C.textMuted, fontSize: 12 }}>{t.title}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ─── Inventory ────────────────────────────────────────────────────
const TENT_NAMES = ["Regular Capsule Tent", "Luxury Capsule Tent", "Premium Capsule Tent"];
const DATES = Array.from({ length: 10 }, (_, i) => {
  const d = new Date(); d.setDate(d.getDate() + i);
  return d.toISOString().split("T")[0];
});
const MOCK_INVENTORY = TENT_NAMES.map(name => ({
  name,
  data: DATES.map(date => ({ date, total: 33, booked: Math.floor(Math.random() * 25), blocked: Math.floor(Math.random() * 3) })),
}));

const Inventory = () => {
  const [inventory] = useState(MOCK_INVENTORY);
  const getColor = (pct) => pct >= 90 ? C.red : pct >= 70 ? C.amber : C.green;
  const getBg = (pct) => pct >= 90 ? C.redLight : pct >= 70 ? C.amberLight : C.greenLight;
  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 6 }}>Inventory Tracker</div>
      <div style={{ color: C.textSub, fontSize: 13, marginBottom: 20 }}>Real-time tent availability for next 10 days</div>

      {/* Legend */}
      <div style={{ display: "flex", gap: 16, marginBottom: 20 }}>
        {[[C.green, C.greenLight, "Available (0–70%)"], [C.amber, C.amberLight, "Filling Up (70–90%)"], [C.red, C.redLight, "Almost Full (90%+)"]].map(([color, bg, label]) => (
          <div key={label} style={{ display: "flex", alignItems: "center", gap: 6, background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 8, padding: "6px 12px", fontSize: 12 }}>
            <div style={{ width: 10, height: 10, borderRadius: 3, background: color }} />
            <span style={{ color: C.textSub }}>{label}</span>
          </div>
        ))}
      </div>

      {inventory.map(tent => (
        <div key={tent.name} style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, marginBottom: 16, boxShadow: C.shadow, overflow: "hidden" }}>
          <div style={{ padding: "14px 20px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ color: C.text, fontWeight: 700, fontSize: 14 }}>{tent.name}</div>
            <div style={{ color: C.textSub, fontSize: 12 }}>33 total units</div>
          </div>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 700 }}>
              <thead>
                <tr>
                  <th style={{ color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 16px", textAlign: "left", background: C.bg, borderBottom: `1px solid ${C.border}`, textTransform: "uppercase" }}>Date</th>
                  <th style={{ color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 16px", textAlign: "center", background: C.bg, borderBottom: `1px solid ${C.border}`, textTransform: "uppercase" }}>Booked</th>
                  <th style={{ color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 16px", textAlign: "center", background: C.bg, borderBottom: `1px solid ${C.border}`, textTransform: "uppercase" }}>Available</th>
                  <th style={{ color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 16px", textAlign: "center", background: C.bg, borderBottom: `1px solid ${C.border}`, textTransform: "uppercase" }}>Blocked</th>
                  <th style={{ color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 16px", textAlign: "left", background: C.bg, borderBottom: `1px solid ${C.border}`, textTransform: "uppercase", minWidth: 180 }}>Occupancy</th>
                </tr>
              </thead>
              <tbody>
                {tent.data.map((d, i) => {
                  const avail = d.total - d.booked - d.blocked;
                  const pct = Math.round((d.booked / d.total) * 100);
                  const color = getColor(pct); const bg = getBg(pct);
                  return (
                    <tr key={d.date} style={{ background: i % 2 === 0 ? "transparent" : "rgba(255,255,255,0.03)" }}>
                      <td style={{ padding: "11px 16px", color: C.text, fontWeight: 600, fontSize: 13 }}>
                        {new Date(d.date).toLocaleDateString("en-IN", { weekday: "short", day: "numeric", month: "short" })}
                      </td>
                      <td style={{ padding: "11px 16px", textAlign: "center", color: C.text, fontWeight: 700 }}>{d.booked}</td>
                      <td style={{ padding: "11px 16px", textAlign: "center" }}>
                        <span style={{ background: bg, color, padding: "3px 10px", borderRadius: 24, fontSize: 12, fontWeight: 700 }}>{avail}</span>
                      </td>
                      <td style={{ padding: "11px 16px", textAlign: "center", color: C.textSub }}>{d.blocked}</td>
                      <td style={{ padding: "11px 16px" }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                          <div style={{ flex: 1, background: C.bg, borderRadius: 99, height: 8, overflow: "hidden" }}>
                            <div style={{ background: color, height: 8, width: `${pct}%`, borderRadius: 99, transition: "width 0.3s" }} />
                          </div>
                          <span style={{ color, fontWeight: 700, fontSize: 12, minWidth: 36 }}>{pct}%</span>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      ))}
    </div>
  );
};

// ─── E-Ticket Viewer ──────────────────────────────────────────────

const QRCode = ({ value, size = 80 }) => {
  const cells = 10;
  const seed = value.split("").reduce((a, c) => a + c.charCodeAt(0), 0);
  const grid = Array.from({ length: cells }, (_, r) =>
    Array.from({ length: cells }, (_, c) => ((seed * (r + 1) * (c + 1) * 7) % 13) < 6)
  );
  const cell = size / cells;
  return (
    <div style={{ display: "inline-block", background: "#fff", padding: 8, borderRadius: 8, border: `1px solid ${C.border}` }}>
      <div style={{ display: "grid", gridTemplateColumns: `repeat(${cells}, ${cell}px)`, gap: 0 }}>
        {grid.flat().map((filled, i) => (
          <div key={i} style={{ width: cell, height: cell, background: filled ? "#111" : "#fff" }} />
        ))}
      </div>
    </div>
  );
};

const classColors = { standard: C.green, luxury: C.primary, premium: C.purple };

const TicketCard = ({ ticket }) => (
  <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, overflow: "hidden", boxShadow: C.shadow }}>
    {/* Top color band */}
    <div style={{ height: 5, background: classColors[ticket.tentClass] || C.primary }} />
    <div style={{ padding: 20 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 16 }}>
        <div>
          <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.5 }}>Booking ID</div>
          <div style={{ color: classColors[ticket.tentClass], fontFamily: "monospace", fontWeight: 800, fontSize: 16 }}>{ticket.id}</div>
        </div>
        <Badge status={ticket.status} />
      </div>
      <div style={{ display: "flex", gap: 16, alignItems: "flex-start" }}>
        <div style={{ flex: 1 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
            <Avatar name={ticket.guest} size={36} />
            <div>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 14 }}>{ticket.guest}</div>
              <div style={{ color: C.textSub, fontSize: 12 }}>{ticket.phone}</div>
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 12 }}>
            {[["Tent", ticket.tent], ["Guests", ticket.guests], ["Check-in", ticket.checkIn], ["Check-out", ticket.checkOut], ["Nights", ticket.nights], ["Amount", `₹${ticket.amount.toLocaleString("en-IN")}`]].map(([l, v]) => (
              <div key={l} style={{ background: C.bg, borderRadius: 8, padding: "8px 10px" }}>
                <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 600 }}>{l}</div>
                <div style={{ color: C.text, fontSize: 12, fontWeight: 700, marginTop: 2 }}>{v}</div>
              </div>
            ))}
          </div>
          <div>
            <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 700, textTransform: "uppercase", marginBottom: 6 }}>Amenities</div>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
              {ticket.amenities.map(a => (
                <span key={a} style={{ background: C.primaryLight, color: C.primary, padding: "2px 8px", borderRadius: 24, fontSize: 11, fontWeight: 600 }}>{a}</span>
              ))}
            </div>
          </div>
        </div>
        {/* QR side */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
          <QRCode value={ticket.qr} size={90} />
          <div style={{ color: C.textMuted, fontSize: 9, textAlign: "center", maxWidth: 90 }}>{ticket.qr}</div>
        </div>
      </div>
      {/* Dashed divider */}
      <div style={{ borderTop: "2px dashed #e8eaed", margin: "16px 0" }} />
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div style={{ color: C.textMuted, fontSize: 11 }}>Booked on {ticket.bookedOn}</div>
        <LiquidMetalButton label="Print Ticket" tone="primary" size="sm" />
      </div>
    </div>
  </div>
);

const ETicket = () => {
  const [search, setSearch] = useState("");
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiGet("/admin/bookings").then(d => {
      if (d?.bookings) setBookings(d.bookings);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, []);

  const filtered = bookings.filter(b =>
    (b.booking_ref || "").toLowerCase().includes(search.toLowerCase()) ||
    (b.guest_name || "").toLowerCase().includes(search.toLowerCase()) ||
    (b.phone || "").includes(search)
  );

  // Convert real booking to ticket format
  const toTicket = (b) => ({
    id: b.booking_ref,
    guest: b.guest_name || b.phone || "Guest",
    phone: b.phone || "—",
    tent: b.tent_name || "—",
    tentClass: b.class || "standard",
    checkIn: b.check_in,
    checkOut: b.check_out,
    nights: b.nights || 0,
    guests: b.guests || 1,
    amount: b.total_amount || 0,
    status: b.status || "pending",
    qr: b.booking_ref,
    bookedOn: b.created_at ? new Date(b.created_at).toLocaleDateString("en-IN") : "—",
    amenities: ["WiFi", "AC", "Attached Bath"],
  });

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 6 }}>E-Ticket Viewer</div>
      <div style={{ color: C.textSub, fontSize: 13, marginBottom: 20 }}>View and print guest booking tickets</div>
      <div style={{ marginBottom: 20 }}>
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder=" Search by booking ID or guest name..." style={{ ...inpStyle, maxWidth: 400 }} />
      </div>
      {loading && <div style={{ color: C.textMuted, padding: 40, textAlign: "center" }}>Loading tickets...</div>}
      {!loading && filtered.length === 0 && <div style={{ color: C.textMuted, padding: 40 }}>No tickets found</div>}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(420px, 1fr))", gap: 16 }}>
        {filtered.map(b => <TicketCard key={b.booking_ref} ticket={toTicket(b)} />)}
      </div>
    </div>
  );
};

// ─── QR Scanner ───────────────────────────────────────────────────
const QRScanner = () => {
  const [input, setInput] = useState("");
  const [result, setResult] = useState(null);
  const [notFound, setNotFound] = useState(false);
  // eslint-disable-next-line
  const [scanning, setScanning] = useState(false);
  const [recentScans, setRecentScans] = useState([]);

  const scan = async () => {
    if (!input.trim()) return;
    setScanning(true);
    try {
      const data = await apiGet("/admin/bookings");
      const bookings = data?.bookings || [];
      const found = bookings.find(b =>
        b.booking_ref?.toUpperCase() === input.trim().toUpperCase()
      );
      if (found) {
        setResult({
          id: found.booking_ref,
          guest: found.guest_name || found.phone || "Guest",
          phone: found.phone || "—",
          tent: found.tent_name || "—",
          tentClass: found.class || "standard",
          checkIn: found.check_in,
          checkOut: found.check_out,
          nights: found.nights || 0,
          guests: found.guests || 1,
          amount: found.total_amount || 0,
          status: found.status,
          qr: found.booking_ref,
        });
        setNotFound(false);
      } else {
        setResult(null);
        setNotFound(true);
      }
    } catch(e) {
      setNotFound(true);
    }
    setScanning(false);
  };

  // eslint-disable-next-line
  const checkIn = (ticket) => {
    const now = new Date().toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" });
    setRecentScans([{ id: ticket.id, guest: ticket.guest, tent: ticket.tent, time: now, action: "Checked In" }, ...recentScans.slice(0, 4)]);
    setResult({ ...ticket, status: "checked_in" });
  };

  const classC = result ? (classColors[result.tentClass] || C.primary) : C.primary;

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 6 }}>QR Check-in Scanner</div>
      <div style={{ color: C.textSub, fontSize: 13, marginBottom: 20 }}>Scan or enter booking ID to check in guests</div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        {/* Scanner Panel */}
        <div>
          <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 22, boxShadow: C.shadow, marginBottom: 16 }}>
            <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 16 }}>Scan Booking QR</div>
            {/* Simulated camera box */}
            <div style={{ background: "#0a0c10", borderRadius: 12, height: 200, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", marginBottom: 16, position: "relative", overflow: "hidden" }}>
              <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, transparent 40%, rgba(37,99,235,0.15) 100%)" }} />
              {/* Corner brackets */}
              {[["0", "0"], ["0", "auto"], ["auto", "0"], ["auto", "auto"]].map(([t, r], i) => (
                <div key={i} style={{ position: "absolute", top: t === "0" ? 16 : "auto", bottom: t === "auto" ? 16 : "auto", left: r === "0" ? 16 : "auto", right: r === "auto" ? 16 : "auto", width: 28, height: 28, borderTop: t === "0" ? `3px solid ${C.primary}` : "none", borderBottom: t === "auto" ? `3px solid ${C.primary}` : "none", borderLeft: r === "0" ? `3px solid ${C.primary}` : "none", borderRight: r === "auto" ? `3px solid ${C.primary}` : "none" }} />
              ))}
              {/* Scan line animation */}
              <div style={{ position: "absolute", left: 20, right: 20, height: 2, background: `linear-gradient(90deg, transparent, ${C.primary}, transparent)`, top: "40%", animation: "scanline 2s ease-in-out infinite" }} />
              <style>{`@keyframes scanline { 0%,100%{top:25%} 50%{top:70%} }`}</style>
              <div style={{ color: "#ffffff66", fontSize: 13, zIndex: 1 }}>Point camera at QR code</div>
              <div style={{ color: "#ffffff33", fontSize: 11, marginTop: 4, zIndex: 1 }}>Camera access not available in browser</div>
            </div>
            {/* Manual input */}
            <div style={{ color: C.textSub, fontSize: 12, fontWeight: 600, marginBottom: 8 }}>OR ENTER BOOKING ID MANUALLY</div>
            <div style={{ display: "flex", gap: 8 }}>
              <input value={input} onChange={e => setInput(e.target.value)} onKeyDown={e => e.key === "Enter" && scan()}
                placeholder="e.g. KT2024001" style={{ ...inpStyle, flex: 1, fontFamily: "monospace", fontWeight: 700, textTransform: "uppercase" }} />
              <BtnPrimary onClick={scan} style={{ whiteSpace: "nowrap" }}>{scanning ? "..." : "Search →"}</BtnPrimary>
            </div>
            <div style={{ color: C.textMuted, fontSize: 11, marginTop: 8 }}>Enter a real booking reference e.g. KTB-2027-XXXXX</div>
          </div>

          {/* Recent Scans */}
          <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 20, boxShadow: C.shadow }}>
            <div style={{ color: C.text, fontWeight: 700, fontSize: 13, marginBottom: 14 }}>Recent Check-ins Today</div>
            {recentScans.length === 0 && <div style={{ color: C.textMuted, fontSize: 13 }}>No check-ins yet today</div>}
            {recentScans.map((s, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 10, padding: "9px 0", borderBottom: i < recentScans.length - 1 ? `1px solid ${C.border}` : "none" }}>
                <div style={{ width: 32, height: 32, borderRadius: "50%", background: C.greenLight, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 14 }}></div>
                <div style={{ flex: 1 }}>
                  <div style={{ color: C.text, fontSize: 13, fontWeight: 600 }}>{s.guest}</div>
                  <div style={{ color: C.textMuted, fontSize: 11 }}>{s.id} · {s.tent}</div>
                </div>
                <div style={{ textAlign: "right" }}>
                  <div style={{ color: C.green, fontSize: 12, fontWeight: 700 }}>{s.action}</div>
                  <div style={{ color: C.textMuted, fontSize: 11 }}>{s.time}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Result Panel */}
        <div>
          {!result && !notFound && (
            <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `2px dashed ${C.border}`, borderRadius: 24, padding: 40, textAlign: "center", height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
              <div style={{ fontSize: 48, marginBottom: 12 }}></div>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 15, marginBottom: 6 }}>No Booking Scanned</div>
              <div style={{ color: C.textMuted, fontSize: 13 }}>Scan a QR code or enter a booking ID to view guest details and check them in</div>
            </div>
          )}
          {notFound && (
            <div style={{ background: C.redLight, border: `1px solid ${C.red}33`, borderRadius: 24, padding: 32, textAlign: "center" }}>
              <div style={{ fontSize: 40, marginBottom: 12 }}></div>
              <div style={{ color: C.red, fontWeight: 800, fontSize: 16, marginBottom: 6 }}>Booking Not Found</div>
              <div style={{ color: C.red + "aa", fontSize: 13 }}>No booking matches "{input}". Please check the ID and try again.</div>
            </div>
          )}
          {result && (
            <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, overflow: "hidden", boxShadow: C.shadow }}>
              <div style={{ height: 5, background: classC }} />
              <div style={{ padding: 22 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
                  <div>
                    <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 700, textTransform: "uppercase" }}>Booking Found</div>
                    <div style={{ color: classC, fontFamily: "monospace", fontWeight: 800, fontSize: 18 }}>{result.id}</div>
                  </div>
                  <Badge status={result.status} />
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 10, background: C.bg, borderRadius: 10, padding: "12px 14px", marginBottom: 16 }}>
                  <Avatar name={result.guest} size={44} />
                  <div>
                    <div style={{ color: C.text, fontWeight: 800, fontSize: 16 }}>{result.guest}</div>
                    <div style={{ color: C.textSub, fontSize: 13 }}>{result.phone}</div>
                  </div>
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 16 }}>
                  {[["Tent", result.tent], ["Guests", result.guests], ["Check-in", result.checkIn], ["Check-out", result.checkOut], ["Nights", result.nights], ["Paid", `₹${result.amount.toLocaleString("en-IN")}`]].map(([l, v]) => (
                    <div key={l} style={{ background: C.bg, borderRadius: 8, padding: "10px 12px" }}>
                      <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 600 }}>{l}</div>
                      <div style={{ color: C.text, fontSize: 13, fontWeight: 700, marginTop: 2 }}>{v}</div>
                    </div>
                  ))}
                </div>
                <div style={{ display: "flex", alignItems: "center", justifyContent: "center", marginBottom: 16 }}>
                  <QRCode value={result.qr} size={100} />
                </div>
                {result.status === "checked_in" ? (
                  <div style={{ background: C.greenLight, border: `1px solid ${C.green}44`, borderRadius: 10, padding: "14px", textAlign: "center", color: C.green, fontWeight: 800, fontSize: 15 }}>
                    Guest Already Checked In
                  </div>
                ) : result.status === "confirmed" ? (
                  <ButtonSoftGlow tone="green" fullWidth onClick={async () => {
                    await apiPut(`/admin/bookings/${result.id}/status`, { status: "checked_in" });
                    const now = new Date().toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" });
                    setRecentScans([{ id: result.id, guest: result.guest, tent: result.tent, time: now, action: "Checked In" }, ...recentScans.slice(0, 4)]);
                    setResult({ ...result, status: "checked_in" });
                  }}>Check In Guest</ButtonSoftGlow>
                ) : (
                  <div style={{ background: C.amberLight, border: `1px solid ${C.amber}44`, borderRadius: 10, padding: "14px", textAlign: "center", color: C.amber, fontWeight: 700, fontSize: 13 }}>
                    Booking status is "{result.status}" — cannot check in
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};



// ─── Change Username Sub-component ───────────────────────────────
const ChangeUsername = ({ currentUsername }) => {
  const [newUsername, setNewUsername] = useState("");
  const [password, setPassword] = useState("");
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(false);

  const change = async () => {
    if (!newUsername || !password) { setStatus({ type: "error", msg: "All fields are required" }); return; }
    if (newUsername.length < 3) { setStatus({ type: "error", msg: "Username must be at least 3 characters" }); return; }
    if (newUsername === currentUsername) { setStatus({ type: "error", msg: "New username is same as current" }); return; }
    setLoading(true); setStatus(null);
    try {
      const res = await fetch(`${API_BASE}/auth/admin/change-username`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
        body: JSON.stringify({ current_username: currentUsername, new_username: newUsername, password }),
      });
      const data = await res.json();
      if (res.ok) {
        setStatus({ type: "success", msg: "Username changed! Please login again." });
        localStorage.setItem("admin_username", newUsername);
        setNewUsername(""); setPassword("");
        setTimeout(() => { localStorage.removeItem("admin_token"); window.location.reload(); }, 2000);
      } else {
        setStatus({ type: "error", msg: data.error || "Failed to change username" });
      }
    } catch (e) {
      setStatus({ type: "error", msg: "Cannot connect to server" });
    }
    setLoading(false);
  };

  return (
    <div>
      {status && (
        <div style={{ background: status.type === "success" ? C.greenLight : C.redLight, border: `1px solid ${status.type === "success" ? C.green : C.red}33`, color: status.type === "success" ? C.green : C.red, borderRadius: 8, padding: "10px 14px", marginBottom: 14, fontSize: 13, fontWeight: 600 }}>
          {status.type === "success" ? "" : ""} {status.msg}
        </div>
      )}
      <div style={{ background: C.bg, borderRadius: 8, padding: "10px 14px", marginBottom: 14, fontSize: 13 }}>
        <span style={{ color: C.textSub }}>Current username: </span>
        <span style={{ color: C.purple, fontWeight: 700, fontFamily: "monospace" }}>{currentUsername}</span>
      </div>
      <FormField label="New Username">
        <input style={inpStyle} placeholder="Enter new username (min 3 chars)" value={newUsername} onChange={e => setNewUsername(e.target.value.toLowerCase().replace(/\s/g, ""))} />
      </FormField>
      <FormField label="Confirm with Password">
        <input style={inpStyle} type="password" placeholder="Enter your current password" value={password} onChange={e => setPassword(e.target.value)} onKeyDown={e => e.key === "Enter" && change()} />
      </FormField>
      <ButtonSoftGlow onClick={change} disabled={loading} tone="purple" fullWidth>{loading ? "Changing..." : "Change Username"}</ButtonSoftGlow>
    </div>
  );
};

// ─── Settings ─────────────────────────────────────────────────────
// ─── Audit Log (Phase 7 QA pass) ────────────────────────────────────
//
// The general admin-mutation trail: tent/coupon edits, booking
// status changes, user block/unblock, KYC verification, and
// admin account changes. Refund-specific events have their own
// dedicated trail (see the "Audit Trail" section inside the
// Accounting modal on the Bookings page) — this is the cross-
// cutting view across everything else.
const AuditLog = () => {
  const [entries, setEntries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("all");

  useEffect(() => {
    apiGet("/admin/audit-log").then(d => { setEntries(d?.entries || []); setLoading(false); }).catch(() => setLoading(false));
  }, []);

  const actions = ["all", ...Array.from(new Set(entries.map(e => e.action)))];
  const filtered = filter === "all" ? entries : entries.filter(e => e.action === filter);
  const thS = { color: C.textSub, fontSize: 11, fontWeight: 700, padding: "10px 14px", textAlign: "left", textTransform: "uppercase", letterSpacing: 0.5, background: C.bg, borderBottom: `1px solid ${C.border}` };
  const tdS = { color: C.text, fontSize: 13, padding: "11px 14px", borderBottom: `1px solid ${C.border}` };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 4 }}>Audit Log</div>
      <div style={{ color: C.textMuted, fontSize: 13, marginBottom: 16 }}>Every sensitive admin action — tent/coupon edits, booking status changes, user moderation, and admin account changes.</div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, boxShadow: C.shadow }}>
        <div style={{ padding: "14px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", gap: 6, flexWrap: "wrap" }}>
          {actions.map(a => (
            <Chip key={a} active={filter === a} onClick={() => setFilter(a)}>{a === "all" ? "All" : a.replace(/_/g, " ")}</Chip>
          ))}
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["When", "Admin", "Action", "Target", "Details"].map(h => <th key={h} style={thS}>{h}</th>)}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={5} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>Loading...</td></tr>}
              {!loading && filtered.length === 0 && <tr><td colSpan={5} style={{ textAlign: "center", padding: 24, color: C.textMuted }}>No audit entries yet</td></tr>}
              {!loading && filtered.map((e, i) => (
                <tr key={i}>
                  <td style={{ ...tdS, color: C.textMuted, fontSize: 12 }}>{e.created_at}</td>
                  <td style={{ ...tdS, fontWeight: 600 }}>{e.admin_username || "—"}</td>
                  <td style={{ ...tdS, textTransform: "capitalize" }}>{e.action.replace(/_/g, " ")}</td>
                  <td style={{ ...tdS, fontFamily: "monospace", fontSize: 12 }}>{e.target_type ? `${e.target_type}:${e.target_id}` : "—"}</td>
                  <td style={{ ...tdS, color: C.textMuted, fontSize: 12 }}>{e.details || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

// ─── Admin Users (Phase 7 RBAC) ─────────────────────────────────────
const AdminUsersPanel = () => {
  const [admins, setAdmins] = useState([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState({ username: "", password: "", role: "staff" });
  const [status, setStatus] = useState(null);

  const load = () => {
    setLoading(true);
    apiGet("/auth/admin/list").then(d => { setAdmins(d?.admins || []); setLoading(false); }).catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const create = async () => {
    if (!form.username || !form.password) { setStatus({ type: "error", msg: "Username and password required" }); return; }
    const { ok, data: res } = await apiPost("/auth/admin/create", form);
    if (ok) {
      setStatus({ type: "success", msg: `Created ${form.username} (${form.role})` });
      setForm({ username: "", password: "", role: "staff" });
      load();
    } else {
      setStatus({ type: "error", msg: res.error || "Failed to create admin" });
    }
  };

  return (
    <div>
      {status && (
        <div style={{ background: status.type === "success" ? C.greenLight : C.redLight, color: status.type === "success" ? C.green : C.red, borderRadius: 8, padding: "8px 12px", marginBottom: 14, fontSize: 12, fontWeight: 600 }}>
          {status.msg}
        </div>
      )}
      <div style={{ marginBottom: 16 }}>
        {loading && <div style={{ color: C.textMuted, fontSize: 13 }}>Loading...</div>}
        {!loading && admins.map(a => (
          <div key={a.username} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "8px 0", borderBottom: `1px solid ${C.border}` }}>
            <div style={{ fontSize: 13, fontWeight: 600, color: C.text }}>{a.username}</div>
            <span style={{ background: a.role === "super_admin" ? C.primaryLight : C.bg, color: a.role === "super_admin" ? C.primary : C.textSub, padding: "2px 10px", borderRadius: 24, fontSize: 11, fontWeight: 700 }}>{a.role === "super_admin" ? "Super Admin" : "Staff"}</span>
          </div>
        ))}
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <input style={{ ...inpStyle, flex: 1 }} placeholder="Username" value={form.username} onChange={e => setForm({ ...form, username: e.target.value })} />
        <input style={{ ...inpStyle, flex: 1 }} type="password" placeholder="Password" value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} />
        <select style={{ ...inpStyle, width: 120 }} value={form.role} onChange={e => setForm({ ...form, role: e.target.value })}>
          <option value="staff">Staff</option>
          <option value="super_admin">Super Admin</option>
        </select>
      </div>
      <div style={{ marginTop: 10 }}><ButtonSoftGlow onClick={create} tone="primary" fullWidth>+ Create Admin Account</ButtonSoftGlow></div>
    </div>
  );
};

const Settings = () => {
  const [oldPass, setOldPass] = useState("");
  const [newPass, setNewPass] = useState("");
  const [confirmPass, setConfirmPass] = useState("");
  const [status, setStatus] = useState(null); // {type: 'success'|'error', msg: ''}
  const [loading, setLoading] = useState(false);
  const username = localStorage.getItem("admin_username") || "admin";

  const changePassword = async () => {
    if (!oldPass || !newPass || !confirmPass) { setStatus({ type: "error", msg: "All fields are required" }); return; }
    if (newPass !== confirmPass) { setStatus({ type: "error", msg: "New passwords do not match" }); return; }
    if (newPass.length < 6) { setStatus({ type: "error", msg: "New password must be at least 6 characters" }); return; }
    setLoading(true); setStatus(null);
    try {
      const res = await fetch(`${API_BASE}/auth/admin/change-password`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${localStorage.getItem("admin_token")}` },
        body: JSON.stringify({ username, old_password: oldPass, new_password: newPass }),
      });
      const data = await res.json();
      if (res.ok) {
        setStatus({ type: "success", msg: "Password changed successfully! Please login again." });
        setOldPass(""); setNewPass(""); setConfirmPass("");
        setTimeout(() => { localStorage.removeItem("admin_token"); window.location.reload(); }, 2000);
      } else {
        setStatus({ type: "error", msg: data.error || "Failed to change password" });
      }
    } catch (e) {
      setStatus({ type: "error", msg: "Cannot connect to server" });
    }
    setLoading(false);
  };

  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 6 }}>Settings</div>
      <div style={{ color: C.textSub, fontSize: 13, marginBottom: 24 }}>Manage your admin account</div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        {/* Change Password */}
        <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 24, boxShadow: C.shadow }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
            <div style={{ background: C.primaryLight, borderRadius: 10, padding: "8px 10px", fontSize: 18 }}></div>
            <div>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>Change Password</div>
              <div style={{ color: C.textMuted, fontSize: 12 }}>Update your admin password</div>
            </div>
          </div>

          {status && (
            <div style={{ background: status.type === "success" ? C.greenLight : C.redLight, border: `1px solid ${status.type === "success" ? C.green : C.red}33`, color: status.type === "success" ? C.green : C.red, borderRadius: 8, padding: "10px 14px", marginBottom: 16, fontSize: 13, fontWeight: 600 }}>
              {status.type === "success" ? "" : ""} {status.msg}
            </div>
          )}

          <FormField label="Current Password">
            <input style={inpStyle} type="password" placeholder="Enter current password" value={oldPass} onChange={e => setOldPass(e.target.value)} />
          </FormField>
          <FormField label="New Password">
            <input style={inpStyle} type="password" placeholder="Enter new password (min 6 chars)" value={newPass} onChange={e => setNewPass(e.target.value)} />
          </FormField>
          <FormField label="Confirm New Password">
            <input style={inpStyle} type="password" placeholder="Confirm new password" value={confirmPass} onChange={e => setConfirmPass(e.target.value)} onKeyDown={e => e.key === "Enter" && changePassword()} />
          </FormField>

          <div style={{ marginTop: 4 }}>
            <ButtonSoftGlow onClick={changePassword} disabled={loading} tone="primary" fullWidth>{loading ? "Changing..." : "Change Password"}</ButtonSoftGlow>
          </div>
        </div>

        {/* Account Info + Change Username */}
        <div>
          <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 24, boxShadow: C.shadow, marginBottom: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
              <div style={{ background: C.primaryLight, borderRadius: 10, padding: "8px 10px", fontSize: 18 }}></div>
              <div>
                <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>Account Info</div>
                <div style={{ color: C.textMuted, fontSize: 12 }}>Your admin account details</div>
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 12, background: C.bg, borderRadius: 10, padding: "14px 16px", marginBottom: 14 }}>
              <Avatar name={username} size={44} />
              <div>
                <div style={{ color: C.text, fontWeight: 800, fontSize: 16 }}>{username}</div>
                <div style={{ color: C.primary, fontSize: 12, fontWeight: 600 }}>{isSuperAdmin() ? "Super Admin" : "Staff"}</div>
              </div>
            </div>
            {[["Role", isSuperAdmin() ? "Super Admin" : "Staff"], ["Access", isSuperAdmin() ? "Full access — can approve refunds, reverse expenses, issue notes" : "Standard — approvals require super admin"], ["Auth", "JWT Token"]].map(([l, v]) => (
              <div key={l} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: `1px solid ${C.border}` }}>
                <div style={{ color: C.textSub, fontSize: 13 }}>{l}</div>
                <div style={{ color: C.text, fontSize: 13, fontWeight: 600 }}>{v}</div>
              </div>
            ))}
          </div>

          {/* Change Username */}
          <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 24, boxShadow: C.shadow, marginBottom: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
              <div style={{ background: "rgba(255,255,255,0.08)", border: `1px solid ${C.border}`, borderRadius: 10, padding: "8px 10px", fontSize: 18 }}></div>
              <div>
                <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>Change Username</div>
                <div style={{ color: C.textMuted, fontSize: 12 }}>Update your login username</div>
              </div>
            </div>
            <ChangeUsername currentUsername={username} />
          </div>

          {isSuperAdmin() && (
            <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", border: `1px solid ${C.border}`, borderRadius: 24, padding: 24, boxShadow: C.shadow, marginBottom: 16 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
                <div style={{ background: C.greenLight, borderRadius: 10, padding: "8px 10px", fontSize: 18 }}></div>
                <div>
                  <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>Admin Users</div>
                  <div style={{ color: C.textMuted, fontSize: 12 }}>Super admin only — manage who can approve refunds and issue notes</div>
                </div>
              </div>
              <AdminUsersPanel />
            </div>
          )}

          {/* Security Tips */}
          <div style={{ background: C.amberLight, border: `1px solid ${C.amber}33`, borderRadius: 24, padding: 20 }}>
            <div style={{ color: C.amber, fontWeight: 700, fontSize: 13, marginBottom: 10 }}>Security Tips</div>
            {["Use a strong password with letters, numbers & symbols", "Change your password regularly", "Never share your admin credentials", "Always logout after your session"].map(t => (
              <div key={t} style={{ color: C.amber + "cc", fontSize: 12, marginBottom: 6, display: "flex", gap: 6 }}>
                <span>•</span><span>{t}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

// ─── App Root ─────────────────────────────────────────────────────
// ─── Refunds ─────────────────────────────────────────────────────
// Approval queue. A cancelled booking creates a refund in
// 'awaiting_approval'; nothing reaches Razorpay until someone
// approves it here.
const REFUND_STATUS_META = {
  awaiting_approval: { color: "#3730a3", bg: "#eef2ff", label: "Awaiting approval" },
  pending:           { color: C.amber,   bg: C.amberLight, label: "Queued" },
  processing:        { color: C.amber,   bg: C.amberLight, label: "Processing" },
  succeeded:         { color: C.green,   bg: C.greenLight, label: "Refunded" },
  failed:            { color: C.red,     bg: C.redLight,   label: "Gateway failed" },
  manual:            { color: C.purple,  bg: C.purpleLight, label: "Manual payout" },
  rejected:          { color: C.red,     bg: C.redLight,   label: "Rejected" },
  not_applicable:    { color: C.textMuted, bg: "#f9fafb",  label: "No refund due" },
};

const RefundBadge = ({ status }) => {
  const m = REFUND_STATUS_META[status] || { color: C.textMuted, bg: "#f9fafb", label: status || "—" };
  return (
    <span style={{ background: m.bg, color: m.color, padding: "3px 10px", borderRadius: 24, fontSize: 11, fontWeight: 700, whiteSpace: "nowrap" }}>
      {m.label}
    </span>
  );
};

const Refunds = () => {
  const [data, setData] = useState({ refunds: [], outstanding: 0, awaiting_approval: 0, awaiting_amount: 0 });
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("awaiting_approval");
  const [busy, setBusy] = useState("");        // booking_ref being acted on
  const [notice, setNotice] = useState(null);  // { kind, text }
  const [rejecting, setRejecting] = useState(null); // refund row
  const [approving, setApproving] = useState(null); // refund row
  const [reason, setReason] = useState("");

  const load = () => {
    setLoading(true);
    apiGet("/admin/refunds")
      .then(d => { setData(d || {}); setLoading(false); })
      .catch(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const admin = localStorage.getItem("admin_username") || "admin";

  // Approval now carries a mandatory justification, same bar as
  // rejection — the backend rejects a blank reason, so the button
  // opens a modal instead of firing straight away.
  const doApprove = async () => {
    if (!reason.trim()) return;
    const r = approving;
    setBusy(r.booking_ref); setNotice(null);
    const { ok, data: res } = await apiPost(`/admin/refunds/${r.booking_ref}/approve`, { reason: reason.trim(), reviewer: admin });
    setBusy(""); setApproving(null); setReason("");
    setNotice(ok
      ? { kind: "ok", text: `Approved ${fmt(r.refund_amount)} for ${r.booking_ref}.` }
      : { kind: "err", text: res.error || "Approval failed" });
    load();
  };

  const doReject = async () => {
    if (!reason.trim()) return;
    const r = rejecting;
    setBusy(r.booking_ref); setNotice(null);
    const { ok, data: res } = await apiPost(`/admin/refunds/${r.booking_ref}/reject`, { reason: reason.trim(), reviewer: admin });
    setBusy(""); setRejecting(null); setReason("");
    setNotice(ok
      ? { kind: "ok", text: `Rejected refund for ${r.booking_ref}.` }
      : { kind: "err", text: res.error || "Rejection failed" });
    load();
  };

  const retry = async (r) => {
    setBusy(r.booking_ref); setNotice(null);
    const { ok, data: res } = await apiPost(`/admin/refunds/${r.booking_ref}/retry`, {});
    setBusy("");
    setNotice(ok ? { kind: "ok", text: `Retry queued for ${r.booking_ref}.` } : { kind: "err", text: res.error || "Retry failed" });
    load();
  };

  const settle = async (r) => {
    const ref = window.prompt("Settlement reference (bank UTR, cash receipt no.):", "");
    if (!ref) return;
    setBusy(r.booking_ref); setNotice(null);
    const { ok, data: res } = await apiPost(`/admin/refunds/${r.booking_ref}/settle`, { reference: ref, note: `settled by ${admin}` });
    setBusy("");
    setNotice(ok ? { kind: "ok", text: `Marked ${r.booking_ref} settled.` } : { kind: "err", text: res.error || "Settle failed" });
    load();
  };

  const all = data.refunds || [];
  const rows = filter === "all" ? all : all.filter(r => r.status === filter);
  const counts = all.reduce((a, r) => { a[r.status] = (a[r.status] || 0) + 1; return a; }, {});

  const FILTERS = [
    { id: "awaiting_approval", label: "Awaiting approval" },
    { id: "pending", label: "Queued" },
    { id: "failed", label: "Failed" },
    { id: "manual", label: "Manual" },
    { id: "succeeded", label: "Refunded" },
    { id: "rejected", label: "Rejected" },
    { id: "all", label: "All" },
  ];

  return (
    <div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))", gap: 16, marginBottom: 20 }}>
        <StatCard icon="" label="Awaiting approval" value={data.awaiting_approval || 0} sub={fmt(data.awaiting_amount || 0)} color={C.purple} />
        <StatCard icon="" label="Outstanding" value={fmt(data.outstanding || 0)} sub="not yet paid out" color={C.amber} />
        <StatCard icon="" label="Total refunds" value={all.length} sub={data.requires_approval ? "approval required" : "auto-approved"} color={C.primary} />
      </div>

      {data.active_policy && (
        <div style={{ background: C.primaryLight, border: `1px solid ${C.border}`, borderRadius: 10, padding: "10px 14px", marginBottom: 16, fontSize: 12, color: C.textSub }}>
          <b style={{ color: C.text }}>Active policy:</b> {data.active_policy}
        </div>
      )}

      {notice && (
        <div style={{
          background: notice.kind === "ok" ? C.greenLight : C.redLight,
          color: notice.kind === "ok" ? C.green : C.red,
          border: `1px solid ${notice.kind === "ok" ? C.green : C.red}22`,
          borderRadius: 10, padding: "10px 14px", marginBottom: 16, fontSize: 13, fontWeight: 600,
        }}>
          {notice.text}
        </div>
      )}

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        {FILTERS.map(f => (
          <Chip key={f.id} active={filter === f.id} onClick={() => setFilter(f.id)}>
            {f.label}{f.id !== "all" && counts[f.id] ? ` (${counts[f.id]})` : ""}
          </Chip>
        ))}
        <div style={{ marginLeft: "auto" }}><GlassButton onClick={load}>↻ Refresh</GlassButton></div>
      </div>

      <div style={{ background: C.white, backdropFilter: "blur(26px) saturate(190%) brightness(1.12)", WebkitBackdropFilter: "blur(26px) saturate(190%) brightness(1.12)", borderRadius: 12, boxShadow: C.shadow, overflow: "hidden" }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: "center", color: C.textSub }}>Loading refunds…</div>
        ) : rows.length === 0 ? (
          <div style={{ padding: 40, textAlign: "center", color: C.textSub }}>
            {filter === "awaiting_approval" ? "Nothing waiting for approval " : "No refunds in this state."}
          </div>
        ) : (
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13, minWidth: 880 }}>
              <thead>
                <tr style={{ background: "rgba(255,255,255,0.04)", borderBottom: `1px solid ${C.border}` }}>
                  {["Booking", "Guest", "Amount", "Policy", "Status", "Requested", "Actions"].map(h => (
                    <th key={h} style={{ textAlign: "left", padding: "12px 14px", fontSize: 11, fontWeight: 700, color: C.textSub, textTransform: "uppercase", letterSpacing: 0.4 }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map(r => (
                  <tr key={r.id} style={{ borderBottom: `1px solid ${C.border}` }}>
                    <td style={{ padding: "12px 14px", fontWeight: 700, color: C.text }}>
                      {r.booking_ref}
                      <div style={{ fontWeight: 400, color: C.textMuted, fontSize: 11 }}>{r.tent_name || "—"}</div>
                    </td>
                    <td style={{ padding: "12px 14px", color: C.textSub }}>{r.phone}</td>
                    <td style={{ padding: "12px 14px", fontWeight: 700, color: C.text }}>
                      {fmt(r.refund_amount)}
                      {r.fee_paise > 0 && <div style={{ fontWeight: 400, color: C.textMuted, fontSize: 11 }}>fee {fmt(r.fee_paise / 100)}</div>}
                    </td>
                    <td style={{ padding: "12px 14px", color: C.textSub, fontSize: 11 }}>{r.policy_rule || "—"}</td>
                    <td style={{ padding: "12px 14px" }}>
                      <RefundBadge status={r.status} />
                      {r.status === "failed" && r.last_error && (
                        <div title={r.last_error} style={{ color: C.red, fontSize: 10, marginTop: 4, maxWidth: 220, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                          {r.last_error}
                        </div>
                      )}
                      {r.status === "rejected" && r.rejection_reason && (
                        <div style={{ color: C.textMuted, fontSize: 10, marginTop: 4 }}>{r.rejection_reason}</div>
                      )}
                      {r.status !== "rejected" && r.approval_reason && (
                        <div style={{ color: C.textMuted, fontSize: 10, marginTop: 4 }}>{r.approval_reason}</div>
                      )}
                      {r.reviewed_by && (
                        <div style={{ color: C.textMuted, fontSize: 10, marginTop: 4 }}>by {r.reviewed_by}</div>
                      )}
                    </td>
                    <td style={{ padding: "12px 14px", color: C.textSub, fontSize: 11 }}>
                      {r.requested_at ? new Date(r.requested_at).toLocaleString("en-IN") : "—"}
                    </td>
                    <td style={{ padding: "12px 14px" }}>
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                        {r.status === "awaiting_approval" && (isSuperAdmin() ? (
                          <>
                            <RowAction disabled={busy === r.booking_ref} onClick={() => { setApproving(r); setReason(""); }} tone="green">✓ Approve</RowAction>
                            <RowAction disabled={busy === r.booking_ref} onClick={() => { setRejecting(r); setReason(""); }} tone="red">✕ Reject</RowAction>
                          </>
                        ) : (
                          <span style={{ color: C.textMuted, fontSize: 11 }}>Requires super admin</span>
                        ))}
                        {r.status === "failed" && (
                          <RowAction disabled={busy === r.booking_ref} onClick={() => retry(r)} tone="primary">↻ Retry</RowAction>
                        )}
                        {(r.status === "manual" || r.status === "failed") && (
                          <RowAction disabled={busy === r.booking_ref} onClick={() => settle(r)} tone="purple">Mark settled</RowAction>
                        )}
                        {["succeeded", "rejected", "not_applicable", "pending", "processing"].includes(r.status) && (
                          <span style={{ color: C.textMuted, fontSize: 11 }}>—</span>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {approving && (
        <Modal title={`Approve refund — ${approving.booking_ref}`} onClose={() => { setApproving(null); setReason(""); }}>
          <p style={{ fontSize: 13, color: C.textSub, marginTop: 0 }}>
            Releasing {fmt(approving.refund_amount)} to {approving.phone}. The reason is stored on the
            refund, written to the audit trail, and carried into the ledger narration and the
            Outstanding &amp; Refund report. This cannot be undone.
          </p>
          <textarea
            value={reason}
            onChange={e => setReason(e.target.value)}
            placeholder="e.g. Cancelled 6 days before check-in; within free-cancellation window."
            rows={3}
            style={{ ...inpStyle, resize: "vertical", fontFamily: "inherit" }}
          />
          <div style={{ display: "flex", gap: 10, marginTop: 16, justifyContent: "flex-end" }}>
            <BtnSecondary onClick={() => { setApproving(null); setReason(""); }}>Cancel</BtnSecondary>
            <ButtonSoftGlow onClick={doApprove} disabled={!reason.trim()} tone="green">Approve refund</ButtonSoftGlow>
          </div>
        </Modal>
      )}

      {rejecting && (
        <Modal title={`Reject refund — ${rejecting.booking_ref}`} onClose={() => { setRejecting(null); setReason(""); }}>
          <p style={{ fontSize: 13, color: C.textSub, marginTop: 0 }}>
            Declining {fmt(rejecting.refund_amount)} for {rejecting.phone}. The customer is shown this reason,
            so write something they can act on. This cannot be undone.
          </p>
          <textarea
            value={reason}
            onChange={e => setReason(e.target.value)}
            placeholder="e.g. Cancelled after check-in date; outside refund policy."
            rows={3}
            style={{ ...inpStyle, resize: "vertical", fontFamily: "inherit" }}
          />
          <div style={{ display: "flex", gap: 10, marginTop: 16, justifyContent: "flex-end" }}>
            <BtnSecondary onClick={() => { setRejecting(null); setReason(""); }}>Cancel</BtnSecondary>
            <ButtonSoftGlow onClick={doReject} disabled={!reason.trim()} tone="red">Reject refund</ButtonSoftGlow>
          </div>
        </Modal>
      )}
    </div>
  );
};

const PAGES = { dashboard: Dashboard, tents: Tents, bookings: Bookings, users: Users, coupons: Coupons, refunds: Refunds, revenue: Revenue, finance: Finance, payments: PaymentTracking, expenses: Expenses, vendorpayables: VendorPayables, customerreceivables: CustomerReceivables, currency: Currency, reconciliation: Reconciliation, pnl: ProfitAndLoss, gst: GSTReport, invoices: Invoices, ledger: Ledger, bankaccounts: BankAccounts, reports: Reports, notifications: Notifications, inventory: Inventory, eticket: ETicket, qrscanner: QRScanner, auditlog: AuditLog, settings: Settings };

export default function App() {
  const [auth, setAuth] = useState(!!localStorage.getItem("admin_token"));
  const [page, setPage] = useState("dashboard");
  const Page = PAGES[page] || Dashboard;
  if (!auth) return <Login onLogin={(token) => setAuth(true)} />;
  return (
    <>
      <SiteBackground />
      <div style={{ position: "relative", zIndex: 1, fontFamily: "'Inter', sans-serif", minHeight: "100vh" }}>
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
      <Sidebar active={page} onNav={setPage} onLogout={() => { localStorage.removeItem("admin_token"); localStorage.removeItem("admin_username"); setAuth(false); setPage("dashboard"); }} />
      <div style={{ marginLeft: 230 }}>
        <TopBar page={page} />
        <main style={{ padding: "24px 28px" }}>
          <Page onNav={setPage} />
        </main>
      </div>
      </div>
    </>
  );
}
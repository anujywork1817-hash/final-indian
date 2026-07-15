import { useState, useEffect } from "react";

// ─── Design Tokens ───────────────────────────────────────────────
const C = {
  bg: "#f5f6fa",
  white: "#ffffff",
  border: "#e8eaed",
  borderDark: "#d1d5db",
  primary: "#2563eb",
  primaryLight: "#eff6ff",
  primaryDark: "#1d4ed8",
  green: "#16a34a",
  greenLight: "#f0fdf4",
  red: "#dc2626",
  redLight: "#fef2f2",
  amber: "#d97706",
  amberLight: "#fffbeb",
  purple: "#7c3aed",
  purpleLight: "#f5f3ff",
  text: "#111827",
  textSub: "#6b7280",
  textMuted: "#9ca3af",
  shadow: "0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04)",
  shadowMd: "0 4px 6px rgba(0,0,0,0.07), 0 2px 4px rgba(0,0,0,0.04)",
  shadowLg: "0 10px 15px rgba(0,0,0,0.08), 0 4px 6px rgba(0,0,0,0.04)",
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

// ─── Helpers ─────────────────────────────────────────────────────
const fmt = (n) => "₹" + n.toLocaleString("en-IN");

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
    <span style={{ background: m.bg, color: m.color, padding: "3px 10px", borderRadius: 20, fontSize: 11, fontWeight: 600, whiteSpace: "nowrap" }}>
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
  <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: "20px 22px", flex: 1, minWidth: 170, boxShadow: C.shadow }}>
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 14 }}>
      <div style={{ background: color + "15", borderRadius: 10, padding: "8px 10px", fontSize: 18 }}>{icon}</div>
      {trend && <div style={{ color: C.green, fontSize: 12, fontWeight: 600, background: C.greenLight, padding: "2px 8px", borderRadius: 20 }}>↑ {trend}</div>}
    </div>
    <div style={{ color: C.textSub, fontSize: 12, fontWeight: 500, marginBottom: 4 }}>{label}</div>
    <div style={{ color: C.text, fontSize: 24, fontWeight: 800, letterSpacing: -0.5 }}>{value}</div>
    {sub && <div style={{ color: C.textMuted, fontSize: 12, marginTop: 3 }}>{sub}</div>}
  </div>
);

// ─── Input style ─────────────────────────────────────────────────
const inpStyle = {
  background: C.white, border: `1px solid ${C.border}`, color: C.text,
  borderRadius: 8, padding: "9px 13px", fontSize: 13, width: "100%",
  boxSizing: "border-box", fontFamily: "inherit", outline: "none",
  transition: "border-color 0.15s",
};

// ─── Login ────────────────────────────────────────────────────────
const API_BASE = "https://kumbh-gateway.onrender.com/api/v1";

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
    <div style={{ minHeight: "100vh", background: C.bg, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "'Inter', sans-serif" }}>
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
      <div style={{ width: 400 }}>
        {/* Header */}
        <div style={{ textAlign: "center", marginBottom: 28 }}>
          <img src="/logo.svg" alt="Kumbh Tent" style={{ height: 64, marginBottom: 10 }} />
          <div style={{ color: C.textSub, fontSize: 14, marginTop: 4 }}>Sign in to manage your dashboard</div>
        </div>
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 18, padding: "32px 28px", boxShadow: C.shadowLg }}>
          <div style={{ marginBottom: 16 }}>
            <label style={{ color: C.text, fontSize: 13, fontWeight: 600, display: "block", marginBottom: 6 }}>Username</label>
            <input style={inpStyle} placeholder="Enter username" value={user} onChange={e => setUser(e.target.value)} />
          </div>
          <div style={{ marginBottom: 20 }}>
            <label style={{ color: C.text, fontSize: 13, fontWeight: 600, display: "block", marginBottom: 6 }}>Password</label>
            <input style={inpStyle} type="password" placeholder="Enter password" value={pass} onChange={e => setPass(e.target.value)} onKeyDown={e => e.key === "Enter" && attempt()} />
          </div>
          {err && <div style={{ background: C.redLight, color: C.red, borderRadius: 8, padding: "9px 13px", fontSize: 13, marginBottom: 14, fontWeight: 500 }}>⚠ {err}</div>}
          <button onClick={attempt} disabled={loading} style={{ width: "100%", background: loading ? C.textMuted : C.primary, color: "#fff", border: "none", borderRadius: 10, padding: "12px", fontSize: 14, fontWeight: 700, cursor: loading ? "not-allowed" : "pointer", fontFamily: "inherit", boxShadow: `0 4px 12px ${C.primary}40`, transition: "background 0.15s" }}
            onMouseEnter={e => { if (!loading) e.currentTarget.style.background = C.primaryDark; }}
            onMouseLeave={e => { if (!loading) e.currentTarget.style.background = C.primary; }}>
            {loading ? "Signing in..." : "Sign In →"}
          </button>
        </div>
      </div>
    </div>
  );
};

// ─── Sidebar ──────────────────────────────────────────────────────
const NAV = [
  { id: "dashboard", icon: "▦", label: "Dashboard" },
  { id: "tents", icon: "⛺", label: "Tents" },
  { id: "bookings", icon: "📋", label: "Bookings" },
  { id: "users", icon: "👥", label: "Users" },
  { id: "coupons", icon: "🎟", label: "Coupons" },
  { id: "revenue", icon: "📈", label: "Revenue" },
  { id: "notifications", icon: "🔔", label: "Notifications" },
  { id: "inventory", icon: "📦", label: "Inventory" },
  { id: "eticket", icon: "🎫", label: "E-Tickets" },
  { id: "qrscanner", icon: "📷", label: "QR Check-in" },
  { id: "settings", icon: "⚙️", label: "Settings" },
];

const Sidebar = ({ active, onNav, onLogout }) => (
  <div style={{ width: 230, background: C.white, borderRight: `1px solid ${C.border}`, display: "flex", flexDirection: "column", minHeight: "100vh", position: "fixed", left: 0, top: 0, boxShadow: "1px 0 0 #e8eaed" }}>
    {/* Logo */}
    <div style={{ padding: "16px 20px", borderBottom: `1px solid ${C.border}` }}>
      <img src="/logo.svg" alt="Kumbh Tent" style={{ height: 44, width: "auto" }} />
      <div style={{ color: C.primary, fontSize: 10, fontWeight: 700, letterSpacing: 1, marginTop: 6, textTransform: "uppercase" }}>Admin Panel</div>
    </div>
    {/* Nav */}
    <nav style={{ flex: 1, padding: "12px 10px" }}>
      <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 700, letterSpacing: 0.8, padding: "4px 10px 8px", textTransform: "uppercase" }}>Main Menu</div>
      {NAV.map(n => (
        <button key={n.id} onClick={() => onNav(n.id)} style={{
          width: "100%", display: "flex", alignItems: "center", gap: 10, padding: "9px 12px",
          background: active === n.id ? C.primaryLight : "transparent",
          border: "none", borderRadius: 9,
          color: active === n.id ? C.primary : C.textSub,
          fontSize: 13, fontWeight: active === n.id ? 700 : 500,
          cursor: "pointer", marginBottom: 1, textAlign: "left",
          transition: "all 0.12s", fontFamily: "inherit",
        }}
          onMouseEnter={e => { if (active !== n.id) { e.currentTarget.style.background = C.bg; e.currentTarget.style.color = C.text; } }}
          onMouseLeave={e => { if (active !== n.id) { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = C.textSub; } }}
        >
          <span style={{ fontSize: 15, width: 20, textAlign: "center" }}>{n.icon}</span>
          {n.label}
          {active === n.id && <div style={{ marginLeft: "auto", width: 5, height: 5, borderRadius: "50%", background: C.primary }} />}
        </button>
      ))}
    </nav>
    {/* User */}
    <div style={{ padding: "12px 10px", borderTop: `1px solid ${C.border}` }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 10px", background: C.bg, borderRadius: 10, marginBottom: 6 }}>
        <Avatar name="Admin User" size={30} />
        <div>
          <div style={{ color: C.text, fontSize: 12, fontWeight: 700 }}>Admin User</div>
          <div style={{ color: C.textMuted, fontSize: 10 }}>Super Admin</div>
        </div>
      </div>
      <button onClick={onLogout} style={{ width: "100%", padding: "8px 12px", background: "transparent", border: `1px solid ${C.border}`, borderRadius: 8, color: C.red, fontSize: 12, fontWeight: 600, cursor: "pointer", textAlign: "left", fontFamily: "inherit", display: "flex", alignItems: "center", gap: 6 }}>
        🚪 Sign Out
      </button>
    </div>
  </div>
);

// ─── Top Bar ──────────────────────────────────────────────────────
const TopBar = ({ page }) => (
  <div style={{ height: 60, background: C.white, borderBottom: `1px solid ${C.border}`, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 28px", position: "sticky", top: 0, zIndex: 10 }}>
    <div>
      <div style={{ color: C.text, fontSize: 16, fontWeight: 700, textTransform: "capitalize" }}>{page}</div>
      <div style={{ color: C.textMuted, fontSize: 11 }}>{new Date().toLocaleDateString("en-IN", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}</div>
    </div>
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{ background: C.greenLight, color: C.green, padding: "4px 10px", borderRadius: 20, fontSize: 11, fontWeight: 600 }}>● All Systems Online</div>
      <div style={{ width: 34, height: 34, background: C.primaryLight, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 15, cursor: "pointer" }}>🔔</div>
    </div>
  </div>
);

// ─── Modal ────────────────────────────────────────────────────────
const Modal = ({ title, onClose, children }) => (
  <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.3)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100, backdropFilter: "blur(4px)" }}>
    <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 18, padding: 28, width: 420, boxShadow: C.shadowLg, maxHeight: "90vh", overflowY: "auto" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 22 }}>
        <div style={{ color: C.text, fontWeight: 800, fontSize: 17 }}>{title}</div>
        <button onClick={onClose} style={{ background: C.bg, border: `1px solid ${C.border}`, borderRadius: 8, width: 30, height: 30, cursor: "pointer", fontSize: 14, color: C.textSub, display: "flex", alignItems: "center", justifyContent: "center" }}>✕</button>
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

const BtnPrimary = ({ onClick, children, style = {} }) => (
  <button onClick={onClick} style={{ background: C.primary, color: "#fff", border: "none", borderRadius: 9, padding: "10px 18px", fontWeight: 700, cursor: "pointer", fontSize: 13, fontFamily: "inherit", ...style }}>{children}</button>
);
const BtnSecondary = ({ onClick, children, style = {} }) => (
  <button onClick={onClick} style={{ background: C.white, color: C.textSub, border: `1px solid ${C.border}`, borderRadius: 9, padding: "10px 18px", fontWeight: 600, cursor: "pointer", fontSize: 13, fontFamily: "inherit", ...style }}>{children}</button>
);

// ─── Dashboard ────────────────────────────────────────────────────
const Dashboard = ({ onNav }) => {
  const [stats, setStats] = useState({ total_bookings: 0, active_bookings: 0, total_revenue: 0, today_revenue: 0, total_users: 0 });
  const [revenue, setRevenue] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);

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
        <button onClick={() => { setLoading(true); load(); }} style={{ background: C.primaryLight, color: C.primary, border: `1px solid ${C.primary}33`, borderRadius: 10, padding: "8px 16px", fontSize: 13, fontWeight: 700, cursor: "pointer", fontFamily: "inherit" }}>
          🔄 Refresh
        </button>
      </div>
      {/* Stats Row */}
      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", marginBottom: 22 }}>
        <StatCard icon="📋" label="Total Bookings" value={stats.total_bookings} sub={`${stats.active_bookings} currently active`} trend="12%" color={C.primary} />
        <StatCard icon="💰" label="Total Revenue" value={fmt(stats.total_revenue || 0)} sub={`${fmt(stats.today_revenue || 0)} today`} trend="8%" color={C.green} />
        <StatCard icon="👥" label="Total Users" value={stats.total_users || 0} sub="Registered users" trend="5%" color={C.purple} />
        <StatCard icon="🏕" label="Active Bookings" value={stats.active_bookings || 0} sub="Confirmed & checked in" color={C.amber} />
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1.6fr 1fr", gap: 16, marginBottom: 16 }}>
        {/* Revenue Chart */}
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 22, boxShadow: C.shadow }}>
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

        {/* Tent split */}
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 22, boxShadow: C.shadow }}>
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
      </div>

      {/* Recent Bookings */}
      <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, boxShadow: C.shadow }}>
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
            <div key={t.id} style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, overflow: "hidden", boxShadow: C.shadow }}>
              {/* Header band */}
              <div style={{ height: 6, background: cc }} />
              <div style={{ padding: 20 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 14 }}>
                  <div>
                    <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>{t.name}</div>
                    <span style={{ background: cc + "15", color: cc, padding: "2px 8px", borderRadius: 20, fontSize: 11, fontWeight: 700 }}>{t.class.toUpperCase()}</span>
                  </div>
                  <Badge status={t.active ? "active" : "inactive"} />
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 16 }}>
                  {[["Price/Night", fmt(t.price)], ["Units", t.units], ["Rating", `⭐ ${t.rating}`], ["Bookings", t.bookings]].map(([l, v]) => (
                    <div key={l} style={{ background: C.bg, borderRadius: 8, padding: "8px 12px" }}>
                      <div style={{ color: C.textMuted, fontSize: 10, fontWeight: 600, textTransform: "uppercase" }}>{l}</div>
                      <div style={{ color: C.text, fontSize: 14, fontWeight: 700, marginTop: 2 }}>{v}</div>
                    </div>
                  ))}
                </div>
                <div style={{ display: "flex", gap: 8 }}>
                  <button onClick={() => openEdit(t)}
                    style={{ flex: 1, background: C.primaryLight, color: C.primary, border: "none", borderRadius: 8, padding: "8px", fontSize: 12, fontWeight: 700, cursor: "pointer", fontFamily: "inherit" }}>
                    ✏️ Edit
                  </button>
                  <button onClick={() => setTents(tents.map(x => x.id === t.id ? { ...x, active: !x.active } : x))}
                    style={{ flex: 1, background: t.active ? C.redLight : C.greenLight, color: t.active ? C.red : C.green, border: "none", borderRadius: 8, padding: "8px", fontSize: 12, fontWeight: 700, cursor: "pointer", fontFamily: "inherit" }}>
                    {t.active ? "Deactivate" : "Activate"}
                  </button>
                  <button onClick={() => setTents(tents.filter(x => x.id !== t.id))}
                    style={{ flex: 1, background: C.bg, color: C.textSub, border: `1px solid ${C.border}`, borderRadius: 8, padding: "8px", fontSize: 12, fontWeight: 600, cursor: "pointer", fontFamily: "inherit" }}>
                    Delete
                  </button>
                </div>
              </div>
            </div>
          );
        })}
      </div>
      {editModal && editTent && (
        <Modal title={`Edit — ${editTent.name}`} onClose={() => setEditModal(false)}>
          <div style={{ background: C.amberLight, border: `1px solid ${C.amber}33`, borderRadius: 8, padding: "10px 13px", marginBottom: 16, fontSize: 12, color: C.amber, fontWeight: 600 }}>
            ⚠ Changing price will apply to new bookings only
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
  const statuses = ["all", "confirmed", "pending", "checked_in", "completed", "cancelled"];

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
          {clearMsg && <span style={{ color: C.green, fontSize: 13, fontWeight: 600 }}>✅ {clearMsg}</span>}
          <button onClick={clearCancelled} disabled={clearing} style={{ background: C.amberLight, color: C.amber, border: `1px solid ${C.amber}33`, borderRadius: 9, padding: "8px 16px", fontSize: 13, fontWeight: 700, cursor: clearing ? "not-allowed" : "pointer", fontFamily: "inherit" }}>
            {clearing ? "Clearing..." : "🗑 Clear Old Cancelled (30d+)"}
          </button>
          <button onClick={clearAllCancelled} disabled={clearing} style={{ background: C.redLight, color: C.red, border: `1px solid ${C.red}33`, borderRadius: 9, padding: "8px 16px", fontSize: 13, fontWeight: 700, cursor: clearing ? "not-allowed" : "pointer", fontFamily: "inherit" }}>
            {clearing ? "Clearing..." : "🗑 Clear All Cancelled"}
          </button>
        </div>
      </div>
      <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, boxShadow: C.shadow }}>
        <div style={{ padding: "16px 18px", borderBottom: `1px solid ${C.border}`, display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="🔍  Search guest name or booking ID..." style={{ ...inpStyle, flex: 1, minWidth: 200 }} />
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {statuses.map(s => (
              <button key={s} onClick={() => setFilter(s)} style={{ background: filter === s ? C.primary : C.bg, color: filter === s ? "#fff" : C.textSub, border: `1px solid ${filter === s ? C.primary : C.border}`, borderRadius: 8, padding: "6px 12px", fontSize: 12, fontWeight: 600, cursor: "pointer", fontFamily: "inherit" }}>
                {s === "all" ? "All" : s.replace("_", " ")}
              </button>
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
                      {b.status === "pending" && <button onClick={() => updateStatus(b.booking_ref, "confirmed")} style={{ background: C.greenLight, color: C.green, border: "none", borderRadius: 6, padding: "4px 10px", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>Confirm</button>}
                      {b.status === "confirmed" && <button onClick={() => updateStatus(b.booking_ref, "checked_in")} style={{ background: C.primaryLight, color: C.primary, border: "none", borderRadius: 6, padding: "4px 10px", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>Check In</button>}
                      {b.status === "checked_in" && <button onClick={() => updateStatus(b.booking_ref, "completed")} style={{ background: C.purpleLight, color: C.purple, border: "none", borderRadius: 6, padding: "4px 10px", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>Complete</button>}
                      {!["cancelled","completed"].includes(b.status) && <button onClick={() => updateStatus(b.booking_ref, "cancelled")} style={{ background: C.redLight, color: C.red, border: "none", borderRadius: 6, padding: "4px 10px", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>Cancel</button>}
                    </div>
                  </td>
                </tr>
              ))}
              {!loading && filtered.length === 0 && <tr><td colSpan={8} style={{ textAlign: "center", padding: 40, color: C.textMuted }}>No bookings found</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
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
      <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, boxShadow: C.shadow, overflowX: "auto" }}>
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
                  <button onClick={() => toggleBlock(u.phone, u.status)}
                    style={{ background: u.status === "active" ? C.redLight : C.greenLight, color: u.status === "active" ? C.red : C.green, border: "none", borderRadius: 7, padding: "5px 12px", fontSize: 12, fontWeight: 700, cursor: "pointer", fontFamily: "inherit" }}>
                    {u.status === "active" ? "Block" : "Unblock"}
                  </button>
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
          <div key={c.id} style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, overflow: "hidden", boxShadow: C.shadow }}>
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
                <button onClick={() => toggleCoupon(c.id)}
                  style={{ flex: 1, background: c.is_active ? C.redLight : C.greenLight, color: c.is_active ? C.red : C.green, border: "none", borderRadius: 8, padding: "8px", fontSize: 12, fontWeight: 700, cursor: "pointer", fontFamily: "inherit" }}>
                  {c.is_active ? "Deactivate" : "Activate"}
                </button>
                <button onClick={() => deleteCoupon(c.id)} style={{ flex: 1, background: C.bg, color: C.textSub, border: `1px solid ${C.border}`, borderRadius: 8, padding: "8px", fontSize: 12, fontWeight: 600, cursor: "pointer", fontFamily: "inherit" }}>Delete</button>
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
        <StatCard icon="💰" label="Total Revenue" value={fmt(stats.total_revenue||0)} trend="18%" color={C.green} />
        <StatCard icon="📅" label="This Week" value={fmt(revenue.reduce((a,r)=>a+r.amount,0))} trend="6%" color={C.primary} />
        <StatCard icon="📆" label="Today" value={fmt(stats.today_revenue||0)} color={C.amber} />
        <StatCard icon="📊" label="Avg per Booking" value={fmt(3752)} color={C.purple} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1.4fr 1fr", gap: 16 }}>
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 22, boxShadow: C.shadow }}>
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
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 22, boxShadow: C.shadow }}>
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
    { label: "🎉 Welcome Offer", title: "Special Welcome Discount!", msg: "Book your first tent and get 20% off with code WELCOME20!" },
    { label: "⚠️ Booking Reminder", title: "Your Check-in is Tomorrow", msg: "Don't forget! Your Kumbh Tent check-in is scheduled for tomorrow. Have a safe journey!" },
    { label: "🌊 Surge Alert", title: "High Demand — Book Now!", msg: "Tent prices are rising due to peak season. Book now to secure your spot!" },
    { label: "⛺ New Tent Available", title: "New Premium Tent Added!", msg: "We've added a new Premium Capsule Tent. Book now for an exclusive experience!" },
  ];
  return (
    <div>
      <div style={{ color: C.text, fontSize: 18, fontWeight: 800, marginBottom: 20 }}>Push Notifications</div>
      {sent && <div style={{ background: C.greenLight, border: `1px solid ${C.green}44`, color: C.green, borderRadius: 10, padding: "11px 16px", marginBottom: 16, fontWeight: 600, fontSize: 13 }}>✅ Notification sent to {sentCount} users!</div>}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 22, boxShadow: C.shadow }}>
          <div style={{ color: C.text, fontWeight: 700, fontSize: 14, marginBottom: 18 }}>Compose Notification</div>
          <FormField label="Target Audience">
            <div style={{ display: "flex", gap: 8 }}>
              {[["all", "All Users"], ["active", "Active"], ["new", "New Users"]].map(([val, lbl]) => (
                <button key={val} onClick={() => setTarget(val)} style={{ flex: 1, background: target === val ? C.primary : C.bg, color: target === val ? "#fff" : C.textSub, border: `1px solid ${target === val ? C.primary : C.border}`, borderRadius: 8, padding: "8px 6px", fontSize: 12, fontWeight: 600, cursor: "pointer", fontFamily: "inherit" }}>{lbl}</button>
              ))}
            </div>
          </FormField>
          <FormField label="Title"><input style={inpStyle} placeholder="Notification title..." value={title} onChange={e => setTitle(e.target.value)} /></FormField>
          <FormField label="Message">
            <textarea style={{ ...inpStyle, minHeight: 90, resize: "vertical" }} placeholder="Write your message here..." value={msg} onChange={e => setMsg(e.target.value)} />
          </FormField>
          <button onClick={send} disabled={loading} style={{ width: "100%", background: loading ? C.textMuted : C.primary, color: "#fff", border: "none", borderRadius: 9, padding: "11px", fontSize: 14, fontWeight: 700, cursor: loading ? "not-allowed" : "pointer", fontFamily: "inherit" }}>
            {loading ? "Sending..." : "🔔 Send Notification"}
          </button>
        </div>
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 22, boxShadow: C.shadow }}>
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
          <div key={label} style={{ display: "flex", alignItems: "center", gap: 6, background: C.white, border: `1px solid ${C.border}`, borderRadius: 8, padding: "6px 12px", fontSize: 12 }}>
            <div style={{ width: 10, height: 10, borderRadius: 3, background: color }} />
            <span style={{ color: C.textSub }}>{label}</span>
          </div>
        ))}
      </div>

      {inventory.map(tent => (
        <div key={tent.name} style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, marginBottom: 16, boxShadow: C.shadow, overflow: "hidden" }}>
          <div style={{ padding: "14px 20px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ color: C.text, fontWeight: 700, fontSize: 14 }}>⛺ {tent.name}</div>
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
                    <tr key={d.date} style={{ background: i % 2 === 0 ? C.white : "#fafafa" }}>
                      <td style={{ padding: "11px 16px", color: C.text, fontWeight: 600, fontSize: 13 }}>
                        {new Date(d.date).toLocaleDateString("en-IN", { weekday: "short", day: "numeric", month: "short" })}
                      </td>
                      <td style={{ padding: "11px 16px", textAlign: "center", color: C.text, fontWeight: 700 }}>{d.booked}</td>
                      <td style={{ padding: "11px 16px", textAlign: "center" }}>
                        <span style={{ background: bg, color, padding: "3px 10px", borderRadius: 20, fontSize: 12, fontWeight: 700 }}>{avail}</span>
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
  <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, overflow: "hidden", boxShadow: C.shadow }}>
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
            {[["⛺ Tent", ticket.tent], ["👥 Guests", ticket.guests], ["📅 Check-in", ticket.checkIn], ["📅 Check-out", ticket.checkOut], ["🌙 Nights", ticket.nights], ["💰 Amount", `₹${ticket.amount.toLocaleString("en-IN")}`]].map(([l, v]) => (
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
                <span key={a} style={{ background: C.primaryLight, color: C.primary, padding: "2px 8px", borderRadius: 20, fontSize: 11, fontWeight: 600 }}>{a}</span>
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
        <button style={{ background: C.primaryLight, color: C.primary, border: "none", borderRadius: 8, padding: "6px 14px", fontSize: 12, fontWeight: 700, cursor: "pointer" }}>🖨 Print Ticket</button>
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
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="🔍  Search by booking ID or guest name..." style={{ ...inpStyle, maxWidth: 400 }} />
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
          <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 22, boxShadow: C.shadow, marginBottom: 16 }}>
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
              <div style={{ color: "#ffffff66", fontSize: 13, zIndex: 1 }}>📷 Point camera at QR code</div>
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
          <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 20, boxShadow: C.shadow }}>
            <div style={{ color: C.text, fontWeight: 700, fontSize: 13, marginBottom: 14 }}>Recent Check-ins Today</div>
            {recentScans.length === 0 && <div style={{ color: C.textMuted, fontSize: 13 }}>No check-ins yet today</div>}
            {recentScans.map((s, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 10, padding: "9px 0", borderBottom: i < recentScans.length - 1 ? `1px solid ${C.border}` : "none" }}>
                <div style={{ width: 32, height: 32, borderRadius: "50%", background: C.greenLight, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 14 }}>✅</div>
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
            <div style={{ background: C.white, border: `2px dashed ${C.border}`, borderRadius: 14, padding: 40, textAlign: "center", height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
              <div style={{ fontSize: 48, marginBottom: 12 }}>🎫</div>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 15, marginBottom: 6 }}>No Booking Scanned</div>
              <div style={{ color: C.textMuted, fontSize: 13 }}>Scan a QR code or enter a booking ID to view guest details and check them in</div>
            </div>
          )}
          {notFound && (
            <div style={{ background: C.redLight, border: `1px solid ${C.red}33`, borderRadius: 14, padding: 32, textAlign: "center" }}>
              <div style={{ fontSize: 40, marginBottom: 12 }}>❌</div>
              <div style={{ color: C.red, fontWeight: 800, fontSize: 16, marginBottom: 6 }}>Booking Not Found</div>
              <div style={{ color: C.red + "aa", fontSize: 13 }}>No booking matches "{input}". Please check the ID and try again.</div>
            </div>
          )}
          {result && (
            <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, overflow: "hidden", boxShadow: C.shadow }}>
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
                  {[["⛺ Tent", result.tent], ["👥 Guests", result.guests], ["📅 Check-in", result.checkIn], ["📅 Check-out", result.checkOut], ["🌙 Nights", result.nights], ["💰 Paid", `₹${result.amount.toLocaleString("en-IN")}`]].map(([l, v]) => (
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
                    ✅ Guest Already Checked In
                  </div>
                ) : result.status === "confirmed" ? (
                  <button onClick={async () => {
                    await apiPut(`/admin/bookings/${result.id}/status`, { status: "checked_in" });
                    const now = new Date().toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" });
                    setRecentScans([{ id: result.id, guest: result.guest, tent: result.tent, time: now, action: "Checked In" }, ...recentScans.slice(0, 4)]);
                    setResult({ ...result, status: "checked_in" });
                  }} style={{ width: "100%", background: C.green, color: "#fff", border: "none", borderRadius: 10, padding: "13px", fontSize: 15, fontWeight: 800, cursor: "pointer", fontFamily: "inherit", boxShadow: `0 4px 12px ${C.green}40` }}>
                    ✅ Check In Guest
                  </button>
                ) : (
                  <div style={{ background: C.amberLight, border: `1px solid ${C.amber}44`, borderRadius: 10, padding: "14px", textAlign: "center", color: C.amber, fontWeight: 700, fontSize: 13 }}>
                    ⚠ Booking status is "{result.status}" — cannot check in
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
          {status.type === "success" ? "✅" : "⚠"} {status.msg}
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
      <button onClick={change} disabled={loading} style={{ width: "100%", background: loading ? C.textMuted : C.purple, color: "#fff", border: "none", borderRadius: 10, padding: "11px", fontSize: 14, fontWeight: 700, cursor: loading ? "not-allowed" : "pointer", fontFamily: "inherit" }}>
        {loading ? "Changing..." : "✏️ Change Username"}
      </button>
    </div>
  );
};

// ─── Settings ─────────────────────────────────────────────────────
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
        <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 24, boxShadow: C.shadow }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
            <div style={{ background: C.primaryLight, borderRadius: 10, padding: "8px 10px", fontSize: 18 }}>🔒</div>
            <div>
              <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>Change Password</div>
              <div style={{ color: C.textMuted, fontSize: 12 }}>Update your admin password</div>
            </div>
          </div>

          {status && (
            <div style={{ background: status.type === "success" ? C.greenLight : C.redLight, border: `1px solid ${status.type === "success" ? C.green : C.red}33`, color: status.type === "success" ? C.green : C.red, borderRadius: 8, padding: "10px 14px", marginBottom: 16, fontSize: 13, fontWeight: 600 }}>
              {status.type === "success" ? "✅" : "⚠"} {status.msg}
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

          <button onClick={changePassword} disabled={loading} style={{ width: "100%", background: loading ? C.textMuted : C.primary, color: "#fff", border: "none", borderRadius: 10, padding: "11px", fontSize: 14, fontWeight: 700, cursor: loading ? "not-allowed" : "pointer", fontFamily: "inherit", marginTop: 4 }}>
            {loading ? "Changing..." : "🔒 Change Password"}
          </button>
        </div>

        {/* Account Info + Change Username */}
        <div>
          <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 24, boxShadow: C.shadow, marginBottom: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
              <div style={{ background: C.primaryLight, borderRadius: 10, padding: "8px 10px", fontSize: 18 }}>👤</div>
              <div>
                <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>Account Info</div>
                <div style={{ color: C.textMuted, fontSize: 12 }}>Your admin account details</div>
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 12, background: C.bg, borderRadius: 10, padding: "14px 16px", marginBottom: 14 }}>
              <Avatar name={username} size={44} />
              <div>
                <div style={{ color: C.text, fontWeight: 800, fontSize: 16 }}>{username}</div>
                <div style={{ color: C.primary, fontSize: 12, fontWeight: 600 }}>Super Admin</div>
              </div>
            </div>
            {[["Role", "Super Admin"], ["Access", "Full Access"], ["Backend", "localhost:8080"], ["Auth", "JWT Token"]].map(([l, v]) => (
              <div key={l} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: `1px solid ${C.border}` }}>
                <div style={{ color: C.textSub, fontSize: 13 }}>{l}</div>
                <div style={{ color: C.text, fontSize: 13, fontWeight: 600 }}>{v}</div>
              </div>
            ))}
          </div>

          {/* Change Username */}
          <div style={{ background: C.white, border: `1px solid ${C.border}`, borderRadius: 14, padding: 24, boxShadow: C.shadow, marginBottom: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
              <div style={{ background: C.purpleLight, borderRadius: 10, padding: "8px 10px", fontSize: 18 }}>✏️</div>
              <div>
                <div style={{ color: C.text, fontWeight: 700, fontSize: 15 }}>Change Username</div>
                <div style={{ color: C.textMuted, fontSize: 12 }}>Update your login username</div>
              </div>
            </div>
            <ChangeUsername currentUsername={username} />
          </div>

          {/* Security Tips */}
          <div style={{ background: C.amberLight, border: `1px solid ${C.amber}33`, borderRadius: 14, padding: 20 }}>
            <div style={{ color: C.amber, fontWeight: 700, fontSize: 13, marginBottom: 10 }}>⚠ Security Tips</div>
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
const PAGES = { dashboard: Dashboard, tents: Tents, bookings: Bookings, users: Users, coupons: Coupons, revenue: Revenue, notifications: Notifications, inventory: Inventory, eticket: ETicket, qrscanner: QRScanner, settings: Settings };

export default function App() {
  const [auth, setAuth] = useState(!!localStorage.getItem("admin_token"));
  const [page, setPage] = useState("dashboard");
  const Page = PAGES[page] || Dashboard;
  if (!auth) return <Login onLogin={(token) => setAuth(true)} />;
  return (
    <div style={{ fontFamily: "'Inter', sans-serif", background: C.bg, minHeight: "100vh" }}>
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
      <Sidebar active={page} onNav={setPage} onLogout={() => { localStorage.removeItem("admin_token"); localStorage.removeItem("admin_username"); setAuth(false); setPage("dashboard"); }} />
      <div style={{ marginLeft: 230 }}>
        <TopBar page={page} />
        <main style={{ padding: "24px 28px" }}>
          <Page onNav={setPage} />
        </main>
      </div>
    </div>
  );
}
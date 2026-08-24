import type React from "react";
import { cn } from "@/lib/utils";

/**
 * Dark botanical backdrop built for Liquid Glass UI.
 *
 * Rendered rather than photographic — every element is vector, so it
 * stays sharp at any viewport, weighs nothing, and ships offline. The
 * brief calls for heavy depth-of-field on all foliage, and blurred
 * silhouettes read as leaves regardless of source, so vector loses
 * very little here.
 *
 * Layer order (back → front), tuned so glass cards always sit over
 * something readable:
 *   1. base gradient            #0B1F18 → #07120F → #020706
 *   2. far foliage   blur 30px  — barely-there shapes, deep corners
 *   3. emerald mist             — soft atmospheric glow pools
 *   4. mid foliage   blur 15px  — the layer glass actually refracts
 *   5. near foliage  blur 6px   — edge framing, strongest silhouettes
 *   6. light rays / bokeh       — highlights for the glass to catch
 *   7. centre vignette          — hard guarantee the middle stays dark
 */

const EMERALD = {
  deep: "#0B1F18",
  mid: "#123528",
  bright: "#1A5C42",
  glow: "#1F7A56",
};

/** One tapered leaf blade, drawn from its base at the bottom-centre. */
function Blade({ fill, opacity = 1 }: { fill: string; opacity?: number }) {
  return (
    <path
      d="M50 4 C 84 62, 96 150, 50 258 C 4 150, 16 62, 50 4 Z"
      fill={fill}
      opacity={opacity}
    />
  );
}

/**
 * Split-leaf (monstera) — built as separate blades fanned around a
 * hub rather than one shape with cut-outs, so the gaps between
 * fronds are genuinely transparent and the layers behind show
 * through them.
 */
function Monstera({ fill, glow }: { fill: string; glow: string }) {
  const angles = [-78, -52, -26, 0, 26, 52, 78];
  return (
    <svg viewBox="-160 -20 320 300" width="100%" height="100%">
      {angles.map((a, i) => {
        const mid = Math.abs(a) < 14;
        return (
          <g key={a} transform={`rotate(${a}) scale(${mid ? 1 : 0.82 - Math.abs(a) / 400}) translate(-50 0)`}>
            <Blade fill={i % 3 === 1 ? glow : fill} opacity={mid ? 0.95 : 0.8} />
          </g>
        );
      })}
    </svg>
  );
}

/** Palm frond — narrow leaflets stepping down a curved rachis. */
function Palm({ fill, glow }: { fill: string; glow: string }) {
  const leaflets = Array.from({ length: 13 }, (_, i) => i);
  return (
    <svg viewBox="-150 -20 300 300" width="100%" height="100%">
      {leaflets.map((i) => {
        const t = i / (leaflets.length - 1);
        const side = i % 2 === 0 ? 1 : -1;
        const angle = side * (24 + t * 46);
        const scale = 0.9 - t * 0.45;
        return (
          <g
            key={i}
            transform={`translate(0 ${t * 120}) rotate(${angle}) scale(${scale}) translate(-50 0)`}
          >
            <Blade fill={i % 4 === 0 ? glow : fill} opacity={0.72} />
          </g>
        );
      })}
    </svg>
  );
}

type Sprig = {
  kind: "monstera" | "palm";
  /** CSS inset positioning, in % or px. */
  style: React.CSSProperties;
  rotate: number;
  size: number;
};

// Foliage hugs the edges and corners; nothing is placed within the
// central band, which is where dashboard cards and text live.
const FAR: Sprig[] = [
  { kind: "palm", style: { top: "-8%", left: "-6%" }, rotate: 155, size: 640 },
  { kind: "monstera", style: { top: "-12%", right: "-8%" }, rotate: 195, size: 720 },
  { kind: "palm", style: { bottom: "-14%", left: "18%" }, rotate: -20, size: 600 },
  { kind: "monstera", style: { bottom: "-10%", right: "12%" }, rotate: 25, size: 560 },
];

const MID: Sprig[] = [
  { kind: "monstera", style: { top: "-14%", left: "-10%" }, rotate: 168, size: 520 },
  { kind: "palm", style: { top: "22%", right: "-14%" }, rotate: 250, size: 560 },
  { kind: "monstera", style: { bottom: "-16%", left: "-8%" }, rotate: 8, size: 480 },
  { kind: "palm", style: { bottom: "-18%", right: "-6%" }, rotate: 42, size: 520 },
];

const NEAR: Sprig[] = [
  { kind: "monstera", style: { top: "-20%", left: "-12%" }, rotate: 160, size: 460 },
  { kind: "palm", style: { top: "-16%", right: "-10%" }, rotate: 210, size: 480 },
  { kind: "monstera", style: { bottom: "-22%", right: "-14%" }, rotate: 32, size: 440 },
  { kind: "palm", style: { bottom: "-20%", left: "-14%" }, rotate: -28, size: 420 },
];

function FoliageLayer({
  sprigs,
  blur,
  opacity,
  fill,
  glow,
}: {
  sprigs: Sprig[];
  blur: number;
  opacity: number;
  fill: string;
  glow: string;
}) {
  return (
    <div
      aria-hidden
      style={{
        position: "absolute",
        inset: 0,
        filter: `blur(${blur}px)`,
        opacity,
        willChange: "transform",
      }}
    >
      {sprigs.map((s, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            width: s.size,
            height: s.size,
            transform: `rotate(${s.rotate}deg)`,
            ...s.style,
          }}
        >
          {s.kind === "monstera" ? <Monstera fill={fill} glow={glow} /> : <Palm fill={fill} glow={glow} />}
        </div>
      ))}
    </div>
  );
}

export function BotanicalBackground({ className }: { className?: string }) {
  return (
    <div
      aria-hidden
      className={cn("fixed inset-0 z-0 overflow-hidden", className)}
      style={{
        background: `linear-gradient(150deg, ${EMERALD.deep} 0%, #07120F 46%, #020706 100%)`,
      }}
    >
      {/* 2 — far foliage, deepest depth-of-field */}
      <FoliageLayer sprigs={FAR} blur={30} opacity={0.5} fill={EMERALD.mid} glow={EMERALD.bright} />

      {/* 3 — atmospheric mist. Each fade ends on rgba(<same hue>,0);
          the `transparent` keyword is rgba(0,0,0,0) and would smear
          these toward black instead of dissolving cleanly. */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `
            radial-gradient(60% 45% at 14% 22%, rgba(31,122,86,0.22) 0%, rgba(31,122,86,0) 100%),
            radial-gradient(55% 40% at 88% 30%, rgba(26,92,66,0.2) 0%, rgba(26,92,66,0) 100%),
            radial-gradient(70% 50% at 76% 86%, rgba(31,122,86,0.16) 0%, rgba(31,122,86,0) 100%),
            radial-gradient(50% 40% at 20% 90%, rgba(18,53,40,0.28) 0%, rgba(18,53,40,0) 100%)
          `,
        }}
      />

      {/* 4 — mid foliage: the layer the glass cards actually distort */}
      <FoliageLayer sprigs={MID} blur={15} opacity={0.62} fill={EMERALD.mid} glow={EMERALD.glow} />

      {/* 5 — near foliage framing the edges */}
      <FoliageLayer sprigs={NEAR} blur={6} opacity={0.5} fill="#0d2a20" glow={EMERALD.bright} />

      {/* 6a — light rays through the canopy */}
      <div
        style={{
          position: "absolute",
          inset: "-25%",
          transform: "rotate(-18deg)",
          mixBlendMode: "screen",
          opacity: 0.5,
          filter: "blur(26px)",
          background: `repeating-linear-gradient(
            96deg,
            rgba(31,122,86,0) 0px,
            rgba(31,122,86,0) 90px,
            rgba(52,150,110,0.11) 120px,
            rgba(31,122,86,0) 168px
          )`,
        }}
      />

      {/* 6b — bokeh highlights for the glass to refract */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          filter: "blur(3px)",
          opacity: 0.5,
          background: `
            radial-gradient(circle 7px at 12% 34%, rgba(90,190,150,0.5) 0%, rgba(90,190,150,0) 100%),
            radial-gradient(circle 11px at 91% 18%, rgba(70,170,130,0.42) 0%, rgba(70,170,130,0) 100%),
            radial-gradient(circle 5px at 82% 66%, rgba(120,210,175,0.45) 0%, rgba(120,210,175,0) 100%),
            radial-gradient(circle 9px at 26% 82%, rgba(70,170,130,0.38) 0%, rgba(70,170,130,0) 100%),
            radial-gradient(circle 6px at 6% 62%, rgba(100,200,160,0.4) 0%, rgba(100,200,160,0) 100%),
            radial-gradient(circle 8px at 68% 8%, rgba(80,180,140,0.34) 0%, rgba(80,180,140,0) 100%)
          `,
        }}
      />

      {/* 7 — centre vignette. Sits above every foliage layer so the
          reading area is dark by construction, not by luck of where
          the leaves happened to land. */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `
            radial-gradient(72% 68% at 52% 48%, rgba(2,7,6,0.9) 0%, rgba(2,7,6,0.62) 42%, rgba(2,7,6,0) 78%),
            linear-gradient(180deg, rgba(2,7,6,0.5) 0%, rgba(2,7,6,0) 22%, rgba(2,7,6,0) 74%, rgba(2,7,6,0.62) 100%)
          `,
        }}
      />
    </div>
  );
}

export default BotanicalBackground;

import type React from "react";
import { cn } from "@/lib/utils";

export type SoftGlowTone = "primary" | "green" | "red" | "amber" | "purple" | "neutral";

// Lifted to 400-level tints so the glow is actually visible against
// the #111–#222 background; the 600-level originals disappeared on
// charcoal. Alpha stays low — a defined edge, not a halo.
const GLOW_COLOR: Record<SoftGlowTone, string> = {
  primary: "#60a5fa",
  green: "#4ade80",
  red: "#f87171",
  amber: "#fbbf24",
  purple: "#c084fc",
  neutral: "#e5e5e5",
};

export interface ButtonSoftGlowProps
  extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "color"> {
  tone?: SoftGlowTone;
  fullWidth?: boolean;
}

// Always a white surface — the "soft glow" comes entirely from a
// blurred, tone-colored shadow sitting behind the button, not from
// the button's own fill. Matches the site's light glass theme
// rather than any dark/colored button fill.
export function ButtonSoftGlow({
  tone = "primary",
  fullWidth,
  disabled,
  className,
  style,
  children,
  ...props
}: ButtonSoftGlowProps) {
  const glow = GLOW_COLOR[tone];
  return (
    <button
      {...props}
      disabled={disabled}
      className={cn(
        "relative inline-flex items-center justify-center gap-2 rounded-full bg-white px-6 py-2.5 text-sm font-semibold text-gray-900",
        "transition-all duration-200 ease-out",
        "hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.98]",
        "disabled:pointer-events-none disabled:opacity-50 disabled:translate-y-0",
        fullWidth && "w-full",
        className,
      )}
      style={{
        boxShadow: disabled
          ? "0 1px 2px rgba(0,0,0,0.4)"
          : `0 2px 6px rgba(0,0,0,0.45), 0 8px 20px -6px ${glow}4d, 0 0 26px -10px ${glow}40`,
        ...style,
      }}
    >
      {children}
    </button>
  );
}

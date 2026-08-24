import { liquidMetalFragmentShader, ShaderMount } from "@paper-design/shaders";
import { Sparkles } from "lucide-react";
import type React from "react";
import { useEffect, useMemo, useRef, useState } from "react";

export type LiquidMetalTone =
  | "neutral"
  | "primary"
  | "green"
  | "red"
  | "amber"
  | "purple";

const TONE_ACCENT: Record<LiquidMetalTone, string> = {
  neutral: "#9a9a9a",
  primary: "#5b8def",
  green: "#22c55e",
  red: "#ef4444",
  amber: "#f59e0b",
  purple: "#a855f7",
};

interface LiquidMetalButtonProps {
  label?: React.ReactNode;
  onClick?: () => void;
  viewMode?: "text" | "icon";
  /** "default" is the original 142x46 hero pill; "sm" is a compact
   * 30px-tall pill sized for table rows, chips, and nav items. */
  size?: "default" | "sm";
  /** Tints the glow/ring and label color to carry the same
   * semantic meaning the old flat-color buttons used (green =
   * positive, red = destructive, etc) without giving up the
   * liquid-metal shader look. */
  tone?: LiquidMetalTone;
  /** Chips/nav/tabs: renders a solid tone-colored ring to show
   * "this is the selected one" instead of the idle metal look. */
  active?: boolean;
  disabled?: boolean;
  fullWidth?: boolean;
  /** Explicit pixel width; overrides the auto-width-from-label
   * calculation. Height still follows `size`. */
  width?: number;
  className?: string;
  style?: React.CSSProperties;
  title?: string;
}

let shaderStyleInjected = false;
function ensureShaderStyle() {
  if (shaderStyleInjected || typeof document === "undefined") return;
  shaderStyleInjected = true;
  const style = document.createElement("style");
  style.id = "shader-canvas-style-exploded";
  style.textContent = `
    .shader-container-exploded canvas {
      width: 100% !important;
      height: 100% !important;
      display: block !important;
      position: absolute !important;
      top: 0 !important;
      left: 0 !important;
      border-radius: 100px !important;
    }
    @keyframes ripple-animation {
      0% { transform: translate(-50%, -50%) scale(0); opacity: 0.6; }
      100% { transform: translate(-50%, -50%) scale(4); opacity: 0; }
    }
    @keyframes lmb-shimmer {
      0% { background-position: 0% 50%; }
      100% { background-position: 200% 50%; }
    }
  `;
  document.head.appendChild(style);
}

// Browsers cap concurrent WebGL contexts per page (commonly ~16).
// This app can have 20+ LiquidMetalButton instances on screen at
// once (sidebar nav, table row actions, filter chips) plus the
// site-wide Velaris background — well past that cap. Past the
// budget, new instances render a CSS-only animated dark pill
// instead of mounting a real WebGL context, so nothing silently
// loses its shader (context loss picks victims unpredictably,
// including ones that already grabbed a context first).
const MAX_SHADER_CONTEXTS = 10;
let activeShaderContexts = 0;

function labelText(label: React.ReactNode): string {
  if (typeof label === "string" || typeof label === "number") return String(label);
  return "";
}

export function LiquidMetalButton({
  label = "Get Started",
  onClick,
  viewMode = "text",
  size = "default",
  tone = "neutral",
  active = false,
  disabled = false,
  fullWidth = false,
  width,
  className,
  style,
  title,
}: LiquidMetalButtonProps) {
  const [isHovered, setIsHovered] = useState(false);
  const [isPressed, setIsPressed] = useState(false);
  const [ripples, setRipples] = useState<
    Array<{ x: number; y: number; id: number }>
  >([]);
  const shaderRef = useRef<HTMLDivElement>(null);
  // biome-ignore lint/suspicious/noExplicitAny: External library without types
  const shaderMount = useRef<any>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const rippleId = useRef(0);
  const holdsContext = useRef(false);
  const [shaderActive, setShaderActive] = useState(false);

  const dimensions = useMemo(() => {
    const height = size === "sm" ? 30 : 46;
    const pad = size === "sm" ? 2 : 2;
    const iconOnly = viewMode === "icon";
    let w: number;
    if (width) w = width;
    else if (iconOnly) w = height;
    else {
      const text = labelText(label);
      const charWidth = size === "sm" ? 6.6 : 7.6;
      const minW = size === "sm" ? 64 : 90;
      w = Math.max(minW, Math.round(text.length * charWidth) + (size === "sm" ? 28 : 44));
    }
    return {
      width: w,
      height,
      innerWidth: w - pad * 2,
      innerHeight: height - pad * 2,
      shaderWidth: w,
      shaderHeight: height,
    };
  }, [viewMode, size, width, label]);

  useEffect(() => {
    ensureShaderStyle();

    if (activeShaderContexts >= MAX_SHADER_CONTEXTS) {
      setShaderActive(false);
      return;
    }

    const loadShader = async () => {
      try {
        if (shaderRef.current) {
          if (shaderMount.current?.destroy) {
            shaderMount.current.destroy();
          }
          shaderMount.current = new ShaderMount(
            shaderRef.current,
            liquidMetalFragmentShader,
            {
              u_repetition: 4,
              u_softness: 0.5,
              u_shiftRed: 0.3,
              u_shiftBlue: 0.3,
              u_distortion: 0,
              u_contour: 0,
              u_angle: 45,
              u_scale: 8,
              u_shape: 1,
              u_offsetX: 0.1,
              u_offsetY: -0.1,
            },
            undefined,
            0.6,
          );
          activeShaderContexts += 1;
          holdsContext.current = true;
          setShaderActive(true);
        }
      } catch (error) {
        console.error("[liquid-metal-button] Failed to load shader:", error);
        setShaderActive(false);
      }
    };

    loadShader();

    return () => {
      if (shaderMount.current?.destroy) {
        shaderMount.current.destroy();
        shaderMount.current = null;
      }
      if (holdsContext.current) {
        activeShaderContexts -= 1;
        holdsContext.current = false;
      }
    };
  }, []);

  const handleMouseEnter = () => {
    if (disabled) return;
    setIsHovered(true);
    shaderMount.current?.setSpeed?.(1);
  };

  const handleMouseLeave = () => {
    setIsHovered(false);
    setIsPressed(false);
    shaderMount.current?.setSpeed?.(0.6);
  };

  const handleClick = (e: React.MouseEvent<HTMLButtonElement>) => {
    if (disabled) return;
    if (shaderMount.current?.setSpeed) {
      shaderMount.current.setSpeed(2.4);
      setTimeout(() => {
        shaderMount.current?.setSpeed?.(isHovered ? 1 : 0.6);
      }, 300);
    }

    if (buttonRef.current) {
      const rect = buttonRef.current.getBoundingClientRect();
      const ripple = { x: e.clientX - rect.left, y: e.clientY - rect.top, id: rippleId.current++ };
      setRipples((prev) => [...prev, ripple]);
      setTimeout(() => setRipples((prev) => prev.filter((r) => r.id !== ripple.id)), 600);
    }

    onClick?.();
  };

  const accent = TONE_ACCENT[tone];
  const fontSize = size === "sm" ? 12 : 14;

  return (
    <div
      className={`relative inline-block ${fullWidth ? "w-full" : ""} ${className || ""}`}
      style={{ opacity: disabled ? 0.5 : 1, ...(fullWidth ? { width: "100%" } : {}), ...style }}
      title={title}
    >
      <div style={{ perspective: "1000px", perspectiveOrigin: "50% 50%" }}>
        <div
          style={{
            position: "relative",
            width: fullWidth ? "100%" : `${dimensions.width}px`,
            height: `${dimensions.height}px`,
            transformStyle: "preserve-3d",
            transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1), width 0.4s ease, height 0.4s ease",
          }}
        >
          <div
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              height: `${dimensions.height}px`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: "6px",
              transformStyle: "preserve-3d",
              transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)",
              transform: "translateZ(20px)",
              zIndex: 30,
              pointerEvents: "none",
              padding: "0 10px",
            }}
          >
            {viewMode === "icon" && (
              <Sparkles
                size={size === "sm" ? 13 : 16}
                style={{
                  color: active ? accent : "#999999",
                  filter: "drop-shadow(0px 1px 2px rgba(0, 0, 0, 0.5))",
                  transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)",
                }}
              />
            )}
            {viewMode === "text" && (
              <span
                style={{
                  fontSize: `${fontSize}px`,
                  color: active ? accent : "#d5d5d5",
                  fontWeight: size === "sm" ? 600 : 500,
                  textShadow: "0px 1px 2px rgba(0, 0, 0, 0.5)",
                  transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)",
                  whiteSpace: "nowrap",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  maxWidth: "100%",
                }}
              >
                {label}
              </span>
            )}
          </div>

          <div
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              height: `${dimensions.height}px`,
              transformStyle: "preserve-3d",
              transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)",
              transform: `translateZ(10px) ${isPressed ? "translateY(1px) scale(0.98)" : "translateY(0) scale(1)"}`,
              zIndex: 20,
            }}
          >
            <div
              style={{
                width: `calc(100% - 4px)`,
                height: `${dimensions.innerHeight}px`,
                margin: "2px",
                borderRadius: "100px",
                background: "linear-gradient(180deg, #202020 0%, #000000 100%)",
                boxShadow: isPressed
                  ? "inset 0px 2px 4px rgba(0, 0, 0, 0.4), inset 0px 1px 2px rgba(0, 0, 0, 0.3)"
                  : "none",
                transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.15s ease",
              }}
            />
          </div>

          <div
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              height: `${dimensions.height}px`,
              transformStyle: "preserve-3d",
              transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)",
              transform: `translateZ(0px) ${isPressed ? "translateY(1px) scale(0.98)" : "translateY(0) scale(1)"}`,
              zIndex: 10,
            }}
          >
            <div
              style={{
                height: `${dimensions.height}px`,
                width: "100%",
                borderRadius: "100px",
                boxShadow: active
                  ? `0px 0px 0px 1.5px ${accent}99, 0px 0px 12px 1px ${accent}55, 0px 4px 4px 0px rgba(0, 0, 0, 0.15)`
                  : isPressed
                    ? "0px 0px 0px 1px rgba(0, 0, 0, 0.5), 0px 1px 2px 0px rgba(0, 0, 0, 0.3)"
                    : isHovered
                      ? `0px 0px 0px 1px ${accent}66, 0px 12px 6px 0px rgba(0, 0, 0, 0.05), 0px 8px 5px 0px rgba(0, 0, 0, 0.1), 0px 4px 4px 0px rgba(0, 0, 0, 0.15)`
                      : "0px 0px 0px 1px rgba(0, 0, 0, 0.3), 0px 20px 12px 0px rgba(0, 0, 0, 0.06), 0px 9px 9px 0px rgba(0, 0, 0, 0.1), 0px 2px 5px 0px rgba(0, 0, 0, 0.15)",
                transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.15s ease",
                background: "rgb(0 0 0 / 0)",
              }}
            >
              <div
                ref={shaderRef}
                className="shader-container-exploded"
                style={{
                  borderRadius: "100px",
                  overflow: "hidden",
                  position: "relative",
                  width: "100%",
                  height: `${dimensions.shaderHeight}px`,
                  transition: "width 0.4s ease, height 0.4s ease",
                  // No WebGL context available for this instance
                  // (past MAX_SHADER_CONTEXTS) — a static/CSS
                  // shimmer stands in so it still reads as the
                  // same dark metal pill, just without live noise.
                  background: shaderActive
                    ? undefined
                    : `linear-gradient(100deg, #1a1a1a 0%, #3a3a3a 25%, #1a1a1a 50%, #2e2e2e 75%, #1a1a1a 100%)`,
                  backgroundSize: shaderActive ? undefined : "200% 100%",
                  animation: shaderActive ? undefined : "lmb-shimmer 4s linear infinite",
                }}
              />
            </div>
          </div>

          <button
            ref={buttonRef}
            onClick={handleClick}
            onMouseEnter={handleMouseEnter}
            onMouseLeave={handleMouseLeave}
            onMouseDown={() => !disabled && setIsPressed(true)}
            onMouseUp={() => setIsPressed(false)}
            disabled={disabled}
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              height: `${dimensions.height}px`,
              background: "transparent",
              border: "none",
              cursor: disabled ? "not-allowed" : "pointer",
              outline: "none",
              zIndex: 40,
              transformStyle: "preserve-3d",
              transform: "translateZ(25px)",
              transition: "all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)",
              overflow: "hidden",
              borderRadius: "100px",
            }}
            aria-label={typeof label === "string" ? label : title}
          >
            {ripples.map((ripple) => (
              <span
                key={ripple.id}
                style={{
                  position: "absolute",
                  left: `${ripple.x}px`,
                  top: `${ripple.y}px`,
                  width: "20px",
                  height: "20px",
                  borderRadius: "50%",
                  background: "radial-gradient(circle, rgba(255, 255, 255, 0.4) 0%, rgba(255, 255, 255, 0) 70%)",
                  pointerEvents: "none",
                  animation: "ripple-animation 0.6s ease-out",
                }}
              />
            ))}
          </button>
        </div>
      </div>
    </div>
  );
}

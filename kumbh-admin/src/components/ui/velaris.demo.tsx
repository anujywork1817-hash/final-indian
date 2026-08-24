import Velaris from "@/components/ui/velaris";

export default function VelarisDemo() {
  return (
    <Velaris height="500px" className="rounded-xl">
      <div className="flex h-full w-full flex-col items-center justify-center gap-4 px-6 text-center">
        <span className="rounded-full border border-white/20 bg-white/10 px-4 py-1 text-xs font-medium text-white/80 backdrop-blur">
          Powered by WebGL
        </span>
        <h1 className="max-w-2xl text-4xl font-semibold tracking-tight text-white sm:text-6xl">
          Living gradients in motion
        </h1>
        <p className="max-w-md text-sm text-white/70 sm:text-base">
          An animated simplex-noise background with color blending, vignette glow and film grain.
        </p>
      </div>
    </Velaris>
  );
}

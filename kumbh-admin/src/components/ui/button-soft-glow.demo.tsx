import { ButtonSoftGlow } from "@/components/ui/button-soft-glow";

export default function ButtonSoftGlowDemo() {
  return (
    <div className="flex items-center gap-4">
      <ButtonSoftGlow tone="primary">Get Started</ButtonSoftGlow>
      <ButtonSoftGlow tone="purple">Learn More</ButtonSoftGlow>
    </div>
  );
}

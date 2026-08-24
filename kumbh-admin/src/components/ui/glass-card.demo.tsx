// demo.tsx
import * as React from "react";
import GlassCard from "@/components/ui/glass-card";

const GlassCardDemo = () => {
  return (
    <div className="flex h-[450px] w-full items-center justify-center bg-zinc-100 p-10 dark:bg-zinc-800">
      <GlassCard />
    </div>
  );
};

export { GlassCardDemo as DemoOne };

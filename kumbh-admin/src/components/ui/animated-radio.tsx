import { useState } from "react";
import type React from "react";
import { cn } from "@/lib/utils";

export interface RadioOption {
  id: string;
  value: string;
  label: React.ReactNode;
}

const DEFAULT_OPTIONS: RadioOption[] = [
  { id: "radio-free", value: "free", label: "Free" },
  { id: "radio-basic", value: "basic", label: "Basic" },
  { id: "radio-premium", value: "premium", label: "Premium" },
];

export interface AnimatedRadioProps {
  /** Defaults to the Free/Basic/Premium demo options. */
  options?: RadioOption[];
  /** Controlled selected value. Omit to let the component manage its own state (demo usage). */
  value?: string;
  /** Required when `value` is passed; called with the newly selected value. */
  onChange?: (value: string) => void;
  name?: string;
  className?: string;
}

export default function AnimatedRadio({
  options = DEFAULT_OPTIONS,
  value,
  onChange,
  name = "radio",
  className,
}: AnimatedRadioProps) {
  const [internalValue, setInternalValue] = useState(options[0]?.value ?? "");
  const selectedValue = value ?? internalValue;

  const handleChange = (v: string) => {
    if (onChange) onChange(v);
    else setInternalValue(v);
  };

  const rawIndex = options.findIndex((option) => option.value === selectedValue);
  const hasSelection = rawIndex !== -1;
  const index = Math.max(0, rawIndex);

  return (
    <div className={cn("flex items-center justify-center", className)}>
      <div className="relative flex flex-col pl-3">
        {options.map((option) => (
          <div key={option.id} className="relative z-20 py-1">
            <input
              id={option.id}
              name={name}
              type="radio"
              value={option.value}
              checked={selectedValue === option.value}
              onChange={(e) => handleChange(e.target.value)}
              className="absolute w-full h-full m-0 opacity-0 cursor-pointer z-30 appearance-none"
            />
            <label
              htmlFor={option.id}
              className={`cursor-pointer text-xl py-2 px-1 block transition-all duration-300 ease-in-out ${
                selectedValue === option.value
                  ? "text-amber-300"
                  : "text-neutral-400 hover:text-neutral-200"
              }`}
            >
              {option.label}
            </label>
          </div>
        ))}

        <div className="absolute left-0 top-0 bottom-0 w-px bg-gradient-to-b from-transparent via-white/12 to-transparent">
          <div
            className="relative w-full bg-gradient-to-b from-transparent via-amber-400 to-transparent transition-[transform,opacity] duration-500 ease-[cubic-bezier(0.37,1.95,0.66,0.56)]"
            style={{
              height: `${100 / options.length}%`,
              transform: `translateY(${index * 100}%)`,
              opacity: hasSelection ? 1 : 0,
            }}
          >
            <div className="absolute top-1/2 -translate-y-1/2 h-3/5 w-[300%] bg-amber-400 blur-[10px]" />
            <div className="absolute left-0 h-full w-36 bg-gradient-to-r from-amber-400/10 to-transparent" />
          </div>
        </div>
      </div>
    </div>
  );
}

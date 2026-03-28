import * as React from "react"

import { cn } from "@/lib/utils"

export type InputProps = React.InputHTMLAttributes<HTMLInputElement>

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        className={cn(
          "flex h-10 w-full rounded-md border border-[var(--border-1)] bg-[var(--surface-1)] px-3 py-2 text-sm text-[var(--text-0)] shadow-sm outline-none transition focus-visible:ring-2 focus-visible:ring-[var(--brand-400)] placeholder:text-[var(--text-2)]",
          className,
        )}
        ref={ref}
        {...props}
      />
    )
  },
)
Input.displayName = "Input"

export { Input }

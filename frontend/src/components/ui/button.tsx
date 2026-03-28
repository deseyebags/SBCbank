import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-semibold transition-all duration-200 disabled:pointer-events-none disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2",
  {
    variants: {
      variant: {
        default:
          "bg-[var(--brand-700)] text-white shadow-sm hover:bg-[var(--brand-600)] focus-visible:ring-[var(--brand-500)]",
        secondary:
          "bg-[var(--surface-2)] text-[var(--text-0)] border border-[var(--border-1)] hover:bg-[var(--surface-3)] focus-visible:ring-[var(--brand-400)]",
        ghost:
          "text-[var(--text-1)] hover:bg-[var(--surface-2)] focus-visible:ring-[var(--brand-400)]",
        danger:
          "bg-[var(--accent-700)] text-white hover:bg-[var(--accent-600)] focus-visible:ring-[var(--accent-500)]",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-8 px-3 text-xs",
        lg: "h-11 px-5 text-base",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, ...props }, ref) => {
    return (
      <button
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    )
  },
)
Button.displayName = "Button"

export { Button }

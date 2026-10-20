// app/helpers/ui_helper.rb と同じ見た目。片方を変えたら、もう片方も直すこと

const BUTTON_VARIANTS = {
  primary: "bg-primary-600 text-white hover:bg-primary-700",
  secondary: "bg-white text-primary-700 ring-1 ring-slate-300 ring-inset hover:bg-primary-50",
  danger: "bg-white text-red-700 ring-1 ring-red-200 ring-inset hover:bg-red-50",
}

const BUTTON_SIZES = {
  sm: "h-8 gap-1.5 px-4",
  md: "h-10 gap-2 px-6",
}

export function buttonClass(
  variant: keyof typeof BUTTON_VARIANTS = "primary",
  size: keyof typeof BUTTON_SIZES = "md",
) {
  return [
    "inline-flex shrink-0 cursor-pointer items-center justify-center rounded-full text-sm font-medium",
    "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600",
    BUTTON_VARIANTS[variant],
    BUTTON_SIZES[size],
  ]
}

// 左ペインのツリーの1行。選択中は丸い帯で示す
export function navItemClass(current: boolean) {
  return [
    "flex items-center gap-2 rounded-full px-4 py-2 text-sm",
    current ? "bg-primary-100 font-semibold text-primary-900" : "text-slate-700 hover:bg-slate-900/5",
  ]
}

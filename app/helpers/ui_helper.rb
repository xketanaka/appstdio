module UiHelper
  BUTTON_VARIANTS = {
    primary: "bg-primary-600 text-white hover:bg-primary-500",
    secondary: "bg-white text-slate-800 ring-1 ring-slate-300 ring-inset hover:bg-slate-50",
    danger: "bg-white text-red-600 ring-1 ring-red-300 ring-inset hover:bg-red-50",
  }.freeze

  BUTTON_SIZES = {
    sm: "gap-1.5 px-3 py-1.5",
    md: "gap-2 px-4 py-2",
  }.freeze

  def ui_button_class(variant = :primary, size: :md, extra: nil)
    class_names(
      "inline-flex shrink-0 cursor-pointer items-center justify-center rounded-md text-sm font-semibold shadow-xs",
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600",
      BUTTON_VARIANTS.fetch(variant),
      BUTTON_SIZES.fetch(size),
      extra,
    )
  end

  def ui_input_class
    "block w-full rounded-md border border-slate-300 bg-white px-3 py-2 shadow-xs " \
      "focus:border-primary-600 focus:outline-hidden focus:ring-3 focus:ring-primary-600/20"
  end
end

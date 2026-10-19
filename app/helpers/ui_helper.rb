module UiHelper
  BUTTON_VARIANTS = {
    primary: "bg-primary-600 text-white hover:bg-primary-700",
    secondary: "bg-white text-primary-700 ring-1 ring-slate-300 ring-inset hover:bg-primary-50",
    danger: "bg-white text-red-700 ring-1 ring-red-200 ring-inset hover:bg-red-50",
  }.freeze

  BUTTON_SIZES = {
    sm: "h-8 gap-1.5 px-4",
    md: "h-10 gap-2 px-6",
  }.freeze

  def ui_button_class(variant = :primary, size: :md, extra: nil)
    class_names(
      "inline-flex shrink-0 cursor-pointer items-center justify-center rounded-full text-sm font-medium",
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600",
      BUTTON_VARIANTS.fetch(variant),
      BUTTON_SIZES.fetch(size),
      extra,
    )
  end

  def ui_input_class
    "block w-full rounded-xl border border-slate-300 bg-white px-3.5 py-2 " \
      "focus:border-primary-600 focus:outline-hidden focus:ring-3 focus:ring-primary-600/20"
  end

  # 左ペイン・メニュー・ツリーの1行。選択中は丸い帯で示す
  def ui_nav_item_class(current, extra: nil)
    class_names(
      "flex items-center gap-2 rounded-full px-4 py-2 text-sm",
      current ? "bg-primary-100 font-semibold text-primary-900" : "text-slate-700 hover:bg-slate-900/5",
      extra,
    )
  end
end

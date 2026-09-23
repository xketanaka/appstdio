class FilesController < ApplicationController
  # 画面モック。実データは未実装で、以下はすべて仮の表示用
  Entry = Struct.new(:name, :folder, :owner, :updated_at, :bytes, keyword_init: true)

  SECTIONS = [
    { key: :shared_drive, open: true, children: ["名称未設定フォルダ"] },
    { key: :shared_with_me, open: false, children: [] },
    { key: :my_drive, open: false, children: [] },
    { key: :trash, open: false, children: [] },
  ].freeze

  def index
    @sections = SECTIONS
    @entries = [
      Entry.new(name: "名称未設定フォルダ", folder: true,
        owner: current_tenant_user.display_name, updated_at: Time.zone.parse("2026-08-15 12:30")),
      Entry.new(name: "議事録.docx", folder: false,
        owner: current_tenant_user.display_name, updated_at: Time.zone.parse("2026-08-14 09:05"), bytes: 25_088),
      Entry.new(name: "見積書.pdf", folder: false,
        owner: "山田 太郎", updated_at: Time.zone.parse("2026-08-12 18:41"), bytes: 1_258_291),
    ]
  end
end

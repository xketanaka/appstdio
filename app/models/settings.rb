class Settings
  def self.convert_to_struct(hash)
    hash.keys.select { |key| hash[key].is_a?(Hash) }
      .each { |key| hash[key] = self.convert_to_struct(hash[key]) }

    hash.keys.select { |key| hash[key].is_a?(Array) }
      .each { |key| hash[key] = hash[key].map { |obj| self.convert_to_struct(obj) } }

    Struct.new(*hash.keys.map(&:to_sym)).new.tap do |obj|
      hash.keys.each { |key| obj[key] = hash[key] }
    end
  end

  # app_url / ops_url を、URL を作るときの引数（protocol・host・port）にする。空なら空
  def self.url_options(url)
    uri = url.presence && URI(url)
    uri ? { protocol: uri.scheme, host: uri.host, port: (uri.port unless uri.port == uri.default_port) }.compact : {}
  end

  # ERB を通すので、<%= ENV.fetch("NAME", "既定") %> で環境変数を埋め込める
  _yaml = ERB.new(File.read(Rails.root.join("config/settings.yml"))).result
  _settings = self.convert_to_struct(YAML.load(_yaml, aliases: true)[Rails.env])
  _settings.members.each do |member|
    define_singleton_method(member) do
      _settings[member]
    end
  end
end

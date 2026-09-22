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

  _settings = self.convert_to_struct(YAML.load_file("#{Rails.root}/config/settings.yml", aliases: true)[Rails.env])
  _settings.members.each do |member|
    define_singleton_method(member) do
      _settings[member]
    end
  end
end

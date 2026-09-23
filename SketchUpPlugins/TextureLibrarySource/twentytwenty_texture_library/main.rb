# frozen_string_literal: true
require 'json'
require 'fileutils'
require 'securerandom'
require 'net/http'
require 'uri'

module TwentyTwenty
  module TextureLibrary
    extend self
    VERSION='0.2.0'.freeze
    PREF_KEY='twentytwenty_texture_library_v020'.freeze
    LIB_ROOT=File.join((ENV['APPDATA'] || Dir.home),'2020toolbox','TextureLibrary').freeze
    TEX_ROOT=File.join(LIB_ROOT,'textures').freeze
    LIB_JSON=File.join(LIB_ROOT,'library.json').freeze
    SIKO_CONCRETE_JSON=File.join(__dir__,'siko_concrete_tiles.json').freeze
    SIKO_FLOOR_JSON=File.join(__dir__,'siko_floor_tiles.json').freeze
    SIKO_CACHE=File.join(LIB_ROOT,'siko').freeze
    EGGER_JSON=File.join(__dir__,'egger_decors.json').freeze
    EGGER_CACHE=File.join(LIB_ROOT,'egger').freeze
    POLYHAVEN_CACHE=File.join(LIB_ROOT,'polyhaven').freeze
    POLYHAVEN_META=File.join(POLYHAVEN_CACHE,'assets.json').freeze
    POLYHAVEN_API='https://api.polyhaven.com'.freeze
    POLYHAVEN_UA='20-20 Texture Library/0.2.0 (SketchUp; Poly Haven API)'.freeze
    # Combined SIKO catalog UI: concrete wall tiles + floor tiles share one Obklady tab.
    # v0.1.7 catalog snapshot includes normalized SIKO filters and the current EGGER decor set.
    RAL=[{"code": "RAL 1000", "hex": "#BEBD7F", "name": "Green beige"}, {"code": "RAL 1001", "hex": "#C2B078", "name": "Beige"}, {"code": "RAL 1002", "hex": "#C6A664", "name": "Sand yellow"}, {"code": "RAL 1003", "hex": "#E5BE01", "name": "Signal yellow"}, {"code": "RAL 1004", "hex": "#CDA434", "name": "Golden yellow"}, {"code": "RAL 1005", "hex": "#A98307", "name": "Honey yellow"}, {"code": "RAL 1006", "hex": "#E4A010", "name": "Maize yellow"}, {"code": "RAL 1007", "hex": "#DC9D00", "name": "Daffodil yellow"}, {"code": "RAL 1011", "hex": "#8A6642", "name": "Brown beige"}, {"code": "RAL 1012", "hex": "#C7B446", "name": "Lemon yellow"}, {"code": "RAL 1013", "hex": "#EAE6CA", "name": "Oyster white"}, {"code": "RAL 1014", "hex": "#E1CC4F", "name": "Ivory"}, {"code": "RAL 1015", "hex": "#E6D690", "name": "Light ivory"}, {"code": "RAL 1016", "hex": "#EDFF21", "name": "Sulfur yellow"}, {"code": "RAL 1017", "hex": "#F5D033", "name": "Saffron yellow"}, {"code": "RAL 1018", "hex": "#F8F32B", "name": "Zinc yellow"}, {"code": "RAL 1019", "hex": "#9E9764", "name": "Grey beige"}, {"code": "RAL 1020", "hex": "#999950", "name": "Olive yellow"}, {"code": "RAL 1021", "hex": "#F3DA0B", "name": "Rape yellow"}, {"code": "RAL 1023", "hex": "#FAD201", "name": "Traffic yellow"}, {"code": "RAL 1024", "hex": "#AEA04B", "name": "Ochre yellow"}, {"code": "RAL 1026", "hex": "#FFFF00", "name": "Luminous yellow"}, {"code": "RAL 1027", "hex": "#9D9101", "name": "Curry"}, {"code": "RAL 1028", "hex": "#F4A900", "name": "Melon yellow"}, {"code": "RAL 1032", "hex": "#D6AE01", "name": "Broom yellow"}, {"code": "RAL 1033", "hex": "#F3A505", "name": "Dahlia yellow"}, {"code": "RAL 1034", "hex": "#EFA94A", "name": "Pastel yellow"}, {"code": "RAL 1035", "hex": "#6A5D4D", "name": "Pearl beige"}, {"code": "RAL 1036", "hex": "#705335", "name": "Pearl gold"}, {"code": "RAL 1037", "hex": "#F39F18", "name": "Sun yellow"}, {"code": "RAL 2000", "hex": "#ED760E", "name": "Yellow orange"}, {"code": "RAL 2001", "hex": "#C93C20", "name": "Red orange"}, {"code": "RAL 2002", "hex": "#CB2821", "name": "Vermilion"}, {"code": "RAL 2003", "hex": "#FF7514", "name": "Pastel orange"}, {"code": "RAL 2004", "hex": "#F44611", "name": "Pure orange"}, {"code": "RAL 2005", "hex": "#FF2301", "name": "Luminous orange"}, {"code": "RAL 2007", "hex": "#FFA420", "name": "Luminous bright orange"}, {"code": "RAL 2008", "hex": "#F75E25", "name": "Bright red orange"}, {"code": "RAL 2009", "hex": "#F54021", "name": "Traffic orange"}, {"code": "RAL 2010", "hex": "#D84B20", "name": "Signal orange"}, {"code": "RAL 2011", "hex": "#EC7C26", "name": "Deep orange"}, {"code": "RAL 2012", "hex": "#E55137", "name": "Salmon orange"}, {"code": "RAL 2013", "hex": "#C35831", "name": "Pearl orange"}, {"code": "RAL 3000", "hex": "#AF2B1E", "name": "Flame red"}, {"code": "RAL 3001", "hex": "#A52019", "name": "Signal red"}, {"code": "RAL 3002", "hex": "#A2231D", "name": "Carmine red"}, {"code": "RAL 3003", "hex": "#9B111E", "name": "Ruby red"}, {"code": "RAL 3004", "hex": "#75151E", "name": "Purple red"}, {"code": "RAL 3005", "hex": "#5E2129", "name": "Wine red"}, {"code": "RAL 3007", "hex": "#412227", "name": "Black red"}, {"code": "RAL 3009", "hex": "#642424", "name": "Oxide red"}, {"code": "RAL 3011", "hex": "#781F19", "name": "Brown red"}, {"code": "RAL 3012", "hex": "#C1876B", "name": "Beige red"}, {"code": "RAL 3013", "hex": "#A12312", "name": "Tomato red"}, {"code": "RAL 3014", "hex": "#D36E70", "name": "Antique pink"}, {"code": "RAL 3015", "hex": "#EA899A", "name": "Light pink"}, {"code": "RAL 3016", "hex": "#B32821", "name": "Coral red"}, {"code": "RAL 3017", "hex": "#E63244", "name": "Rose"}, {"code": "RAL 3018", "hex": "#D53032", "name": "Strawberry red"}, {"code": "RAL 3020", "hex": "#CC0605", "name": "Traffic red"}, {"code": "RAL 3022", "hex": "#D95030", "name": "Salmon pink"}, {"code": "RAL 3024", "hex": "#F80000", "name": "Luminous red"}, {"code": "RAL 3026", "hex": "#FE0000", "name": "Luminous bright red"}, {"code": "RAL 3027", "hex": "#C51D34", "name": "Raspberry red"}, {"code": "RAL 3028", "hex": "#CB3234", "name": "Pure red"}, {"code": "RAL 3031", "hex": "#B32428", "name": "Orient red"}, {"code": "RAL 3032", "hex": "#721422", "name": "Pearl ruby red"}, {"code": "RAL 3033", "hex": "#B44C43", "name": "Pearl pink"}, {"code": "RAL 4001", "hex": "#6D3F5B", "name": "Red lilac"}, {"code": "RAL 4002", "hex": "#922B3E", "name": "Red violet"}, {"code": "RAL 4003", "hex": "#DE4C8A", "name": "Heather violet"}, {"code": "RAL 4004", "hex": "#641C34", "name": "Claret violet"}, {"code": "RAL 4005", "hex": "#6C4675", "name": "Blue lilac"}, {"code": "RAL 4006", "hex": "#A03472", "name": "Traffic purple"}, {"code": "RAL 4007", "hex": "#4A192C", "name": "Purple violet"}, {"code": "RAL 4008", "hex": "#924E7D", "name": "Signal violet"}, {"code": "RAL 4009", "hex": "#A18594", "name": "Pastel violet"}, {"code": "RAL 4010", "hex": "#CF3476", "name": "Telemagenta"}, {"code": "RAL 4011", "hex": "#8673A1", "name": "Pearl violet"}, {"code": "RAL 4012", "hex": "#6C6874", "name": "Pearl blackberry"}, {"code": "RAL 5000", "hex": "#354D73", "name": "Violet blue"}, {"code": "RAL 5001", "hex": "#1F3438", "name": "Green blue"}, {"code": "RAL 5002", "hex": "#20214F", "name": "Ultramarine blue"}, {"code": "RAL 5003", "hex": "#1D1E33", "name": "Sapphire blue"}, {"code": "RAL 5004", "hex": "#18171C", "name": "Black blue"}, {"code": "RAL 5005", "hex": "#1E2460", "name": "Signal blue"}, {"code": "RAL 5007", "hex": "#3E5F8A", "name": "Brilliant blue"}, {"code": "RAL 5008", "hex": "#26252D", "name": "Grey blue"}, {"code": "RAL 5009", "hex": "#025669", "name": "Azure blue"}, {"code": "RAL 5010", "hex": "#0E294B", "name": "Gentian blue"}, {"code": "RAL 5011", "hex": "#231A24", "name": "Steel blue"}, {"code": "RAL 5012", "hex": "#3B83BD", "name": "Light blue"}, {"code": "RAL 5013", "hex": "#1E213D", "name": "Cobalt blue"}, {"code": "RAL 5014", "hex": "#606E8C", "name": "Pigeon blue"}, {"code": "RAL 5015", "hex": "#2271B3", "name": "Sky blue"}, {"code": "RAL 5017", "hex": "#063971", "name": "Traffic blue"}, {"code": "RAL 5018", "hex": "#3F888F", "name": "Turquoise blue"}, {"code": "RAL 5019", "hex": "#1B5583", "name": "Capri blue"}, {"code": "RAL 5020", "hex": "#1D334A", "name": "Ocean blue"}, {"code": "RAL 5021", "hex": "#256D7B", "name": "Water blue"}, {"code": "RAL 5022", "hex": "#252850", "name": "Night blue"}, {"code": "RAL 5023", "hex": "#49678D", "name": "Distant blue"}, {"code": "RAL 5024", "hex": "#5D9B9B", "name": "Pastel blue"}, {"code": "RAL 5025", "hex": "#2A6478", "name": "Pearl gentian blue"}, {"code": "RAL 5026", "hex": "#102C54", "name": "Pearl night blue"}, {"code": "RAL 6000", "hex": "#316650", "name": "Patina green"}, {"code": "RAL 6001", "hex": "#287233", "name": "Emerald green"}, {"code": "RAL 6002", "hex": "#2D572C", "name": "Leaf green"}, {"code": "RAL 6003", "hex": "#424632", "name": "Olive green"}, {"code": "RAL 6004", "hex": "#1F3A3D", "name": "Blue green"}, {"code": "RAL 6005", "hex": "#2F4538", "name": "Moss green"}, {"code": "RAL 6006", "hex": "#3E3B32", "name": "Grey olive"}, {"code": "RAL 6007", "hex": "#343B29", "name": "Bottle green"}, {"code": "RAL 6008", "hex": "#39352A", "name": "Brown green"}, {"code": "RAL 6009", "hex": "#31372B", "name": "Fir green"}, {"code": "RAL 6010", "hex": "#35682D", "name": "Grass green"}, {"code": "RAL 6011", "hex": "#587246", "name": "Reseda green"}, {"code": "RAL 6012", "hex": "#343E40", "name": "Black green"}, {"code": "RAL 6013", "hex": "#6C7156", "name": "Reed green"}, {"code": "RAL 6014", "hex": "#47402E", "name": "Yellow olive"}, {"code": "RAL 6015", "hex": "#3B3C36", "name": "Black olive"}, {"code": "RAL 6016", "hex": "#1E5945", "name": "Turquoise green"}, {"code": "RAL 6017", "hex": "#4C9141", "name": "May green"}, {"code": "RAL 6018", "hex": "#57A639", "name": "Yellow green"}, {"code": "RAL 6019", "hex": "#BDECB6", "name": "Pastel green"}, {"code": "RAL 6020", "hex": "#2E3A23", "name": "Chrome green"}, {"code": "RAL 6021", "hex": "#89AC76", "name": "Pale green"}, {"code": "RAL 6022", "hex": "#25221B", "name": "Olive drab"}, {"code": "RAL 6024", "hex": "#308446", "name": "Traffic green"}, {"code": "RAL 6025", "hex": "#3D642D", "name": "Fern green"}, {"code": "RAL 6026", "hex": "#015D52", "name": "Opal green"}, {"code": "RAL 6027", "hex": "#84C3BE", "name": "Light green"}, {"code": "RAL 6028", "hex": "#2C5545", "name": "Pine green"}, {"code": "RAL 6029", "hex": "#20603D", "name": "Mint green"}, {"code": "RAL 6032", "hex": "#317F43", "name": "Signal green"}, {"code": "RAL 6033", "hex": "#497E76", "name": "Mint turquoise"}, {"code": "RAL 6034", "hex": "#7FB5B5", "name": "Pastel turquoise"}, {"code": "RAL 6035", "hex": "#1C542D", "name": "Pearl green"}, {"code": "RAL 6036", "hex": "#193737", "name": "Pearl opal green"}, {"code": "RAL 6037", "hex": "#008F39", "name": "Pure green"}, {"code": "RAL 6038", "hex": "#00BB2D", "name": "Luminous green"}, {"code": "RAL 7000", "hex": "#78858B", "name": "Squirrel grey"}, {"code": "RAL 7001", "hex": "#8A9597", "name": "Silver grey"}, {"code": "RAL 7002", "hex": "#7E7B52", "name": "Olive grey"}, {"code": "RAL 7003", "hex": "#6C7059", "name": "Moss grey"}, {"code": "RAL 7004", "hex": "#969992", "name": "Signal grey"}, {"code": "RAL 7005", "hex": "#646B63", "name": "Mouse grey"}, {"code": "RAL 7006", "hex": "#6D6552", "name": "Beige grey"}, {"code": "RAL 7008", "hex": "#6A5F31", "name": "Khaki grey"}, {"code": "RAL 7009", "hex": "#4D5645", "name": "Green grey"}, {"code": "RAL 7010", "hex": "#4C514A", "name": "Tarpaulin grey"}, {"code": "RAL 7011", "hex": "#434B4D", "name": "Iron grey"}, {"code": "RAL 7012", "hex": "#4E5754", "name": "Basalt grey"}, {"code": "RAL 7013", "hex": "#464531", "name": "Brown grey"}, {"code": "RAL 7015", "hex": "#434750", "name": "Slate grey"}, {"code": "RAL 7016", "hex": "#293133", "name": "Anthracite grey"}, {"code": "RAL 7021", "hex": "#23282B", "name": "Black grey"}, {"code": "RAL 7022", "hex": "#332F2C", "name": "Umbra grey"}, {"code": "RAL 7023", "hex": "#686C5E", "name": "Concrete grey"}, {"code": "RAL 7024", "hex": "#474A51", "name": "Graphite grey"}, {"code": "RAL 7026", "hex": "#2F353B", "name": "Granite grey"}, {"code": "RAL 7030", "hex": "#8B8C7A", "name": "Stone grey"}, {"code": "RAL 7031", "hex": "#474B4E", "name": "Blue grey"}, {"code": "RAL 7032", "hex": "#B8B799", "name": "Pebble grey"}, {"code": "RAL 7033", "hex": "#7D8471", "name": "Cement grey"}, {"code": "RAL 7034", "hex": "#8F8B66", "name": "Yellow grey"}, {"code": "RAL 7035", "hex": "#D7D7D7", "name": "Light grey"}, {"code": "RAL 7036", "hex": "#7F7679", "name": "Platinum grey"}, {"code": "RAL 7037", "hex": "#7D7F7D", "name": "Dusty grey"}, {"code": "RAL 7038", "hex": "#B5B8B1", "name": "Agate grey"}, {"code": "RAL 7039", "hex": "#6C6960", "name": "Quartz grey"}, {"code": "RAL 7040", "hex": "#9DA1AA", "name": "Window grey"}, {"code": "RAL 7042", "hex": "#8D948D", "name": "Traffic grey A"}, {"code": "RAL 7043", "hex": "#4E5452", "name": "Traffic grey B"}, {"code": "RAL 7044", "hex": "#CAC4B0", "name": "Silk grey"}, {"code": "RAL 7045", "hex": "#909090", "name": "Telegrey 1"}, {"code": "RAL 7046", "hex": "#82898F", "name": "Telegrey 2"}, {"code": "RAL 7047", "hex": "#D0D0D0", "name": "Telegrey 4"}, {"code": "RAL 7048", "hex": "#898176", "name": "Pearl mouse grey"}, {"code": "RAL 8000", "hex": "#826C34", "name": "Green brown"}, {"code": "RAL 8001", "hex": "#955F20", "name": "Ochre brown"}, {"code": "RAL 8002", "hex": "#6C3B2A", "name": "Signal brown"}, {"code": "RAL 8003", "hex": "#734222", "name": "Clay brown"}, {"code": "RAL 8004", "hex": "#8E402A", "name": "Copper brown"}, {"code": "RAL 8007", "hex": "#59351F", "name": "Fawn brown"}, {"code": "RAL 8008", "hex": "#6F4F28", "name": "Olive brown"}, {"code": "RAL 8011", "hex": "#5B3A29", "name": "Nut brown"}, {"code": "RAL 8012", "hex": "#592321", "name": "Red brown"}, {"code": "RAL 8014", "hex": "#382C1E", "name": "Sepia brown"}, {"code": "RAL 8015", "hex": "#633A34", "name": "Chestnut brown"}, {"code": "RAL 8016", "hex": "#4C2F27", "name": "Mahogany brown"}, {"code": "RAL 8017", "hex": "#45322E", "name": "Chocolate brown"}, {"code": "RAL 8019", "hex": "#403A3A", "name": "Grey brown"}, {"code": "RAL 8022", "hex": "#212121", "name": "Black brown"}, {"code": "RAL 8023", "hex": "#A65E2E", "name": "Orange brown"}, {"code": "RAL 8024", "hex": "#79553D", "name": "Beige brown"}, {"code": "RAL 8025", "hex": "#755C48", "name": "Pale brown"}, {"code": "RAL 8028", "hex": "#4E3B31", "name": "Terra brown"}, {"code": "RAL 8029", "hex": "#763C28", "name": "Pearl copper"}, {"code": "RAL 9001", "hex": "#FDF4E3", "name": "Cream"}, {"code": "RAL 9002", "hex": "#E7EBDA", "name": "Grey white"}, {"code": "RAL 9003", "hex": "#F4F4F4", "name": "Signal white"}, {"code": "RAL 9004", "hex": "#282828", "name": "Signal black"}, {"code": "RAL 9005", "hex": "#0A0A0A", "name": "Jet black"}, {"code": "RAL 9006", "hex": "#A5A5A5", "name": "White aluminium"}, {"code": "RAL 9007", "hex": "#8F8F8F", "name": "Grey aluminium"}, {"code": "RAL 9010", "hex": "#FFFFFF", "name": "Pure white"}, {"code": "RAL 9011", "hex": "#1C1C1C", "name": "Graphite black"}, {"code": "RAL 9016", "hex": "#F6F6F6", "name": "Traffic white"}, {"code": "RAL 9017", "hex": "#1E1E1E", "name": "Traffic black"}, {"code": "RAL 9018", "hex": "#D7D7D7", "name": "Papyrus white"}, {"code": "RAL 9022", "hex": "#9C9C9C", "name": "Pearl light grey"}, {"code": "RAL 9023", "hex": "#828282", "name": "Pearl dark grey"}].freeze
    NCS_PRESETS=['NCS S 0500-N','NCS S 1000-N','NCS S 1500-N','NCS S 2000-N','NCS S 2500-N','NCS S 3000-N','NCS S 4000-N','NCS S 5000-N','NCS S 6000-N','NCS S 7000-N','NCS S 8000-N','NCS S 9000-N','NCS S 0502-Y','NCS S 1002-Y','NCS S 1502-Y','NCS S 2005-Y20R','NCS S 3010-Y20R','NCS S 2020-Y20R','NCS S 3020-Y30R','NCS S 3050-Y70R','NCS S 2050-R','NCS S 3050-R20B','NCS S 4050-R50B','NCS S 3050-B','NCS S 2050-B30G','NCS S 2060-B','NCS S 2040-G20Y','NCS S 2060-G20Y','NCS S 3010-G20Y','NCS S 4020-G30Y','NCS S 4040-G50Y'].freeze

    def init
      return if @loaded
      @loaded=true
      ensure_library!
      create_command
      create_menu
      create_toolbar
    end

    def create_command
      @cmd_open=UI::Command.new('20-20 Texture Library'){show_dialog}
      @cmd_open.tooltip='20-20 Texture Library – vlastní textury, SIKO obklady, EGGER dekory, Poly Haven CC0, RAL a NCS'
      @cmd_open.status_bar_text='Otevře knihovnu textur, SIKO obkladů, EGGER dekorů, Poly Haven materiálů a barev pro rychlé mapování klikáním na plochy.'
      icon=File.join(__dir__,'icons','texture_library.png')
      if File.exist?(icon)
        @cmd_open.small_icon=icon
        @cmd_open.large_icon=icon
      end
    end

    def create_menu
      UI.menu('Extensions').add_item(@cmd_open)
      UI.menu('Tools').add_item(@cmd_open)
    end

    def create_toolbar
      @toolbar=UI::Toolbar.new('20-20 Texture Library')
      @toolbar.add_item(@cmd_open)
      @toolbar.restore
    rescue StandardError
      nil
    end

    def ensure_library!
      FileUtils.mkdir_p([TEX_ROOT,SIKO_CACHE,EGGER_CACHE,POLYHAVEN_CACHE])
      File.write(LIB_JSON,JSON.pretty_generate({'textures'=>[]})) unless File.exist?(LIB_JSON)
    end

    def read_library
      ensure_library!
      data=JSON.parse(File.read(LIB_JSON)); data['textures']||=[]; data
    rescue StandardError
      {'textures'=>[]}
    end

    def write_library(data)
      ensure_library!; File.write(LIB_JSON,JSON.pretty_generate(data))
    end

    def read_siko_catalog(kind='concrete')
      path=kind.to_s=='floor' ? SIKO_FLOOR_JSON : SIKO_CONCRETE_JSON
      return [] unless File.file?(path)
      data=JSON.parse(File.read(path,encoding:'UTF-8'))
      Array(data['items'])
    rescue StandardError
      []
    end

    def siko_record(code,kind='concrete')
      read_siko_catalog(kind).find{|x|x['code'].to_s==code.to_s}
    end

    def read_egger_catalog
      return [] unless File.file?(EGGER_JSON)
      data=JSON.parse(File.read(EGGER_JSON,encoding:'UTF-8'))
      Array(data['items'])
    rescue StandardError
      []
    end

    def egger_record(code)
      read_egger_catalog.find{|x|x['code'].to_s.casecmp(code.to_s).zero?}
    end

    def polyhaven_api_json(path)
      uri=URI.parse("#{POLYHAVEN_API}#{path}")
      req=Net::HTTP::Get.new(uri.request_uri,{'User-Agent'=>POLYHAVEN_UA,'Accept'=>'application/json'})
      response=Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:8,read_timeout:35){|http|http.request(req)}
      raise "Poly Haven API HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end

    def polyhaven_catalog(force=false)
      FileUtils.mkdir_p(POLYHAVEN_CACHE)
      if !force && @polyhaven_catalog && @polyhaven_catalog_loaded_at && (Time.now-@polyhaven_catalog_loaded_at)<21_600
        return @polyhaven_catalog
      end

      data=nil
      if !force && File.file?(POLYHAVEN_META) && (Time.now-File.mtime(POLYHAVEN_META))<21_600
        begin
          cached=JSON.parse(File.read(POLYHAVEN_META,encoding:'UTF-8'))
          data=Array(cached['items'])
        rescue StandardError
          data=nil
        end
      end

      unless data
        raw=polyhaven_api_json('/assets?type=textures')
        data=raw.map do |id,x|
          next unless x.is_a?(Hash) && x['type'].to_i==1
          path=x['category'].to_s
          top=path.split('/').first.to_s
          dims=Array(x['dimensions'])
          {
            'id'=>id.to_s,
            'name'=>(x['name'].to_s.empty? ? id.to_s : x['name'].to_s),
            'category'=>(top.empty? ? 'Other' : top),
            'category_path'=>path,
            'tags'=>Array(x['tags']),
            'thumbnail_url'=>x['thumbnail_url'].to_s,
            'dimensions'=>dims,
            'download_count'=>x['download_count'].to_i
          }
        end.compact
        data.sort_by!{|x|[-x['download_count'].to_i,x['name'].to_s.downcase]}
        File.write(POLYHAVEN_META,JSON.pretty_generate({'updated_at'=>Time.now.to_i,'items'=>data}))
      end

      @polyhaven_catalog=data
      @polyhaven_by_id={}
      data.each{|x|@polyhaven_by_id[x['id'].to_s]=x}
      @polyhaven_catalog_loaded_at=Time.now
      data
    rescue StandardError => e
      # Offline fallback: keep the last cache even if older than the normal TTL.
      if File.file?(POLYHAVEN_META)
        begin
          cached=JSON.parse(File.read(POLYHAVEN_META,encoding:'UTF-8'))
          data=Array(cached['items'])
          @polyhaven_catalog=data
          @polyhaven_by_id={}
          data.each{|x|@polyhaven_by_id[x['id'].to_s]=x}
          @polyhaven_catalog_loaded_at=Time.now
          return data
        rescue StandardError
          nil
        end
      end
      raise e
    end

    def polyhaven_record(id)
      polyhaven_catalog(false) unless @polyhaven_by_id
      @polyhaven_by_id && @polyhaven_by_id[id.to_s]
    end

    def push_polyhaven_to_dialog(force=false)
      return unless @dialog
      items=polyhaven_catalog(force)
      @dialog.execute_script("window.setPolyHaven(#{JSON.generate(items)});")
    rescue StandardError => e
      @dialog.execute_script("window.setPolyHavenError(#{JSON.generate(e.message)});") rescue nil
    end

    def polyhaven_files(id)
      polyhaven_api_json("/files/#{URI.encode_www_form_component(id.to_s)}")
    end

    def polyhaven_diffuse_file(files,resolution='2k')
      diffuse=files['Diffuse'] || files['diffuse'] || files['diff']
      return nil unless diffuse.is_a?(Hash)
      wanted=[resolution.to_s.downcase,'2k','1k','4k','8k'].uniq
      wanted.each do |res|
        block=diffuse[res]
        next unless block.is_a?(Hash)
        %w[jpg png].each do |fmt|
          file=block[fmt]
          return [file,res,fmt] if file.is_a?(Hash) && file['url'].to_s.start_with?('https://')
        end
      end
      nil
    end

    def polyhaven_texture_path(rec,resolution='2k')
      files=polyhaven_files(rec['id'])
      picked=polyhaven_diffuse_file(files,resolution)
      raise 'Poly Haven u tohoto materiálu nenabízí Diffuse JPG/PNG.' unless picked
      file,actual_res,fmt=picked
      safe=rec['id'].to_s.gsub(/[^0-9A-Za-z._-]+/,'_')
      target=File.join(POLYHAVEN_CACHE,"#{safe}_diff_#{actual_res}.#{fmt}")
      unless File.file?(target) && File.size(target)>512
        uri=URI.parse(file['url'].to_s)
        req=Net::HTTP::Get.new(uri.request_uri,{'User-Agent'=>POLYHAVEN_UA})
        response=Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:10,read_timeout:90){|http|http.request(req)}
        raise "Stažení Poly Haven selhalo (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target,response.body)
      end
      [target,actual_res]
    end

    def polyhaven_texture_size(rec,path)
      dims=Array(rec['dimensions'])
      w=dims[0].to_f
      h=dims[1].to_f
      w=1000.0 if w<=0
      h=1000.0 if h<=0
      begin
        rep=Sketchup::ImageRep.new
        rep.load_file(path)
        iw=rep.width.to_f
        ih=rep.height.to_f
        return [w.mm,h.mm,'api_dimensions'] unless iw>0 && ih>0
        image_ratio=iw/ih
        real_ratio=w/h
        return [w.mm,h.mm,'api_dimensions'] if (Math.log(image_ratio/real_ratio)).abs<=0.12
        long_side=[w,h].max
        if image_ratio>=1.0
          [long_side.mm,(long_side/image_ratio).mm,'source_aspect_safe']
        else
          [(long_side*image_ratio).mm,long_side.mm,'source_aspect_safe']
        end
      rescue StandardError
        [w.mm,h.mm,'api_dimensions_fallback']
      end
    end

    def download_https(url,target,limit=5)
      raise 'Příliš mnoho přesměrování.' if limit<=0
      uri=URI.parse(url.to_s)
      raise 'Neplatná adresa obrázku.' unless uri.is_a?(URI::HTTPS)
      req=Net::HTTP::Get.new(uri.request_uri,{'User-Agent'=>'20-20 Texture Library/0.2.0'})
      response=Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:8,read_timeout:25){|http|http.request(req)}
      case response
      when Net::HTTPSuccess
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target,response.body)
        target
      when Net::HTTPRedirection
        download_https(URI.join(uri.to_s,response['location']).to_s,target,limit-1)
      else
        raise "Stažení obrázku selhalo (HTTP #{response.code})."
      end
    end

    def siko_texture_path(rec)
      url=rec['image_url'].to_s
      raise 'U produktu chybí obrázek.' if url.empty?
      ext=File.extname(URI.parse(url).path).downcase
      ext='.jpg' unless %w[.jpg .jpeg .png .webp .bmp].include?(ext)
      safe=rec['code'].to_s.gsub(/[^0-9A-Za-z._-]+/,'_')
      target=File.join(SIKO_CACHE,"#{safe}#{ext}")
      download_https(url,target) unless File.file?(target) && File.size(target)>256
      target
    end

    def egger_texture_path(rec)
      url=rec['image_url'].to_s
      raise 'U dekoru EGGER chybí obrázek.' if url.empty?
      ext=File.extname(URI.parse(url).path).downcase
      ext='.jpg' unless %w[.jpg .jpeg .png .webp .bmp].include?(ext)
      safe=rec['code'].to_s.gsub(/[^0-9A-Za-z._-]+/,'_')
      target=File.join(EGGER_CACHE,"#{safe}#{ext}")
      download_https(url,target) unless File.file?(target) && File.size(target)>256
      target
    end

    def egger_texture_size(rec,path)
      w=rec['width_mm'].to_f
      h=rec['height_mm'].to_f
      w=2311.0 if w<=0
      h=1300.0 if h<=0
      begin
        rep=Sketchup::ImageRep.new
        rep.load_file(path)
        iw=rep.width.to_f
        ih=rep.height.to_f
        return [w.mm,h.mm,'catalog'] unless iw>0 && ih>0
        image_ratio=iw/ih
        catalog_ratio=w/h
        if (Math.log(image_ratio/catalog_ratio)).abs<=0.10
          [w.mm,h.mm,'catalog']
        else
          long_side=[w,h].max
          if image_ratio>=1.0
            [long_side.mm,(long_side/image_ratio).mm,'source_aspect_safe']
          else
            [(long_side*image_ratio).mm,long_side.mm,'source_aspect_safe']
          end
        end
      rescue StandardError
        [w.mm,h.mm,'catalog_fallback']
      end
    end

    # Never deform a SIKO source image just to force it into the declared tile ratio.
    # If the image already matches the product (also allowing a 90° orientation), use
    # the exact declared dimensions. Otherwise keep the source-image aspect ratio and
    # anchor its longer side to the longer declared product side.
    def siko_texture_size(rec,path)
      w=rec['width_cm'].to_f*10.0
      h=rec['height_cm'].to_f*10.0
      return nil unless w>0 && h>0

      begin
        rep=Sketchup::ImageRep.new
        rep.load_file(path)
        iw=rep.width.to_f
        ih=rep.height.to_f
        return [w.mm,h.mm,'product_fallback'] unless iw>0 && ih>0

        image_ratio=iw/ih
        normal_ratio=w/h
        swapped_ratio=h/w
        normal_error=(Math.log(image_ratio/normal_ratio)).abs
        swapped_error=(Math.log(image_ratio/swapped_ratio)).abs

        if [normal_error,swapped_error].min<=0.12
          return swapped_error<normal_error ? [h.mm,w.mm,'product_rotated'] : [w.mm,h.mm,'product']
        end

        long_side=[w,h].max
        if image_ratio>=1.0
          fixed_w=long_side
          fixed_h=long_side/image_ratio
        else
          fixed_h=long_side
          fixed_w=long_side*image_ratio
        end
        [fixed_w.mm,fixed_h.mm,'source_aspect_safe']
      rescue StandardError
        # Even if ImageRep inspection fails, use a square safe fallback instead of
        # visibly stretching an unknown source image into a rectangular product ratio.
        long_side=[w,h].max
        [long_side.mm,long_side.mm,'safe_square_fallback']
      end
    end

    def face_texture_axes(face)
      edge=face.edges.max_by{|e|e.length.to_f}
      return nil unless edge
      u=edge.line[1].clone
      u.normalize!
      n=face.normal.clone
      n.normalize!
      v=n.cross(u)
      return nil if v.length.to_f<=0.000001
      v.normalize!
      [u,v]
    rescue StandardError
      nil
    end

    def apply_face_mapping(face,material,x_mm=0.0,y_mm=0.0,rotation_deg=0.0,record_operation=true)
      return false unless face && face.valid? && material && material.texture
      axes=face_texture_axes(face)
      return false unless axes
      u,v=axes
      angle=rotation_deg.to_f.degrees
      ca=Math.cos(angle); sa=Math.sin(angle)
      ru=Geom::Vector3d.new(u.x*ca+v.x*sa,u.y*ca+v.y*sa,u.z*ca+v.z*sa)
      rv=Geom::Vector3d.new(-u.x*sa+v.x*ca,-u.y*sa+v.y*ca,-u.z*sa+v.z*ca)
      ru.normalize!; rv.normalize!
      origin=face.vertices.first.position
      p0=origin.offset(ru,x_mm.to_f.mm).offset(rv,y_mm.to_f.mm)
      p1=p0.offset(ru,material.texture.width)
      p2=p0.offset(rv,material.texture.height)
      mapping=[
        p0,Geom::Point3d.new(0,0,0),
        p1,Geom::Point3d.new(1,0,0),
        p2,Geom::Point3d.new(0,1,0)
      ]
      model=Sketchup.active_model
      model.start_operation('20-20 Upravit mapování textury',true,false,true) if record_operation
      face.position_material(material,mapping,true)
      face.set_attribute('20-20 Texture Library','map_x_mm',x_mm.to_f)
      face.set_attribute('20-20 Texture Library','map_y_mm',y_mm.to_f)
      face.set_attribute('20-20 Texture Library','map_rotation_deg',rotation_deg.to_f)
      model.commit_operation if record_operation
      model.active_view.invalidate
      true
    rescue StandardError => e
      Sketchup.active_model.abort_operation rescue nil if record_operation
      UI.messagebox("Úprava mapování selhala:\n#{e.class}: #{e.message}") if record_operation
      false
    end

    def open_texture_positioner
      model=Sketchup.active_model
      faces=model.selection.grep(Sketchup::Face)
      return UI.messagebox('Vyber přesně jednu plochu, jejíž texturu chceš posunout nebo otočit.') unless faces.length==1
      face=faces.first
      material=face.material
      return UI.messagebox('Vybraná plocha nemá na přední straně materiál.') unless material
      return UI.messagebox('Materiál na vybrané ploše nemá texturu.') unless material.texture

      @position_face=face
      @position_material=material
      x=face.get_attribute('20-20 Texture Library','map_x_mm',0.0).to_f
      y=face.get_attribute('20-20 Texture Library','map_y_mm',0.0).to_f
      rot=face.get_attribute('20-20 Texture Library','map_rotation_deg',0.0).to_f

      @position_dialog.close rescue nil if @position_dialog
      dlg=UI::HtmlDialog.new(
        dialog_title:'20-20 – Pozice textury',
        preferences_key:'twentytwenty_texture_positioner_v1',
        scrollable:false,resizable:true,width:520,height:390,min_width:430,min_height:330,
        style:UI::HtmlDialog::STYLE_DIALOG
      )
      dlg.set_html(texture_positioner_html(material.display_name,x,y,rot))
      dlg.add_action_callback('adjust_texture'){|_ctx,payload|
        begin
          data=JSON.parse(payload.to_s)
          face_ref=@position_face
          mat_ref=@position_material
          next unless face_ref && face_ref.valid? && mat_ref && mat_ref.texture
          apply_face_mapping(face_ref,mat_ref,data['x'].to_f,data['y'].to_f,data['rotation'].to_f,true)
        rescue StandardError => e
          UI.messagebox("Úprava mapování selhala:\n#{e.class}: #{e.message}")
        end
      }
      dlg.add_action_callback('reset_texture'){|_ctx|
        if @position_face && @position_face.valid? && @position_material
          apply_face_mapping(@position_face,@position_material,0.0,0.0,0.0,true)
        end
      }
      dlg.add_action_callback('close_positioner'){|_ctx| dlg.close}
      dlg.set_on_closed{@position_dialog=nil;@position_face=nil;@position_material=nil}
      @position_dialog=dlg
      dlg.show
      dlg.bring_to_front
    rescue StandardError => e
      UI.messagebox("Pozice textury: #{e.class}: #{e.message}")
    end

    def texture_positioner_html(material_name,x,y,rot)
      safe_name=material_name.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;')
      <<~HTML
<!doctype html><html lang="cs"><head><meta charset="utf-8"><style>
*{box-sizing:border-box}body{margin:0;background:#f5f5f5;color:#18181b;font:13px system-ui,Segoe UI,sans-serif}.head{background:#f7f197;border-bottom:1px solid #d8d16d;padding:14px 16px}.head b{font-size:16px}.head div{font-size:10px;margin-top:3px;color:#555}.wrap{padding:16px}.row{display:grid;grid-template-columns:82px 1fr 92px;gap:10px;align-items:center;margin:15px 0}.row label{font-weight:700}.row input[type=range]{width:100%}.row input[type=number]{width:100%;padding:7px;border:1px solid #ccc;border-radius:7px}.buttons{display:flex;gap:8px;margin-top:22px}.btn{border:1px solid #ccc;background:#fff;border-radius:8px;padding:9px 12px;cursor:pointer}.primary{background:#18181b;color:#fff;border-color:#18181b}.hint{font-size:11px;color:#666;line-height:1.45;margin-top:14px}
</style></head><body><div class="head"><b>Pozice textury na vybrané ploše</b><div>#{safe_name}</div></div><div class="wrap">
<div class="row"><label>Posun X</label><input id="xr" type="range" min="-3000" max="3000" step="1" value="#{x}"><input id="xn" type="number" step="1" value="#{x}"></div>
<div class="row"><label>Posun Y</label><input id="yr" type="range" min="-3000" max="3000" step="1" value="#{y}"><input id="yn" type="number" step="1" value="#{y}"></div>
<div class="row"><label>Rotace</label><input id="rr" type="range" min="-180" max="180" step="1" value="#{rot}"><input id="rn" type="number" min="-360" max="360" step="1" value="#{rot}"></div>
<div class="buttons"><button class="btn" onclick="resetAll()">Reset</button><button class="btn primary" onclick="sketchup.close_positioner()">Hotovo</button></div>
<div class="hint">X/Y jsou v milimetrech. Úprava se týká pouze právě vybrané plochy; ostatní plochy se stejným materiálem zůstanou beze změny.</div>
</div><script>
let timer=null;function send(){clearTimeout(timer);timer=setTimeout(()=>sketchup.adjust_texture(JSON.stringify({x:+xn.value||0,y:+yn.value||0,rotation:+rn.value||0})),35)}
function pair(range,num){range.addEventListener('input',()=>{num.value=range.value;send()});num.addEventListener('input',()=>{range.value=num.value;send()})}
const xr=document.getElementById('xr'),xn=document.getElementById('xn'),yr=document.getElementById('yr'),yn=document.getElementById('yn'),rr=document.getElementById('rr'),rn=document.getElementById('rn');pair(xr,xn);pair(yr,yn);pair(rr,rn);
function resetAll(){xr.value=xn.value=0;yr.value=yn.value=0;rr.value=rn.value=0;sketchup.reset_texture()}
</script></body></html>
      HTML
    end

    def show_dialog
      @dialog=build_dialog if @dialog.nil?
      @dialog.show
      @dialog.bring_to_front
      push_library_to_dialog
    rescue StandardError => e
      @dialog=nil
      UI.messagebox("Texture Library: #{e.class}: #{e.message}")
    end

    def build_dialog
      dlg=UI::HtmlDialog.new(dialog_title:"20-20 Texture Library v#{VERSION}",preferences_key:PREF_KEY,scrollable:true,resizable:true,width:900,height:720,min_width:700,min_height:520,style:UI::HtmlDialog::STYLE_DIALOG)
      dlg.set_html(dialog_html)
      dlg.add_action_callback('ready'){|_ctx| push_library_to_dialog}
      dlg.add_action_callback('add_texture'){|_ctx| add_custom_texture}
      dlg.add_action_callback('delete_texture'){|_ctx,id| delete_custom_texture(id.to_s)}
      dlg.add_action_callback('paint'){|_ctx,payload| activate_paint_tool(payload)}
      dlg.add_action_callback('refresh_polyhaven'){|_ctx| push_polyhaven_to_dialog(true)}
      dlg.add_action_callback('open_positioner'){|_ctx| open_texture_positioner}
      dlg.add_action_callback('open_url'){|_ctx,url|
        u=url.to_s
        UI.openURL(u) if u.start_with?('https://www.siko.cz/') || u.start_with?('https://www.egger.com/') || u.start_with?('https://www.sketchuptextureclub.com/')
      }
      dlg.add_action_callback('close_dialog'){|_ctx| dlg.close}
      dlg.set_on_closed{@dialog=nil}
      dlg
    end

    def push_library_to_dialog
      return unless @dialog
      @dialog.execute_script("window.setCustomTextures(#{JSON.generate(read_library['textures'])});")
      @dialog.execute_script("window.setSikoTiles(#{JSON.generate(read_siko_catalog('concrete'))});")
      @dialog.execute_script("window.setSikoFloorTiles(#{JSON.generate(read_siko_catalog('floor'))});")
      @dialog.execute_script("window.setEggerDecors(#{JSON.generate(read_egger_catalog)});")
      UI.start_timer(0.05,false){push_polyhaven_to_dialog(false)}
    rescue StandardError
      nil
    end

    def normalize_texture_image(source,id)
      ext=File.extname(source.to_s).downcase
      return source if %w[.jpg .jpeg .png].include?(ext)

      # Chromium can preview WebP/BMP even when SketchUp's material decoder cannot.
      # Convert through SketchUp ImageRep whenever possible so the material receives a real PNG.
      if defined?(Sketchup::ImageRep)
        begin
          rep=Sketchup::ImageRep.new
          rep.load_file(source)
          target=File.join(TEX_ROOT,"#{id}.png")
          rep.save_file(target)
          return target if File.file?(target) && File.size(target)>0
        rescue StandardError
          nil
        end
      end

      raise "Formát #{ext.empty? ? 'obrázku' : ext} lze zobrazit v náhledu, ale SketchUp ho neumí spolehlivě použít jako texturu. Ulož obrázek jako PNG nebo JPG."
    end

    def add_custom_texture
      path=UI.openpanel('Vyber texturu',nil,'Obrázky|*.png;*.jpg;*.jpeg;*.webp;*.bmp||')
      return unless path && File.file?(path)
      base=File.basename(path,'.*')
      values=UI.inputbox(['Název textury:','Reálná šířka vzoru [mm]:','Reálná výška vzoru [mm]:'],[base,1000.0,1000.0],'Přidat texturu do knihovny')
      return unless values
      name=values[0].to_s.strip; name=base if name.empty?
      width_mm=[values[1].to_f,1.0].max; height_mm=[values[2].to_f,1.0].max
      id=SecureRandom.hex(6)
      ext=File.extname(path).downcase
      copied=File.join(TEX_ROOT,"#{id}#{ext}")
      FileUtils.cp(path,copied)
      target=normalize_texture_image(copied,id)
      if target!=copied && File.file?(copied)
        File.delete(copied) rescue nil
      end
      data=read_library
      data['textures'] << {'id'=>id,'name'=>name,'path'=>target,'width_mm'=>width_mm,'height_mm'=>height_mm}
      write_library(data); push_library_to_dialog
    rescue StandardError => e
      UI.messagebox("Přidání textury selhalo:\n#{e.class}: #{e.message}")
    end

    def delete_custom_texture(id)
      data=read_library; before=data['textures'].length
      data['textures'].reject!{|t| t['id'].to_s==id.to_s}
      write_library(data); push_library_to_dialog
      UI.messagebox('Textura byla odebrána z knihovny.') if data['textures'].length<before
    rescue StandardError => e
      UI.messagebox("Smazání textury selhalo:\n#{e.class}: #{e.message}")
    end

    def activate_paint_tool(payload)
      data=JSON.parse(payload.to_s); material=material_from_payload(data); return unless material
      Sketchup.active_model.select_tool(PaintFacesTool.new(material))
    rescue StandardError => e
      UI.messagebox("Mapování selhalo:\n#{e.class}: #{e.message}")
    end

    def material_from_payload(data)
      model=Sketchup.active_model; kind=data['kind'].to_s
      if kind=='custom'
        lib=read_library
        rec=lib['textures'].find{|t|t['id'].to_s==data['id'].to_s}
        return UI.messagebox('Textura už není v knihovně.') unless rec && File.file?(rec['path'].to_s)
        path=rec['path'].to_s
        begin
          normalized=normalize_texture_image(path,rec['id'].to_s)
          if normalized!=path
            rec['path']=normalized
            write_library(lib)
            push_library_to_dialog
            path=normalized
          end
        rescue StandardError => e
          return UI.messagebox("Texturu se nepodařilo připravit pro SketchUp:\n#{e.message}")
        end
        mat_name="20-20 TEX | #{rec['name']}"; mat=model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture=path
        return UI.messagebox('SketchUp obrázek nenačetl jako texturu. Použij PNG nebo JPG.') unless mat.texture
        begin; mat.texture.size=[rec['width_mm'].to_f.mm,rec['height_mm'].to_f.mm]; rescue StandardError; end
        mat
      elsif kind=='siko' || kind=='siko_floor'
        catalog_kind=kind=='siko_floor' ? 'floor' : 'concrete'
        rec=siko_record(data['code'],catalog_kind)
        label=catalog_kind=='floor' ? 'Dlažby' : 'Betonové obklady'
        return UI.messagebox("Produkt už není v katalogu #{label}.") unless rec
        path=siko_texture_path(rec)
        mat_name="20-20 SIKO | #{rec['name']}"; mat=model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture=path
        return UI.messagebox('Obrázek SIKO se nepodařilo načíst jako SketchUp texturu.') unless mat.texture
        size_info=siko_texture_size(rec,path)
        begin
          mat.texture.size=[size_info[0],size_info[1]] if size_info
        rescue StandardError
        end
        begin
          mat.set_attribute('20-20 Texture Library','source','SIKO')
          mat.set_attribute('20-20 Texture Library','catalog',catalog_kind)
          mat.set_attribute('20-20 Texture Library','product_url',rec['product_url'].to_s)
          mat.set_attribute('20-20 Texture Library','product_code',rec['code'].to_s)
          mat.set_attribute('20-20 Texture Library','size_cm',rec['size_cm'].to_s)
          mat.set_attribute('20-20 Texture Library','texture_size_mode',size_info ? size_info[2] : 'unknown')
        rescue StandardError
        end
        mat
      elsif kind=='egger'
        rec=egger_record(data['code'])
        return UI.messagebox('Dekor už není v katalogu EGGER.') unless rec
        path=egger_texture_path(rec)
        mat_name="20-20 EGGER | #{rec['code']} | #{rec['name']}"; mat=model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture=path
        return UI.messagebox('Obrázek EGGER se nepodařilo načíst jako SketchUp texturu.') unless mat.texture
        size_info=egger_texture_size(rec,path)
        begin
          mat.texture.size=[size_info[0],size_info[1]] if size_info
        rescue StandardError
        end
        begin
          mat.set_attribute('20-20 Texture Library','source','EGGER')
          mat.set_attribute('20-20 Texture Library','manufacturer','EGGER')
          mat.set_attribute('20-20 Texture Library','decor_code',rec['code'].to_s)
          mat.set_attribute('20-20 Texture Library','product_url',rec['product_url'].to_s)
          mat.set_attribute('20-20 Texture Library','directional',rec['directional'] ? true : false)
          mat.set_attribute('20-20 Texture Library','texture_size_mode',size_info ? size_info[2] : 'unknown')
        rescue StandardError
        end
        mat
      elsif kind=='polyhaven'
        rec=polyhaven_record(data['id'])
        return UI.messagebox('Materiál už není v katalogu Poly Haven.') unless rec
        requested=data['resolution'].to_s
        requested='2k' unless %w[1k 2k 4k].include?(requested)
        path,actual_res=polyhaven_texture_path(rec,requested)
        mat_name="20-20 POLY HAVEN | #{rec['name']}"; mat=model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture=path
        return UI.messagebox('Diffuse mapa Poly Haven se nepodařila načíst jako SketchUp textura.') unless mat.texture
        size_info=polyhaven_texture_size(rec,path)
        begin
          mat.texture.size=[size_info[0],size_info[1]] if size_info
        rescue StandardError
        end
        begin
          mat.set_attribute('20-20 Texture Library','source','Poly Haven')
          mat.set_attribute('20-20 Texture Library','license','CC0')
          mat.set_attribute('20-20 Texture Library','asset_id',rec['id'].to_s)
          mat.set_attribute('20-20 Texture Library','category',rec['category_path'].to_s)
          mat.set_attribute('20-20 Texture Library','resolution',actual_res.to_s)
          mat.set_attribute('20-20 Texture Library','texture_size_mode',size_info ? size_info[2] : 'unknown')
        rescue StandardError
        end
        @dialog.execute_script("window.polyHavenReady && window.polyHavenReady(#{JSON.generate(rec['id'])},#{JSON.generate(actual_res)});") rescue nil
        mat
      else
        name=data['name'].to_s; rgb=hex_to_rgb(data['hex'].to_s); return UI.messagebox('Neplatná barva.') unless rgb
        mat_name="20-20 #{name}"; mat=model.materials[mat_name] || model.materials.add(mat_name); mat.color=Sketchup::Color.new(*rgb); mat
      end
    end

    def hex_to_rgb(hex)
      m=hex.to_s.strip.match(/\A#?([0-9a-fA-F]{6})\z/); return nil unless m
      s=m[1]; [s[0,2].to_i(16),s[2,2].to_i(16),s[4,2].to_i(16)]
    end

    class PaintFacesTool
      def initialize(material); @material=material; end
      def activate; Sketchup.status_text="20-20 Texture Library: klikáním aplikuj '#{@material.display_name}'. Esc = konec."; end
      def deactivate(_view); Sketchup.status_text=''; end
      def onCancel(_reason,_view); Sketchup.active_model.select_tool(nil); end
      def onKeyDown(key,_repeat,_flags,_view); Sketchup.active_model.select_tool(nil) if key==27; end
      def onLButtonDown(_flags,x,y,view)
        ph=view.pick_helper; ph.do_pick(x,y); face=nil
        (0...ph.count).each do |i|
          path=ph.path_at(i); next unless path
          candidate=path.reverse.find{|e| e.is_a?(Sketchup::Face)}
          if candidate; face=candidate; break; end
        end
        return unless face
        model=Sketchup.active_model
        model.start_operation('20-20 Paint Texture',true)
        face.material=@material
        TwentyTwenty::TextureLibrary.apply_face_mapping(face,@material,0.0,0.0,0.0,false) if @material.texture
        model.commit_operation
        view.invalidate
      rescue StandardError => e
        Sketchup.active_model.abort_operation rescue nil
        UI.messagebox("Aplikace materiálu selhala:\n#{e.class}: #{e.message}")
      end
    end

    def dialog_html
      ral_json=JSON.generate(RAL); ncs_json=JSON.generate(NCS_PRESETS)
      <<~HTML
<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
:root{--bg:#f5f5f5;--card:#fff;--line:#dedede;--text:#18181b;--muted:#71717a;--yellow:#f7f197}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:13px system-ui,Segoe UI,sans-serif}.head{position:sticky;top:0;z-index:10;background:var(--yellow);border-bottom:1px solid #d8d16d;padding:13px 16px;display:flex;align-items:center;justify-content:space-between}.head b{font-size:17px}.wrap{padding:14px}.tabs{display:flex;gap:7px;flex-wrap:wrap}.tab{border:1px solid var(--line);background:#fff;border-radius:8px;padding:8px 12px;cursor:pointer}.tab.active{background:#18181b;color:#fff;border-color:#18181b}.toolbar{display:flex;gap:8px;margin:12px 0;align-items:center;flex-wrap:wrap}.search{flex:1;min-width:220px;border:1px solid var(--line);border-radius:8px;padding:9px}.filters{display:none;grid-template-columns:repeat(4,minmax(120px,1fr)) auto;gap:7px;margin:-3px 0 12px;align-items:center}.filters select{width:100%;min-width:0;border:1px solid var(--line);border-radius:8px;background:#fff;padding:8px;font:inherit}.filter-reset{white-space:nowrap}.result-count{grid-column:1/-1;font-size:10px;color:var(--muted);margin-top:-1px}.color-pill{display:inline-flex;align-items:center;gap:5px}.color-dot{width:9px;height:9px;border:1px solid #aaa;border-radius:50%;display:inline-block}@media(max-width:760px){.filters{grid-template-columns:1fr 1fr}.filter-reset{grid-column:1/-1}.result-count{grid-column:1/-1}}.btn{border:1px solid var(--line);background:#fff;border-radius:8px;padding:8px 11px;cursor:pointer}.primary{background:#18181b;color:#fff;border-color:#18181b}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}.grid.list{display:flex;flex-direction:column;gap:8px}.card{background:#fff;border:1px solid var(--line);border-radius:10px;overflow:hidden;cursor:pointer;text-align:left;color:inherit}.card:hover{border-color:#999}.grid.list .card{display:grid;grid-template-columns:132px minmax(0,1fr);width:100%;min-height:96px}.preview{height:92px;background:#eee;background-size:cover;background-position:center;border-bottom:1px solid var(--line);overflow:hidden}.grid.list .preview{height:100%;min-height:96px;border-bottom:0;border-right:1px solid var(--line)}.preview img{width:100%;height:100%;object-fit:cover;display:block}.source-link{float:right;border:0;background:transparent;color:#52525b;text-decoration:underline;cursor:pointer;font-size:10px;padding:0}.swatch{height:92px;border-bottom:1px solid var(--line)}.copy{padding:9px}.name{font-weight:700}.meta{font-size:10px;color:var(--muted);margin-top:3px;line-height:1.35}.delete{float:right;border:0;background:transparent;color:#991b1b;cursor:pointer;font-size:11px}.empty{border:1px dashed #ccc;border-radius:10px;padding:28px;text-align:center;color:var(--muted);grid-column:1/-1}.ncsbox{display:flex;gap:7px;align-items:center;flex-wrap:wrap;margin-bottom:10px}.ncsbox input{flex:1;min-width:230px;border:1px solid var(--line);border-radius:8px;padding:9px}.hint{font-size:10px;color:var(--muted);line-height:1.4;margin:8px 0 12px}.decor-filter{display:none;grid-template-columns:minmax(180px,280px) auto;gap:7px;margin:-3px 0 12px;align-items:center}.decor-filter select{border:1px solid var(--line);border-radius:8px;background:#fff;padding:8px;font:inherit}.decor-filter .result-count{grid-column:1/-1}.grid.decor-grid{grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:14px}.decor-card{border-radius:0;border:0;box-shadow:0 5px 12px rgba(0,0,0,.11)}.decor-card .preview{height:132px}.decor-card .copy{padding:12px}.decor-card .name{font-weight:400;font-size:12px;color:#666}.decor-code{font-size:16px;font-weight:700;margin-top:5px}.club-tabs{display:none;gap:6px;flex-wrap:wrap;margin:-2px 0 12px}.club-subtab{border:1px solid var(--line);background:#fff;border-radius:8px;padding:7px 10px;cursor:pointer;font-size:12px}.club-subtab.active{background:#18181b;color:#fff;border-color:#18181b}.club-head{display:none;background:#fff;border:1px solid var(--line);border-radius:10px;padding:14px;margin-bottom:12px}.club-head-row{display:flex;justify-content:space-between;gap:12px;align-items:center;flex-wrap:wrap}.club-head h3{margin:0 0 3px;font-size:16px}.club-actions{display:flex;gap:7px;flex-wrap:wrap}.club-note{font-size:10px;color:var(--muted);line-height:1.45;margin-top:8px}.ph-tabs{display:none;gap:6px;flex-wrap:wrap;margin:-2px 0 10px}.ph-subtab{border:1px solid var(--line);background:#fff;border-radius:8px;padding:7px 10px;cursor:pointer;font-size:12px}.ph-subtab.active{background:#18181b;color:#fff;border-color:#18181b}.ph-toolbar{display:none;gap:8px;align-items:center;flex-wrap:wrap;background:#fff;border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-bottom:12px}.ph-toolbar select{border:1px solid var(--line);border-radius:8px;background:#fff;padding:7px}.ph-status{font-size:10px;color:var(--muted);margin-left:auto}.ph-card .preview{height:120px}.ph-card .name{font-size:12px}.ph-badge{font-size:9px;color:#52525b;background:#f2f2f2;border-radius:4px;padding:2px 5px;display:inline-block;margin-top:5px}.footer{margin-top:14px;font-size:10px;color:var(--muted);line-height:1.45}</style></head><body>
<div class="head"><div><b>20-20 TEXTURE LIBRARY</b><div style="font-size:10px;margin-top:2px">vyber materiál → klikáním mapuj plochy</div></div><button class="btn" onclick="sketchup.close_dialog()">Zavřít</button></div><div class="wrap"><div class="tabs"><button class="tab active" data-tab="custom">Vlastní textury</button><button class="tab" data-tab="siko">Obklady</button><button class="tab" data-tab="decor">Dekor</button><button class="tab" data-tab="polyhaven">Poly Haven</button><button class="tab" data-tab="ral">RAL</button><button class="tab" data-tab="ncs">NCS</button></div><div class="toolbar"><input id="search" class="search" placeholder="Hledat…" oninput="LIMIT=240;render()"><button id="positionBtn" class="btn" onclick="sketchup.open_positioner()">↔ Upravit mapování vybrané plochy</button><button id="addBtn" class="btn primary" onclick="sketchup.add_texture()">+ Přidat texturu</button></div><div id="sikoFilters" class="filters"><select id="filterSize" onchange="LIMIT=240;render()"><option value="">Všechny rozměry</option></select><select id="filterBrand" onchange="LIMIT=240;render()"><option value="">Všechny značky</option></select><select id="filterProduct" onchange="LIMIT=240;render()"><option value="">Všechny série</option></select><select id="filterColor" onchange="LIMIT=240;render()"><option value="">Všechny barvy</option></select><button class="btn filter-reset" onclick="resetSikoFilters()">Vymazat filtry</button><div id="resultCount" class="result-count"></div></div><div id="decorFilters" class="decor-filter"><select id="decorManufacturer" onchange="LIMIT=240;render()"><option value="">Všichni výrobci</option></select><button class="btn filter-reset" onclick="resetDecorFilters()">Vymazat filtr</button><div id="decorResultCount" class="result-count"></div></div><div id="phTabs" class="ph-tabs"></div><div id="phToolbar" class="ph-toolbar"><b>Assets from Poly Haven · CC0</b><label>Diffuse <select id="phResolution" onchange="render()"><option value="1k">1K</option><option value="2k" selected>2K</option><option value="4k">4K</option></select></label><button class="btn" onclick="phRefresh()">↻ Obnovit katalog</button><span id="phStatus" class="ph-status">Načítám katalog…</span></div><div id="ncsControls" class="ncsbox" style="display:none"><input id="ncsInput" value="NCS S 2050-B90G" placeholder="např. NCS S 2050-B90G"><button class="btn primary" onclick="useTypedNcs()">Použít NCS kód</button></div><div id="ncsHint" class="hint" style="display:none">NCS náhled je převod pro obrazovku, ne náhrada fyzického vzorníku. Můžeš zadat i vlastní platný NCS/NCS S kód.</div><div id="grid" class="grid"></div><div class="footer">Kliknutí na kartu aktivuje štětec. Potom klikáš na libovolné plochy ve SketchUpu; <b>Esc</b> režim ukončí. Vlastní textury se ukládají do <code>%APPDATA%\\2020toolbox\\TextureLibrary</code> a zůstanou dostupné i v dalších projektech. RAL/NCS hodnoty jsou pouze aproximace pro zobrazení na monitoru. <b>Obklady:</b> SIKO katalog s vyčištěnými filtry. <b>Dekor:</b> EGGER dekory. <b>Poly Haven:</b> 862+ CC0 materiálů se zobrazí přímo v knihovně; kliknutí automaticky stáhne Diffuse mapu ve zvoleném rozlišení, nastaví reálné rozměry z API a rovnou aktivuje štětec. Tlačítko <b>Upravit mapování vybrané plochy</b> dovolí samostatně posunout X/Y a otočit texturu jen na jedné ploše.</div></div>
<script>
const RAL=#{ral_json};const NCS_PRESETS=#{ncs_json};let CUSTOM=[],SIKO_CONCRETE=[],SIKO_FLOOR=[],SIKO_ALL=[],EGGER=[],POLYHAVEN=[],PH_CATEGORY='Vše',tab='custom',LIMIT=240;const COLOR_HEX={'Bílá':'#f5f5f2','Šedá':'#969696','Černá':'#202020','Béžová':'#d8c5a4','Hnědá':'#805b42','Modrá':'#6687a8','Zelená':'#718b67','Červená':'#a95149','Oranžová':'#c77c45','Žlutá':'#d4bb58','Růžová':'#cf9aa8','Fialová':'#8b7095','Ostatní':'#ddd'};window.setCustomTextures=items=>{CUSTOM=items||[];render()};window.setSikoTiles=items=>{SIKO_CONCRETE=items||[];rebuildSiko()};window.setSikoFloorTiles=items=>{SIKO_FLOOR=items||[];rebuildSiko()};window.setEggerDecors=items=>{EGGER=items||[];fillDecorFilters();render()};window.setPolyHaven=items=>{POLYHAVEN=items||[];document.getElementById('phStatus').textContent=POLYHAVEN.length+' materiálů';renderPhTabs();render()};window.setPolyHavenError=msg=>{document.getElementById('phStatus').textContent='Chyba: '+msg};function rebuildSiko(){const seen=new Map();SIKO_CONCRETE.forEach(x=>{if(!seen.has(String(x.code)))seen.set(String(x.code),Object.assign({_kind:'siko'},x))});SIKO_FLOOR.forEach(x=>{if(!seen.has(String(x.code)))seen.set(String(x.code),Object.assign({_kind:'siko_floor'},x))});SIKO_ALL=Array.from(seen.values());fillSikoFilters();render()}document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;LIMIT=240;document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('active',x===b));document.getElementById('addBtn').style.display=tab==='custom'?'':'none';document.getElementById('sikoFilters').style.display=tab==='siko'?'grid':'none';document.getElementById('decorFilters').style.display=tab==='decor'?'grid':'none';document.getElementById('phTabs').style.display=tab==='polyhaven'?'flex':'none';document.getElementById('phToolbar').style.display=tab==='polyhaven'?'flex':'none';document.getElementById('ncsControls').style.display=tab==='ncs'?'flex':'none';document.getElementById('ncsHint').style.display=tab==='ncs'?'block':'none';document.getElementById('search').value='';render()});
function esc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]))}function fileUrl(path){const p=String(path).split(String.fromCharCode(92)).join('/');return 'file:///'+p.split('/').map((x,i)=>(i===0&&/^[A-Za-z]:$/.test(x))?x:encodeURIComponent(x)).join('/')}function paint(o){sketchup.paint(JSON.stringify(o))}function del(id,e){e.stopPropagation();if(confirm('Odebrat texturu z knihovny?'))sketchup.delete_texture(id)}function openSource(url,e){e.stopPropagation();sketchup.open_url(url)}function colorCard(code,name,hex,kind){const data=JSON.stringify({kind,name:code,hex}).replace(/'/g,'&#39;');return `<button class="card" data-payload='${data}' onclick="paint(JSON.parse(this.dataset.payload))"><div class="swatch" style="background:${hex}"></div><div class="copy"><div class="name">${esc(code)}</div><div class="meta">${esc(name||hex)} · ${esc(hex)}</div></div></button>`}function sikoCard(x){const data=JSON.stringify({kind:x._kind||'siko',code:x.code}).replace(/'/g,'&#39;');const img=x.image_url?`<img loading="lazy" src="${esc(x.image_url)}" alt="">`:'';const col=x.filter_color||'Ostatní',dot=COLOR_HEX[col]||COLOR_HEX.Ostatní;return `<div class="card" role="button" tabindex="0" data-payload='${data}' onclick="paint(JSON.parse(this.dataset.payload))"><div class="preview">${img}</div><div class="copy"><button class="source-link" onclick="openSource('${esc(x.product_url)}',event)">SIKO ↗</button><div class="name">${esc(x.name)}</div><div class="meta">${esc(x.filter_brand||x.brand||'')} · ${esc(x.filter_product||x.series||'')} · ${esc(x.filter_size||x.size_cm||'rozměr neuveden')} cm</div><div class="meta color-pill"><span class="color-dot" style="background:${dot}"></span>${esc(col)} · ${esc(x.code||'')}</div></div></div>`}function catalogHtml(items,empty){if(!items.length)return `<div class="empty">${empty}</div>`;const visible=items.slice(0,LIMIT);let html=visible.map(sikoCard).join('');if(items.length>visible.length)html+=`<button class="btn" style="width:100%;padding:12px" onclick="LIMIT+=240;render()">Načíst další · zobrazeno ${visible.length} z ${items.length}</button>`;return html}
function eggerPreviewUrl(raw){try{const u=new URL(raw);u.searchParams.set('width','360');return u.toString()}catch(e){return raw}}let DECOR_OBSERVER=null;function activateDecorLazy(){if(DECOR_OBSERVER)DECOR_OBSERVER.disconnect();const imgs=[...document.querySelectorAll('img.decor-lazy[data-src]')];if(!('IntersectionObserver'in window)){imgs.forEach(i=>{i.src=i.dataset.src;i.removeAttribute('data-src')});return}DECOR_OBSERVER=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){const i=e.target;i.src=i.dataset.src;i.removeAttribute('data-src');DECOR_OBSERVER.unobserve(i)}}),{rootMargin:'500px 0px'});imgs.forEach(i=>DECOR_OBSERVER.observe(i))}function eggerCard(x){const data=JSON.stringify({kind:'egger',code:x.code}).replace(/'/g,'&#39;');const img=x.image_url?`<img class="decor-lazy" data-src="${esc(eggerPreviewUrl(x.image_url))}" alt="">`:'';return `<div class="card decor-card" role="button" tabindex="0" data-payload='${data}' onclick="paint(JSON.parse(this.dataset.payload))"><div class="preview">${img}</div><div class="copy"><button class="source-link" onclick="openSource('${esc(x.product_url)}',event)">EGGER ↗</button><div class="name">${esc(x.name)}</div><div class="decor-code">${esc(x.code)}</div></div></div>`}function optionSort(a,b){return String(a).localeCompare(String(b),'cs',{numeric:true,sensitivity:'base'})}function fillSelect(id,values,label){const el=document.getElementById(id),keep=el.value;const vals=Array.from(new Set(values.filter(Boolean))).sort(optionSort);el.innerHTML=`<option value="">${label}</option>`+vals.map(v=>`<option value="${esc(v)}">${esc(v)}</option>`).join('');if(vals.includes(keep))el.value=keep}function fillSikoFilters(){fillSelect('filterSize',SIKO_ALL.map(x=>x.filter_size||x.size_cm),'Všechny rozměry');fillSelect('filterBrand',SIKO_ALL.map(x=>x.filter_brand||x.brand),'Všechny značky');fillSelect('filterProduct',SIKO_ALL.map(x=>x.filter_product||x.series),'Všechny série');fillSelect('filterColor',SIKO_ALL.map(x=>x.filter_color),'Všechny barvy')}function resetSikoFilters(){['filterSize','filterBrand','filterProduct','filterColor'].forEach(id=>document.getElementById(id).value='');LIMIT=240;render()}function fillDecorFilters(){fillSelect('decorManufacturer',EGGER.map(x=>x.manufacturer||'EGGER'),'Všichni výrobci')}function resetDecorFilters(){document.getElementById('decorManufacturer').value='';LIMIT=240;render()}function filteredEgger(){const q=document.getElementById('search').value.trim().toLowerCase(),fm=document.getElementById('decorManufacturer').value;return EGGER.filter(x=>(!fm||(x.manufacturer||'EGGER')===fm)&&(!q||[x.name,x.code,x.base_code,x.texture,x.manufacturer].join(' ').toLowerCase().includes(q)))}function filteredSiko(){const q=document.getElementById('search').value.trim().toLowerCase(),fs=document.getElementById('filterSize').value,fb=document.getElementById('filterBrand').value,fp=document.getElementById('filterProduct').value,fc=document.getElementById('filterColor').value;return SIKO_ALL.filter(x=>{if(fs&&(x.filter_size||x.size_cm)!==fs)return false;if(fb&&(x.filter_brand||x.brand)!==fb)return false;if(fp&&(x.filter_product||x.series)!==fp)return false;if(fc&&x.filter_color!==fc)return false;if(q&&!([x.name,x.code,x.filter_brand,x.brand,x.filter_product,x.series,x.filter_size,x.size_cm,x.filter_color].join(' ').toLowerCase().includes(q)))return false;return true})}
function customCard(x){const data=JSON.stringify({kind:'custom',id:x.id}).replace(/'/g,'&#39;');return `<div class="card" role="button" tabindex="0" data-payload='${data}' onclick="paint(JSON.parse(this.dataset.payload))"><div class="preview" style="background-image:url('${fileUrl(x.path)}')"></div><div class="copy"><button class="delete" onclick="del('${x.id}',event)">Smazat</button><div class="name">${esc(x.name)}</div><div class="meta">${Math.round(x.width_mm)} × ${Math.round(x.height_mm)} mm${x.category_name?' · '+esc(x.category_name):''}</div></div></div>`}function render(){const q=document.getElementById('search').value.trim().toLowerCase(),g=document.getElementById('grid');g.classList.toggle('list',tab==='custom'||tab==='siko');g.classList.toggle('decor-grid',tab==='decor'||tab==='polyhaven');if(tab==='custom'){const a=CUSTOM.filter(x=>(x.name+' '+x.width_mm+' '+x.height_mm+' '+(x.category_name||'')).toLowerCase().includes(q));g.innerHTML=a.length?a.map(customCard).join(''):`<div class="empty">Zatím žádné vlastní textury.<br><br>Klikni na <b>+ Přidat texturu</b>.</div>`}else if(tab==='siko'){const a=filteredSiko();document.getElementById('resultCount').textContent=`Nalezeno ${a.length} z ${SIKO_ALL.length} položek`;g.innerHTML=catalogHtml(a,'Žádný obklad neodpovídá vybraným filtrům.')}else if(tab==='decor'){const a=filteredEgger(),visible=a.slice(0,LIMIT);document.getElementById('decorResultCount').textContent=`Nalezeno ${a.length} z ${EGGER.length} dekorů`;g.classList.add('decor-grid');g.innerHTML=visible.length?visible.map(eggerCard).join(''):`<div class="empty">Žádný dekor neodpovídá filtru.</div>`;if(a.length>visible.length)g.innerHTML+=`<button class="btn" style="grid-column:1/-1;padding:12px" onclick="LIMIT+=240;render()">Načíst další · zobrazeno ${visible.length} z ${a.length}</button>`;setTimeout(activateDecorLazy,0)}else if(tab==='polyhaven'){const a=filteredPolyHaven(),visible=a.slice(0,LIMIT);g.classList.remove('list');g.classList.add('decor-grid');g.innerHTML=visible.length?visible.map(phCard).join(''):`<div class="empty">${POLYHAVEN.length?'Žádný materiál neodpovídá filtru.':'Načítám Poly Haven katalog…'}</div>`;if(a.length>visible.length)g.innerHTML+=`<button class="btn" style="grid-column:1/-1;padding:12px" onclick="LIMIT+=180;render()">Načíst další · zobrazeno ${visible.length} z ${a.length}</button>`;setTimeout(activatePhLazy,0)}else if(tab==='ral'){const a=RAL.filter(x=>(x.code+' '+x.name+' '+x.hex).toLowerCase().includes(q));g.innerHTML=a.map(x=>colorCard(x.code,x.name,x.hex,'ral')).join('')}else{const a=NCS_PRESETS.map(code=>({code,hex:ncsHex(code)})).filter(x=>x.hex&&(x.code+' '+x.hex).toLowerCase().includes(q));g.innerHTML=a.map(x=>colorCard(x.code,'NCS screen preview',x.hex,'ncs')).join('')}}

function useTypedNcs(){let code=document.getElementById('ncsInput').value.trim().toUpperCase();if(!/^NCS/.test(code))code='NCS S '+code.replace(/^S\s+/,'');const hex=ncsHex(code);if(!hex){alert('Neplatný NCS kód. Příklad: NCS S 2050-B90G');return}paint({kind:'ncs',name:code,hex})}
function ncsHex(value){const m=String(value).trim().toUpperCase().match(/^(?:NCS|NCS\sS)\s(\d{2})(\d{2})-(N|R|G|B|Y)(\d{2})?(R|G|B|Y)?$/);if(!m)return null;const Sn=parseInt(m[1],10),Cn=parseInt(m[2],10),C1=m[3],N=parseInt(m[4]||'0',10);let R,G,B;if(C1==='N'){R=G=B=parseInt((1-Sn/100)*255,10)}else{const S=1.05*Sn-5.25,C=Cn;let Ra,Ba,Ga,x;if(C1==='Y'&&N<=60)Ra=1;else if((C1==='Y'&&N>60)||(C1==='R'&&N<=80)){x=C1==='Y'?N-60:N+40;Ra=(Math.sqrt(14884-x*x)-22)/100}else if((C1==='R'&&N>80)||C1==='B')Ra=0;else if(C1==='G'){x=N-170;Ra=(Math.sqrt(33800-x*x)-70)/100}if(C1==='Y'&&N<=80)Ba=0;else if((C1==='Y'&&N>80)||(C1==='R'&&N<=60)){x=C1==='Y'?(N-80)+20.5:(N+20)+20.5;Ba=(104-Math.sqrt(11236-x*x))/100}else if((C1==='R'&&N>60)||(C1==='B'&&N<=80)){x=C1==='R'?(N-60)-60:(N+40)-60;Ba=(Math.sqrt(10000-x*x)-10)/100}else if((C1==='B'&&N>80)||(C1==='G'&&N<=40)){x=C1==='B'?(N-80)-131:(N+20)-131;Ba=(122-Math.sqrt(19881-x*x))/100}else if(C1==='G'&&N>40)Ba=0;if(C1==='Y')Ga=(85-17/20*N)/100;else if(C1==='R'&&N<=60)Ga=0;else if(C1==='R'&&N>60){x=(N-60)+35;Ga=(67.5-Math.sqrt(5776-x*x))/100}else if(C1==='B'&&N<=60){x=N-68.5;Ga=(6.5+Math.sqrt(7044.5-x*x))/100}else if((C1==='B'&&N>60)||(C1==='G'&&N<=60))Ga=.9;else if(C1==='G'&&N>60){x=N-60;Ga=(90-x/8)/100}if([Ra,Ga,Ba].some(v=>!Number.isFinite(v)))return null;const avg=(Ra+Ga+Ba)/3,Rc=((avg-Ra)*(100-C)/100)+Ra,Gc=((avg-Ga)*(100-C)/100)+Ga,Bc=((avg-Ba)*(100-C)/100)+Ba,top=Math.max(Rc,Gc,Bc);if(!top)return null;const ss=1/top;R=Math.floor(Rc*ss*(100-S)/100*255);G=Math.floor(Gc*ss*(100-S)/100*255);B=Math.floor(Bc*ss*(100-S)/100*255)}const cl=v=>Math.max(0,Math.min(255,v|0)),h=v=>cl(v).toString(16).padStart(2,'0');return '#'+h(R)+h(G)+h(B)}
render();setTimeout(()=>sketchup.ready(),50);
</script></body></html>
      HTML
    end
  end
end
TwentyTwenty::TextureLibrary.init

# frozen_string_literal: true
require 'json'
require 'fileutils'
require 'securerandom'
require 'net/http'
require 'uri'

module TwentyTwenty
  module TextureLibrary
    extend self
    VERSION='0.1.2'.freeze
    PREF_KEY='twentytwenty_texture_library_v012'.freeze
    LIB_ROOT=File.join((ENV['APPDATA'] || Dir.home),'2020toolbox','TextureLibrary').freeze
    TEX_ROOT=File.join(LIB_ROOT,'textures').freeze
    LIB_JSON=File.join(LIB_ROOT,'library.json').freeze
    SIKO_JSON=File.join(__dir__,'siko_concrete_tiles.json').freeze
    SIKO_CACHE=File.join(LIB_ROOT,'siko_concrete').freeze
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
      @cmd_open.tooltip='20-20 Texture Library – vlastní textury, RAL a NCS'
      @cmd_open.status_bar_text='Otevře knihovnu textur a barev pro rychlé mapování klikáním na plochy.'
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
      FileUtils.mkdir_p([TEX_ROOT,SIKO_CACHE])
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

    def read_siko_catalog
      return [] unless File.file?(SIKO_JSON)
      data=JSON.parse(File.read(SIKO_JSON,encoding:'UTF-8'))
      Array(data['items'])
    rescue StandardError
      []
    end

    def siko_record(code)
      read_siko_catalog.find{|x|x['code'].to_s==code.to_s}
    end

    def download_https(url,target,limit=5)
      raise 'Příliš mnoho přesměrování.' if limit<=0
      uri=URI.parse(url.to_s)
      raise 'Neplatná adresa obrázku.' unless uri.is_a?(URI::HTTPS)
      req=Net::HTTP::Get.new(uri.request_uri,{'User-Agent'=>'20-20 Texture Library/0.1.2'})
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
      dlg.add_action_callback('open_url'){|_ctx,url| u=url.to_s; UI.openURL(u) if u.start_with?('https://www.siko.cz/')}
      dlg.add_action_callback('close_dialog'){|_ctx| dlg.close}
      dlg.set_on_closed{@dialog=nil}
      dlg
    end

    def push_library_to_dialog
      return unless @dialog
      @dialog.execute_script("window.setCustomTextures(#{JSON.generate(read_library['textures'])});")
      @dialog.execute_script("window.setSikoTiles(#{JSON.generate(read_siko_catalog)});")
    rescue StandardError
      nil
    end

    def add_custom_texture
      path=UI.openpanel('Vyber texturu',nil,'Obrázky|*.png;*.jpg;*.jpeg;*.webp;*.bmp||')
      return unless path && File.file?(path)
      base=File.basename(path,'.*')
      values=UI.inputbox(['Název textury:','Reálná šířka vzoru [mm]:','Reálná výška vzoru [mm]:'],[base,1000.0,1000.0],'Přidat texturu do knihovny')
      return unless values
      name=values[0].to_s.strip; name=base if name.empty?
      width_mm=[values[1].to_f,1.0].max; height_mm=[values[2].to_f,1.0].max
      id=SecureRandom.hex(6); ext=File.extname(path).downcase; target=File.join(TEX_ROOT,"#{id}#{ext}")
      FileUtils.cp(path,target)
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
        rec=read_library['textures'].find{|t|t['id'].to_s==data['id'].to_s}
        return UI.messagebox('Textura už není v knihovně.') unless rec && File.file?(rec['path'].to_s)
        mat_name="20-20 TEX | #{rec['name']}"; mat=model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture=rec['path'].to_s
        if mat.texture
          begin; mat.texture.size=[rec['width_mm'].to_f.mm,rec['height_mm'].to_f.mm]; rescue StandardError; end
        end
        mat
      elsif kind=='siko'
        rec=siko_record(data['code'])
        return UI.messagebox('Produkt už není v katalogu Betonové obklady.') unless rec
        path=siko_texture_path(rec)
        mat_name="20-20 SIKO | #{rec['name']}"; mat=model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture=path
        if mat.texture
          w=rec['width_cm'].to_f; h=rec['height_cm'].to_f
          begin; mat.texture.size=[(w*10.0).mm,(h*10.0).mm] if w>0 && h>0; rescue StandardError; end
        end
        begin
          mat.set_attribute('20-20 Texture Library','source','SIKO')
          mat.set_attribute('20-20 Texture Library','product_url',rec['product_url'].to_s)
          mat.set_attribute('20-20 Texture Library','product_code',rec['code'].to_s)
          mat.set_attribute('20-20 Texture Library','size_cm',rec['size_cm'].to_s)
        rescue StandardError
        end
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
        model=Sketchup.active_model; model.start_operation('20-20 Paint Texture',true); face.material=@material; model.commit_operation; view.invalidate
      rescue StandardError => e
        Sketchup.active_model.abort_operation rescue nil
        UI.messagebox("Aplikace materiálu selhala:\n#{e.class}: #{e.message}")
      end
    end

    def dialog_html
      ral_json=JSON.generate(RAL); ncs_json=JSON.generate(NCS_PRESETS)
      <<~HTML
<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
:root{--bg:#f5f5f5;--card:#fff;--line:#dedede;--text:#18181b;--muted:#71717a;--yellow:#f7f197}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:13px system-ui,Segoe UI,sans-serif}.head{position:sticky;top:0;z-index:10;background:var(--yellow);border-bottom:1px solid #d8d16d;padding:13px 16px;display:flex;align-items:center;justify-content:space-between}.head b{font-size:17px}.wrap{padding:14px}.tabs{display:flex;gap:7px;flex-wrap:wrap}.tab{border:1px solid var(--line);background:#fff;border-radius:8px;padding:8px 12px;cursor:pointer}.tab.active{background:#18181b;color:#fff;border-color:#18181b}.toolbar{display:flex;gap:8px;margin:12px 0;align-items:center;flex-wrap:wrap}.search{flex:1;min-width:220px;border:1px solid var(--line);border-radius:8px;padding:9px}.btn{border:1px solid var(--line);background:#fff;border-radius:8px;padding:8px 11px;cursor:pointer}.primary{background:#18181b;color:#fff;border-color:#18181b}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}.card{background:#fff;border:1px solid var(--line);border-radius:10px;overflow:hidden;cursor:pointer;text-align:left}.card:hover{border-color:#999}.preview{height:92px;background:#eee;background-size:cover;background-position:center;border-bottom:1px solid var(--line);overflow:hidden}.preview img{width:100%;height:100%;object-fit:cover;display:block}.source-link{float:right;border:0;background:transparent;color:#52525b;text-decoration:underline;cursor:pointer;font-size:10px;padding:0}.swatch{height:92px;border-bottom:1px solid var(--line)}.copy{padding:9px}.name{font-weight:700}.meta{font-size:10px;color:var(--muted);margin-top:3px;line-height:1.35}.delete{float:right;border:0;background:transparent;color:#991b1b;cursor:pointer;font-size:11px}.empty{border:1px dashed #ccc;border-radius:10px;padding:28px;text-align:center;color:var(--muted);grid-column:1/-1}.ncsbox{display:flex;gap:7px;align-items:center;flex-wrap:wrap;margin-bottom:10px}.ncsbox input{flex:1;min-width:230px;border:1px solid var(--line);border-radius:8px;padding:9px}.hint{font-size:10px;color:var(--muted);line-height:1.4;margin:8px 0 12px}.footer{margin-top:14px;font-size:10px;color:var(--muted);line-height:1.45}</style></head><body>
<div class="head"><div><b>20-20 TEXTURE LIBRARY</b><div style="font-size:10px;margin-top:2px">vyber materiál → klikáním mapuj plochy</div></div><button class="btn" onclick="sketchup.close_dialog()">Zavřít</button></div><div class="wrap"><div class="tabs"><button class="tab active" data-tab="custom">Vlastní textury</button><button class="tab" data-tab="siko">Betonové obklady</button><button class="tab" data-tab="ral">RAL</button><button class="tab" data-tab="ncs">NCS</button></div><div class="toolbar"><input id="search" class="search" placeholder="Hledat…" oninput="render()"><button id="addBtn" class="btn primary" onclick="sketchup.add_texture()">+ Přidat texturu</button></div><div id="ncsControls" class="ncsbox" style="display:none"><input id="ncsInput" value="NCS S 2050-B90G" placeholder="např. NCS S 2050-B90G"><button class="btn primary" onclick="useTypedNcs()">Použít NCS kód</button></div><div id="ncsHint" class="hint" style="display:none">NCS náhled je převod pro obrazovku, ne náhrada fyzického vzorníku. Můžeš zadat i vlastní platný NCS/NCS S kód.</div><div id="grid" class="grid"></div><div class="footer">Kliknutí na kartu aktivuje štětec. Potom klikáš na libovolné plochy ve SketchUpu; <b>Esc</b> režim ukončí. Vlastní textury se ukládají do <code>%APPDATA%\\2020toolbox\\TextureLibrary</code> a zůstanou dostupné i v dalších projektech. RAL/NCS hodnoty jsou pouze aproximace pro zobrazení na monitoru. <b>Betonové obklady:</b> data a obrázky SIKO.</div></div>
<script>
const RAL=#{ral_json};const NCS_PRESETS=#{ncs_json};let CUSTOM=[],SIKO=[],tab='custom';window.setCustomTextures=items=>{CUSTOM=items||[];render()};window.setSikoTiles=items=>{SIKO=items||[];render()};document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('active',x===b));document.getElementById('addBtn').style.display=tab==='custom'?'':'none';document.getElementById('ncsControls').style.display=tab==='ncs'?'flex':'none';document.getElementById('ncsHint').style.display=tab==='ncs'?'block':'none';document.getElementById('search').value='';render()});
function esc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]))}function fileUrl(path){return 'file:///'+String(path).split(String.fromCharCode(92)).join('/').split('/').map(encodeURIComponent).join('/')}function paint(o){sketchup.paint(JSON.stringify(o))}function del(id,e){e.stopPropagation();if(confirm('Odebrat texturu z knihovny?'))sketchup.delete_texture(id)}function openSiko(url,e){e.stopPropagation();sketchup.open_url(url)}function colorCard(code,name,hex,kind){const data=JSON.stringify({kind,name:code,hex}).replace(/'/g,'&#39;');return `<button class="card" data-payload='${data}' onclick="paint(JSON.parse(this.dataset.payload))"><div class="swatch" style="background:${hex}"></div><div class="copy"><div class="name">${esc(code)}</div><div class="meta">${esc(name||hex)} · ${esc(hex)}</div></div></button>`}function sikoCard(x){const data=JSON.stringify({kind:'siko',code:x.code}).replace(/'/g,'&#39;');const img=x.image_url?`<img loading="lazy" src="${esc(x.image_url)}" alt="">`:'';return `<div class="card" role="button" tabindex="0" data-payload='${data}' onclick="paint(JSON.parse(this.dataset.payload))"><div class="preview">${img}</div><div class="copy"><button class="source-link" onclick="openSiko('${esc(x.product_url)}',event)">SIKO ↗</button><div class="name">${esc(x.name)}</div><div class="meta">${esc(x.size_cm||'rozměr neuveden')} cm · ${esc(x.code||'')}</div></div></div>`}
function render(){const q=document.getElementById('search').value.trim().toLowerCase(),g=document.getElementById('grid');if(tab==='custom'){const a=CUSTOM.filter(x=>(x.name+' '+x.width_mm+' '+x.height_mm).toLowerCase().includes(q));g.innerHTML=a.length?a.map(x=>{const data=JSON.stringify({kind:'custom',id:x.id}).replace(/'/g,'&#39;');return `<button class="card" data-payload='${data}' onclick="paint(JSON.parse(this.dataset.payload))"><div class="preview" style="background-image:url('${fileUrl(x.path)}')"></div><div class="copy"><button class="delete" onclick="del('${x.id}',event)">Smazat</button><div class="name">${esc(x.name)}</div><div class="meta">${Math.round(x.width_mm)} × ${Math.round(x.height_mm)} mm</div></div></button>`}).join(''):`<div class="empty">Zatím žádné vlastní textury.<br><br>Klikni na <b>+ Přidat texturu</b>.</div>`}else if(tab==='siko'){const a=SIKO.filter(x=>([x.name,x.code,x.brand,x.series,x.size_cm].join(' ').toLowerCase().includes(q)));g.innerHTML=a.length?a.map(sikoCard).join(''):`<div class="empty">Katalog betonových obkladů není dostupný.</div>`}else if(tab==='ral'){const a=RAL.filter(x=>(x.code+' '+x.name+' '+x.hex).toLowerCase().includes(q));g.innerHTML=a.map(x=>colorCard(x.code,x.name,x.hex,'ral')).join('')}else{const a=NCS_PRESETS.map(code=>({code,hex:ncsHex(code)})).filter(x=>x.hex&&(x.code+' '+x.hex).toLowerCase().includes(q));g.innerHTML=a.map(x=>colorCard(x.code,'NCS screen preview',x.hex,'ncs')).join('')}}
function useTypedNcs(){let code=document.getElementById('ncsInput').value.trim().toUpperCase();if(!/^NCS/.test(code))code='NCS S '+code.replace(/^S\s+/,'');const hex=ncsHex(code);if(!hex){alert('Neplatný NCS kód. Příklad: NCS S 2050-B90G');return}paint({kind:'ncs',name:code,hex})}
function ncsHex(value){const m=String(value).trim().toUpperCase().match(/^(?:NCS|NCS\sS)\s(\d{2})(\d{2})-(N|R|G|B|Y)(\d{2})?(R|G|B|Y)?$/);if(!m)return null;const Sn=parseInt(m[1],10),Cn=parseInt(m[2],10),C1=m[3],N=parseInt(m[4]||'0',10);let R,G,B;if(C1==='N'){R=G=B=parseInt((1-Sn/100)*255,10)}else{const S=1.05*Sn-5.25,C=Cn;let Ra,Ba,Ga,x;if(C1==='Y'&&N<=60)Ra=1;else if((C1==='Y'&&N>60)||(C1==='R'&&N<=80)){x=C1==='Y'?N-60:N+40;Ra=(Math.sqrt(14884-x*x)-22)/100}else if((C1==='R'&&N>80)||C1==='B')Ra=0;else if(C1==='G'){x=N-170;Ra=(Math.sqrt(33800-x*x)-70)/100}if(C1==='Y'&&N<=80)Ba=0;else if((C1==='Y'&&N>80)||(C1==='R'&&N<=60)){x=C1==='Y'?(N-80)+20.5:(N+20)+20.5;Ba=(104-Math.sqrt(11236-x*x))/100}else if((C1==='R'&&N>60)||(C1==='B'&&N<=80)){x=C1==='R'?(N-60)-60:(N+40)-60;Ba=(Math.sqrt(10000-x*x)-10)/100}else if((C1==='B'&&N>80)||(C1==='G'&&N<=40)){x=C1==='B'?(N-80)-131:(N+20)-131;Ba=(122-Math.sqrt(19881-x*x))/100}else if(C1==='G'&&N>40)Ba=0;if(C1==='Y')Ga=(85-17/20*N)/100;else if(C1==='R'&&N<=60)Ga=0;else if(C1==='R'&&N>60){x=(N-60)+35;Ga=(67.5-Math.sqrt(5776-x*x))/100}else if(C1==='B'&&N<=60){x=N-68.5;Ga=(6.5+Math.sqrt(7044.5-x*x))/100}else if((C1==='B'&&N>60)||(C1==='G'&&N<=60))Ga=.9;else if(C1==='G'&&N>60){x=N-60;Ga=(90-x/8)/100}if([Ra,Ga,Ba].some(v=>!Number.isFinite(v)))return null;const avg=(Ra+Ga+Ba)/3,Rc=((avg-Ra)*(100-C)/100)+Ra,Gc=((avg-Ga)*(100-C)/100)+Ga,Bc=((avg-Ba)*(100-C)/100)+Ba,top=Math.max(Rc,Gc,Bc);if(!top)return null;const ss=1/top;R=Math.floor(Rc*ss*(100-S)/100*255);G=Math.floor(Gc*ss*(100-S)/100*255);B=Math.floor(Bc*ss*(100-S)/100*255)}const cl=v=>Math.max(0,Math.min(255,v|0)),h=v=>cl(v).toString(16).padStart(2,'0');return '#'+h(R)+h(G)+h(B)}
render();setTimeout(()=>sketchup.ready(),50);
</script></body></html>
      HTML
    end
  end
end
TwentyTwenty::TextureLibrary.init

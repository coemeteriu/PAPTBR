require "zlib"
require "fileutils"

SCRIPTS_PATH = "Data/Scripts.rxdata"
TXT_PATH     = "Data/messages_hashes/messages_hashes.txt"
DAT_FILES    = ["Data/messages_core.dat", "Data/messages_game.dat"]

def inflate_maybe(blob); Zlib::Inflate.inflate(blob) rescue blob; end
def deflate(code); Zlib::Deflate.deflate(code); end

def to_utf8(str)
  s = str.dup.force_encoding("UTF-8") rescue str.dup
  return s if s.respond_to?(:valid_encoding?) && s.valid_encoding?
  str.dup.force_encoding("Windows-1252").encode("UTF-8", invalid: :replace, undef: :replace, replace: "?") rescue str.dup
end

data = Marshal.load(File.binread(SCRIPTS_PATH))

inject = "PTBR_TXT_PATH = '#{TXT_PATH}'\n" + <<~'RUBY'
  # === 📢 SISTEMA DE ATUALIZAÇÃO AUTOMÁTICA (MODO FANTASMA) ===
  module PTBR_UPDATER
    URL_VERSAO = "https://raw.githubusercontent.com/coemeteriu/PAPTBR/main/versao.txt"

    def self.obter_versao_local
      ["versao.txt", "versao.txt.txt"].each do |arquivo|
        if File.exist?(arquivo)
          begin
            conteudo = File.read(arquivo).strip
            return conteudo.to_f if conteudo.match?(/^[0-9]+(\.[0-9]+)?$/)
          rescue
          end
        end
      end
      return 1.0 
    end

    def self.checar_e_avisar
      texto = ""
      
      if defined?(pbDownloadToString)
        begin
          texto = pbDownloadToString(URL_VERSAO).to_s.strip
        rescue Exception
        end
      end

      if (!texto || texto.empty?)
        begin
          vbs_code = "Set ws = CreateObject(\"WScript.Shell\")\nws.Run \"cmd /c curl -sL #{URL_VERSAO} -o ptbr_fofoca.txt\", 0, True"
          File.open("ptbr_fofoca.vbs", "w") { |f| f.write(vbs_code) }
          system("wscript", "ptbr_fofoca.vbs")
          if File.exist?("ptbr_fofoca.txt")
            texto = File.read("ptbr_fofoca.txt").strip
            File.delete("ptbr_fofoca.txt") rescue nil
          end
          File.delete("ptbr_fofoca.vbs") rescue nil
        rescue Exception
        end
      end
      
      if texto && texto.match?(/^[0-9]+(\.[0-9]+)?$/)
        versao_online = texto.to_f
        v_local = obter_versao_local
        if versao_online > v_local
          aviso = "Uma nova versão da tradução (v#{versao_online}) está disponível!\nAcesse pokemonanilbr.netlify.app para baixar as novidades!"
          if defined?(pbMessage)
            pbMessage(aviso)
          elsif defined?(Kernel.pbMessage)
            Kernel.pbMessage(aviso)
          else
            print(aviso)
          end
        end
      end
    end
  end

  if defined?(Game_Player) && !Game_Player.method_defined?(:ptbr_orig_update_fofoq)
    class Game_Player
      alias ptbr_orig_update_fofoq update
      def update
        ptbr_orig_update_fofoq
        unless $ptbr_fofoca_feita
          if Graphics.frame_count % 60 == 0 && $game_map
            map_name = ""
            begin
              if $game_map.respond_to?(:name)
                map_name = $game_map.name.to_s.downcase
              elsif defined?(pbGetMapName)
                map_name = pbGetMapName($game_map.map_id).to_s.downcase
              end
            rescue
            end
            if (map_name.include?("centro") || map_name.include?("center")) && map_name.include?("pok")
              $ptbr_fofoca_feita = true
              PTBR_UPDATER.checar_e_avisar
            end
          end
        end
      end
    end
  end
  # ==========================================================

  module PTBR_TEXT
    @map = {}; @partials = []; @loaded = false; @cache = {}

    def self.load_map
      return if @loaded
      @loaded = true
      return unless File.exist?(PTBR_TXT_PATH)
      File.foreach(PTBR_TXT_PATH, encoding: "bom|utf-8") do |line|
        partes = line.chomp.split("|||", 3)
        if partes.length == 3
          if partes[0] == "SUB"
            @partials << [partes[1].force_encoding("UTF-8"), partes[2].force_encoding("UTF-8")]
          else
            # 🔨 ARRUMADO: Normaliza o dicionário também!
            key = partes[1].gsub('\n', "\n").gsub('\r', "\r").gsub("…", "...").force_encoding("UTF-8")
            val = partes[2].gsub('\n', "\n").gsub('\r', "\r").gsub("…", "...").force_encoding("UTF-8")
            @map[key] = val
          end
        end
      end
    rescue
    end

    def self.t(str)
      return str if !str || !str.is_a?(String) || str.empty?
      return @cache[str] if @cache.key?(str)

      orig_str = str.dup

      system_words = [
        "info", "skills", "moves", "egg", "allstats", "memo",
        "red", "blue", "green", "yellow", "black", "white", "gray", "grey",
        "orange", "purple", "pink", "brown", "cyan", "magenta", "transparent",
        "bag", "party", "summary", "pokegear", "pokedex", "trainer", "save", "options"
      ]

      if str.match?(/^(Graphics|Pictures|Audio|Data|System|Fonts)\//i) ||
         str.match?(/\.(png|jpg|jpeg|gif|bmp|rxdata|dat|txt)$/i) ||
         system_words.include?(str.downcase.strip)
        @cache[orig_str] = str
        return str
      end

      res = str.dup
      
      # 🔨 O DESMASCARADOR DE RETICÊNCIAS (Isso resolve dezenas de fugas!)
      res.gsub!("…", "...")

      load_map
      if @map.key?(res)
        res = @map[res]
      elsif @map.key?(res.strip)
        res = res.sub(res.strip, @map[res.strip])
      end

      @partials.each do |es, pt|
        if res.include?(es)
          res.gsub!(es, pt)
        end
      end

      # === 💥 A GUILHOTINA DE GOLPES E APRENDIZADO ===
      res.gsub!(/ha olvidado c[oó]mo utilizar/i, "esqueceu como usar")
      res.gsub!(/\} y\.\.\./i, "} e...")
      res.gsub!(/1,\s*2\s*y\.\.\./i, "1, 2, e...")
      res.gsub!(/y\.\.\.\s*¡(.*?) aprendi[oó]/i, 'e... ¡\1 aprendeu')
      res.gsub!(/¡(.*?) aprendi[oó]/i, '¡\1 aprendeu')
      # ========================================

      res.gsub!("¡{1} subió al Nivel {2}!", "{1} subiu para o nível {2}!")
      res.gsub!("¡{1} subió al Nível {2}!", "{1} subiu para o nível {2}!")
      res.gsub!(/¡(.*?) subi[oó] al N[ií]vel (.*?)!/i, '\1 subiu para o nível \2!')
      
      res.gsub!(/¡Has obtenido la /i, "Você obteve a ")
      res.gsub!(/¡Has obtenido el /i, "Você obteve o ")
      res.gsub!(/¡Has obtenido /i, "Você obteve ")

      res.gsub!(/\bNivel\b/i, "Nível")
      
      res.gsub!(/Has(?:\\n|\\r|\s)+guardado/i, "Você guardou")
      res.gsub!(/en(?:\\n|\\r|\s)+el(?:\\n|\\r|\s)+bolsillo/i, "no bolso")
      res.gsub!(/el(?:\\n|\\r|\s)+bolsillo/i, "o bolso")
      res.gsub!(/\ben(?:\\n|\\r|\s)+o(?:\\n|\\r|\s)+bolso/i, "no bolso")

      res.gsub!(/Estadísticas Generales/i, "Estatísticas Gerais")
      res.gsub!(/Ratio de Captura/i, "Taxa de Captura")
      res.gsub!(/Prob\. de género/i, "Prob. de gênero")
      res.gsub!(/sin género/i, "sem gênero")
      res.gsub!(/\bHembra\b/i, "Fêmea")
      res.gsub!(/\bMacho\b/i, "Macho")
      res.gsub!(/Encuentros/i, "Encontros")
      res.gsub!(/Derrotados/i, "Derrotados")
      res.gsub!(/Capturados/i, "Capturados")
      res.gsub!(/Morfolog[ií]a/i, "Morfologia")
      res.gsub!(/H[aá]bit[aá]t/i, "Habitat")
      res.gsub!(/\bCrianza\b/i, "Cruzamento")
      res.gsub!(/Ramas evolutivas/i, "Ramificações evolutivas")
      res.gsub!(/Método de Evolución/i, "Método de Evolução")

      res.gsub!(/El color principal de la especie es el/i, "A cor principal da espécie é o")
      res.gsub!(/Tiene forma de/i, "Possui a forma de")
      res.gsub!(/Tiene forma/i, "Possui a forma")

      res.gsub!(/(Esta|Esa|Essa)\s+especie\s+(se puede encontrar|puede ser encontrada)/i, "Esta espécie pode ser encontrada")
      res.gsub!(/en zonas escarpadas de/i, "em zonas escarpadas de")
      res.gsub!(/en zonas escarpadas/i, "em zonas escarpadas")
      res.gsub!(/en escarpadas áreas/i, "em áreas escarpadas")
      res.gsub!(/en densas áreas/i, "em densas áreas")
      res.gsub!(/circulando por áreas/i, "circulando por áreas")
      res.gsub!(/cerca de áreas/i, "perto de áreas")
      res.gsub!(/en áreas de/i, "em áreas de")
      res.gsub!(/en lugares desconocidos/i, "em locais desconhecidos")

      res.gsub!(/\bPS M[aá]x\.?\b/i, "HP")
      res.gsub!(/\bAtaque\b/i, "Ataque")
      res.gsub!(/\bDefensa\b/i, "Defesa")
      res.gsub!(/\bVelocidad\b/i, "Velocidade")
      res.gsub!(/\bAt\.?\s*Esp\.?\b/i, "Atq. Esp")
      res.gsub!(/\bDef\.?\s*Esp\.?\b/i, "Def. Esp")

      res.gsub!(/Especie compatible con los grupos/i, "Espécie compatível com os grupos")
      res.gsub!(/Especie compatible com los grupos/i, "Espécie compatível com os grupos")
      res.gsub!(/Especie compatible con el grupo/i, "Espécie compatível com o grupo")
      res.gsub!(/Es compatible con los grupos/i, "É compatível com os grupos")
      res.gsub!(/Es compatible con el grupo/i, "É compatível com o grupo")
      res.gsub!(/está en el grupo/i, "está no grupo")
      res.gsub!(/compatible con todos excepto/i, "compatível com todos exceto")
      res.gsub!(/no tiene género y solo es compatible con el grupo/i, "não tem gênero e só é compatível com o grupo")
      res.gsub!(/y no puede criar/i, "e não pode cruzar")

      res.gsub!(/Si el juego te va MUY RÁPIDO o MUY LENTO/i, "Se o jogo estiver MUITO RÁPIDO o MUITO LENTO")
      res.gsub!(/ve a Opciones y cambia la opción/i, "vá em Opções e altere a configuração")

      begin
        ctx = res.dup
        ctx.gsub!(/\\c\[[0-9]+\]/i, "")
        ctx.gsub!(/\\[a-z]+\[[^\]]*\]/i, "")
        ctx.gsub!(/\\[a-z]+/i, "")
        ctx.gsub!(/<[^>]+>/, "")
        ctx = ctx.downcase

        if ctx.match?(/grupo|grupos|cruz|crian|huevo|egg|compatib|compat[ií]vel|género|genero/i)
          spacer = /(?:\s+|\\c\[[0-9]+\]|\\[a-z]+\[[^\]]*\]|\\[a-z]+|<[^>]+>)*/
          res.gsub!(/#{spacer}\by\b#{spacer}/i) do |m|
            left_codes  = m.sub(/(?i)\by\b.*\z/m, "")
            right_codes = m.sub(/\A.*(?i)\by\b/m, "")
            "#{left_codes} e #{right_codes}"
          end
        end
      rescue
      end

      res.gsub!(/Subir de nivel a/i, "Subir de nível de")
      res.gsub!(/Sube de nivel a/i, "Sobe de nível de")
      res.gsub!(/con gran felicidad/i, "com muita felicidad")
      res.gsub!(/durante el día/i, "durante o dia")
      res.gsub!(/durante la noche/i, "durante a noite")
      res.gsub!(/conociendo el movimiento/i, "conhecendo o movimiento")
      res.gsub!(/conociendo un movimiento de tipo/i, "conhecendo um ataque do tipo")
      res.gsub!(/equipado con/i, "equipado com")
      res.gsub!(/llevando/i, "segurando")

      {"rojo"=>"vermelho", "azul"=>"azul", "amarillo"=>"amarelo", "verde"=>"verde",
       "negro"=>"preto", "blanco"=>"branco", "marrón"=>"marrom", "rosa"=>"rosa",
       "gris"=>"cinza", "morado"=>"roxo"}.each { |es, pt| res.gsub!(/\b#{es}\b/i, pt) }

      res.gsub!(/cabeza y cuerpo/i, "cabeça e corpo")
      res.gsub!(/cabeza y brazos/i, "cabeça e braços")
      res.gsub!(/cabeza y base/i, "cabeça e base")
      res.gsub!(/cuadrúpedo/i, "quadrúpede")
      res.gsub!(/alas/i, "asas")
      res.gsub!(/tentáculos/i, "tentáculos")
      res.gsub!(/insectoide/i, "insetóide")
      res.gsub!(/serpentino/i, "serpentino")
      res.gsub!(/aletas/i, "barbatanas")
      res.gsub!(/varios cuerpos/i, "vários corpos")

      @cache[orig_str] = res
      return res
    end
  end

  if defined?(Window_Base) && !Window_Base.method_defined?(:ptbr_orig_draw_text)
    class Window_Base
      alias ptbr_orig_draw_text draw_text
      def draw_text(*args)
        t_idx = args[0].is_a?(Numeric) ? 4 : 1
        args[t_idx] = PTBR_TEXT.t(args[t_idx]) if args[t_idx].is_a?(String)
        ptbr_orig_draw_text(*args)
      end
    end
  end

  unless defined?($PTBR_HOOK_MAPNAMES)
    $PTBR_HOOK_MAPNAMES = true

    [
      :pbGetMapName,
      :pbGetMapNameFromId,
      :pbGetMapNameFromID,
      :pbGetBasicMapNameFromID,
      :pbMapName,
      :pbGetMapDisplayName
    ].each do |m|
      if defined?(Kernel) && Kernel.method_defined?(m)
        Kernel.module_eval do
          alias_method :"__ptbr_#{m}_original", m
          define_method(m) do |*a|
            r = send(:"__ptbr_#{m}_original", *a)
            r.is_a?(String) ? PTBR_TEXT.t(r) : r
          end
        end
      end
    end

    if defined?(Game_Map) && Game_Map.method_defined?(:name)
      Game_Map.class_eval do
        alias __ptbr_gamemap_name_original name
        def name
          r = __ptbr_gamemap_name_original
          r.is_a?(String) ? PTBR_TEXT.t(r) : r
        end
      end
    end

    if defined?(RPG) && defined?(RPG::MapInfo) && RPG::MapInfo.method_defined?(:name)
      RPG::MapInfo.class_eval do
        alias __ptbr_mapinfo_name_original name
        def name
          r = __ptbr_mapinfo_name_original
          r.is_a?(String) ? PTBR_TEXT.t(r) : r
        end
      end
    end
  end
RUBY

def apply_hooks(code_utf8, inject_utf8)
  code = code_utf8.dup
  changed = 0

  unless code.include?("module PTBR_TEXT")
    code.insert(0, inject_utf8 + "\n")
    changed += 1
  end

  if code.include?("def pbGetMessage(")
    code.gsub!(/def pbGetMessage\([^)]+\)/) do |m|
      "#{m}\n  res = MessageTypes.get(type, id) rescue ''\n  return res unless res.is_a?(String)\n  is_loc = (defined?(MessageTypes) && [MessageTypes::MapNames, MessageTypes::RegionNames, MessageTypes::PlaceNames].include?(type)) rescue false\n  return PTBR_TEXT.t(res) if is_loc\n  return (res.length > 12 || res.include?(' ')) ? PTBR_TEXT.t(res) : res"
    end
    changed += 1
  end

  if code.include?("def pbGetMessageFromHash(")
    code.gsub!(/def pbGetMessageFromHash\([^)]+\)/) do |m|
      "#{m}\n  res = MessageTypes.getFromHash(type, id) rescue ''\n  return res unless res.is_a?(String)\n  is_loc = (defined?(MessageTypes) && [MessageTypes::MapNames, MessageTypes::RegionNames, MessageTypes::PlaceNames].include?(type)) rescue false\n  return PTBR_TEXT.t(res) if is_loc\n  return (res.length > 12 || res.include?(' ')) ? PTBR_TEXT.t(res) : res"
    end
    changed += 1
  end

  if code.include?("def pbDrawTextPositions")
    code.gsub!(/def pbDrawTextPositions\s*\(([^,]+),\s*([^)]+)\)/) do |m|
      "#{m}\n  #{$2}.each { |pos| pos[0] = PTBR_TEXT.t(pos[0]) if pos.is_a?(Array) && pos[0].is_a?(String) } if #{$2}.is_a?(Array) rescue nil"
    end
    changed += 1
  end

  if code.include?("def _MAPINTL(")
    code.gsub!(/def\s+_MAPINTL\s*\(\s*([a-zA-Z0-9_]+)\s*,\s*\*\s*([a-zA-Z0-9_]+)(.*)/) do |_m|
      "def _MAPINTL(#{$1}, *#{$2}#{$3}\n  #{$2}.each_with_index { |v, i| #{$2}[i] = PTBR_TEXT.t(v) if v.is_a?(String) }"
    end
    changed += 1
  end

  if code.include?("def _INTL(")
    code.gsub!(/def\s+_INTL\s*\(\s*\*\s*([a-zA-Z0-9_]+)(.*)/) do |_m|
      "def _INTL(*#{$1}#{$2}\n  #{$1}.each_with_index { |v, i| #{$1}[i] = PTBR_TEXT.t(v) if v.is_a?(String) }"
    end
    changed += 1
  end

  if code.include?("def pbMessage(")
    code.gsub!(/def\s+pbMessage\s*\(\s*([a-zA-Z0-9_]+)(.*)/) do |_m|
      "def pbMessage(#{$1}#{$2}\n  #{$1} = PTBR_TEXT.t(#{$1}) if #{$1}.is_a?(String)"
    end
    changed += 1
  end

  # Hook para displays menores (onde as mensagens de level up as vezes se escondem)
  if code.include?("def pbDisplayPaused(")
    code.gsub!(/def\s+pbDisplayPaused\s*\(\s*([a-zA-Z0-9_]+)(.*)/) do |_m|
      "def pbDisplayPaused(#{$1}#{$2}\n  #{$1} = PTBR_TEXT.t(#{$1}) if #{$1}.is_a?(String)"
    end
    changed += 1
  end

  if code.include?("def pbDisplay(")
    code.gsub!(/def\s+pbDisplay\s*\(\s*([a-zA-Z0-9_]+)(.*)/) do |_m|
      "def pbDisplay(#{$1}#{$2}\n  #{$1} = PTBR_TEXT.t(#{$1}) if #{$1}.is_a?(String)"
    end
    changed += 1
  end

  [code, changed]
end

patched = 0
data.each_with_index do |entry, i|
  raw = inflate_maybe(entry[2])
  next unless raw.is_a?(String)

  if raw.include?("def pbGetMessage") || raw.include?("def _INTL") ||
     raw.include?("def pbDrawTextPositions") || raw.include?("def pbMessage") ||
     raw.include?("def pbDisplay") || raw.include?("def _MAPINTL") || entry[1] == "Main"

    code_utf8 = to_utf8(raw)
    new_code, changes = apply_hooks(code_utf8, inject)

    if changes > 0
      data[i][2] = deflate(new_code.encode("UTF-8"))
      patched += 1
    end
  end
end

File.binwrite(SCRIPTS_PATH, Marshal.dump(data))
puts "\n--- V44 (A FORTALEZA V20) APLICADA: RETICÊNCIAS FALSAS DESTRUÍDAS! ---"

DAT_FILES.each do |f|
  if File.exist?(f)
    File.delete(f) rescue nil
  end
end
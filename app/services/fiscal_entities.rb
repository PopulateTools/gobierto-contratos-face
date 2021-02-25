class FiscalEntities
  require "faraday"

  def initialize(level)
    @level = level
    @base_url = "https://face.gob.es/api/v2/administraciones"
    @items = []
    @new_parents_items = []
    @ignored_parents_items = []
    @new_og_items = []
    @ignored_og_items = []
    @new_ut_items = []
    @ignored_ut_items = []
  end

  def import_new_entities
    @start_time = Time.now
    @log_file = "items_dir3"
    level_index = 1

    Rails.logger = Logger.new "#{Rails.root}/log/#{@log_file}.log"

    if @level
      get_dir3(@level)
    else
      5.times do
        get_dir3(level_index)
        level_index += 1
      end
    end

    process_entities

    execution_log
  end

  private

  def execution_log
    puts "These are the new and ignored items, see in this log: #{@log_file}"
    Rails.logger.info "******************************TIME EXECUTION #{@start_time}*********************************************"
    Rails.logger.info "*******************************************************************************************************"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "*************************************Created Parents Items*********************************************"
    Rails.logger.info @new_parents_items.empty? ? "no item processed" : format_array(@new_parents_items)
    Rails.logger.info "*******************************************************************************************************"
    Rails.logger.info "*************************************Ignored Parents Items*********************************************"
    Rails.logger.info @ignored_parents_items.empty? ? "no item ignored" : format_array(@ignored_parents_items)
    Rails.logger.info "*******************************************************************************************************"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "****************************************Created Og Items***********************************************"
    Rails.logger.info @new_og_items.empty? ? "no item processed" : format_array(@new_og_items)
    Rails.logger.info "*******************************************************************************************************"
    Rails.logger.info "****************************************Ignored Og Items***********************************************"
    Rails.logger.info @ignored_og_items.empty? ? "no item ignored" : format_array(@ignored_og_items)
    Rails.logger.info "*******************************************************************************************************"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "#######################################################################################################"
    Rails.logger.info "****************************************Created Ut Items***********************************************"
    Rails.logger.info @new_ut_items.empty? ? "no item processed" : format_array(@new_ut_items)
    Rails.logger.info "*******************************************************************************************************"
    Rails.logger.info "****************************************Ignored Ut Items***********************************************"
    Rails.logger.info @ignored_ut_items.empty? ? "no item ignored" : format_array(@ignored_ut_items)
    Rails.logger.info "*******************************************************************************************************"
    Rails.logger.info "*******************************TIME FINAL EXECUTION #{Time.now}****************************************"
  end

  def format_array(items)
    items.each_slice(15).to_a.map { |a| a.push("\n") }.join("|")
  end

  def get_dir3(level)
    page = 1

    loop do
      response = call_api_v1(level, page)
      @items.concat(response.map { |i| i["codigo_dir"] }) unless response.empty?
      page += 1
      break unless response.count.positive?
    end
  end

  def process_entities
    @dirs3_bd = Hash[FiscalEntity.pluck(:dir3, :id).collect { |x, y| [x, y] }]
    @items.each do |item|
      @aux = []
      page_hierarchy = 1

      loop do
        hierarchy = call_api_v2(item, page_hierarchy)
        @aux.concat(hierarchy.map { |i| i }) unless hierarchy.empty?
        page_hierarchy += 1
        break unless hierarchy.count.positive?
      end

      nifs = get_nifs(@aux)

      create_or_update_entities(item, @ignored_parents_items, @new_parents_items, @aux.first["administracion"]["nombre"], nifs)

      @aux.each do |i|
        # Del elemento i["oc"] como comentamos en la llamada vamos a skipearlo, pues tiene mismo dir3, pero name diferente

        create_or_update_entities(i["og"]["codigo_dir"], @ignored_og_items, @new_og_items, i["og"]["nombre"], nifs, @dirs3_bd[item])

        create_or_update_entities(i["ut"]["codigo_dir"], @ignored_ut_items, @new_ut_items, format_ut_name(i), nifs, @dirs3_bd[item])
      end
    end

    @ignored_parents_items.uniq!
    @ignored_og_items.uniq!
    @ignored_ut_items.uniq!
  end

  def create_entity(item, name, nifs, id_parent = nil)
    begin
      new_entity = FiscalEntity.new(dir3: item, name: name, nifs: nifs, parent_id: id_parent)
      new_entity.save

      new_entity
    rescue StandardError => e
      Rails.logger.error("Error creating entity #{e.message}")
      execution_log
    end
  end

  def create_or_update_entities(dir3, ignored_array, new_array, name, nifs, id_parent = nil)
    if @dirs3_bd.has_key?(dir3)
      ignored_array << dir3
    else
      new_entity = create_entity(dir3, name, nifs, id_parent)
      @dirs3_bd[dir3] = new_entity.id

      new_array << dir3
    end
  end

  def get_nifs(datas)
    nifs = []

    datas.each do |i|
      i["cifs"].each do |nif|
        nifs << nif["nif"]
      end
      i["administracion"]["cifs"].each do |nif|
        nifs << nif["nif"]
      end
    end

    nifs.uniq!
  end

  def format_ut_name(childs)
    "#{childs["og"]["nombre"]} #{childs["ut"]["nombre"]}"
  end

  def find_entity(item)
    FiscalEntity.find_by(dir3: item)
  end

  def call_api_v1(level, page)
    begin
      JSON.parse(Faraday.get("#{@base_url}?nivel=#{level}&page=#{page}").body)["items"]
    rescue StandardError => exception
      puts exception
      Rails.logger.error exception
      execution_log
    end
  end

  def call_api_v2(item, page_hierarchy)
    begin
      JSON.parse(Faraday.get("#{@base_url}/#{item}/relaciones?administracion=#{item}&page=#{page_hierarchy}&limit=10").body)["items"]
    rescue StandardError => exception
      puts exception
      Rails.logger.error exception
      execution_log
    end
  end
end
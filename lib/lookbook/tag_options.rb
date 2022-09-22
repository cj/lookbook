module Lookbook
  class TagOptions
    EVAL_OPTION_MATCH = /(\{\{\s?(.*)\s?\}\})$/
    YAML_HASH_MATCH = /(\{(.*)\})$/
    YAML_ARRAY_MATCH = /(\[(.*)\])$/
    FILE_PATH_MATCH = /(\S+\.(json|yml))$/

    def initialize(options_str, eval_scope: nil, base_dir: nil)
      @options_str = options_str.is_a?(String) ? options_str.strip : ""
      @eval_scope = eval_scope
      @base_dir = base_dir
    end

    def option(key)
      options = resolve
      options[key] if options.is_a?(Hash)
    end

    def options
      resolve
    end

    def resolve
      begin
        @resolved_options ||= if @options_str.present?
          if @options_str.end_with?(".json") || @options_str.end_with?(".yml")
            file_path = resolve_file_path
            if file_path
              options_file_content = File.read(file_path)
            else
              raise "Tag options data file not found"
            end
          end
          if file_path&.extname == ".json"
            JSON.parse(options_file_content)
          elsif file_path&.extname == ".yml"
            YAML.safe_load(options_file_content)
          elsif evaluatable?
            evaluate
          else
            YAML.safe_load(@options_str || "~")
          end
        end
      rescue => exception
        Lookbook.logger.warn Lookbook::Error.new(exception)
        {}
      end
    end

    def resolve_file_path
      path = if @options_str.start_with?(".") && @base_dir.present?
        File.expand_path(@options_str, @base_dir)
      else
        Rails.root.join(@options_str)
      end
      Pathname.new path
    end

    def evaluate
      if Lookbook.config.preview_params_options_eval == true
        if @eval_scope.nil?
          raise "Preview params eval must be scoped to an object"
        else
          evaluatable? ? @eval_scope.instance_eval(statement) : nil
        end
      else
        raise "The config option `preview_params_options_eval` must be set to `true` before param options can be evaluated at runtime"
      end
    end

    def self.extract_options(str)
      str ||= ""
      str.strip!
      opts_str = ""

      [YAML_ARRAY_MATCH, YAML_HASH_MATCH, EVAL_OPTION_MATCH, FILE_PATH_MATCH].each do |regexp|
        match_data = str.match(regexp)
        unless match_data.nil?
          str.gsub!(regexp, "").strip!
          opts_str = match_data[1]
          break
        end
      end
      
      [str, opts_str]
    end

    def self.resolveable?(str)
      return unless str.is_a?(String)
      str.strip!
      str.end_with?(".json") ||
        str.end_with?(".yml") ||
        str.match?(YAML_ARRAY_MATCH) ||
        str.match?(YAML_HASH_MATCH) ||
        str.match?(EVAL_OPTION_MATCH)
    end

    private

    def statement
      eval_match_data[2].strip if evaluatable?
    end

    def evaluatable?
      eval_match_data.present?
    end

    def eval_match_data
      @match_data ||= @options_str.match(EVAL_OPTION_MATCH)
    end
  end
end
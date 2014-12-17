class Roda
	module RodaPlugins

		module RestApi

			APPLICATION_JSON = 'application/json'.freeze
			SINGLETON_ROUTES = %i{ show create update destroy edit new }.freeze

			def self.load_dependencies(app, _opts = {})
				app.plugin :all_verbs
				app.plugin :symbol_matchers
				app.plugin :header_matchers
				app.plugin :static_path_info
			end
			
			class Resource
				
				attr_reader :request, :path, :singleton, :content_type, :parent
				attr_accessor :captures
				
				def initialize(path, request, parent, options={})
					@request = request
					@path = path.to_s
					bare = options.delete(:bare) || false
					@singleton = options.delete(:singleton) || false
					@primary_key = options.delete(:primary_key) || "id"
					@parent_key = options.delete(:parent_key) || "parent_id"
					@content_type = options.delete(:content_type) || APPLICATION_JSON
					if parent
						@parent = parent
						@path = [':d', @path].join('/') unless bare
					end
				end
								
				def list(&block)
					@list = block if block
					@list || ->(_){raise NotImplementedError, "list"}
				end
				
				def one(&block)
					@one = block if block
					@one || ->(_){raise NotImplementedError, "one"}
				end
				
				def save(&block)
					@save = block if block
					@save || ->(_){raise NotImplementedError, "save"}
				end
				
				def delete(&block)
					@delete = block if block
					@delete || ->(_){raise NotImplementedError, "delete"}
				end
				
				def serialize(&block)
					@serialize = block if block
					@serialize || ->(obj){obj.is_a?(String) ? obj : obj.send(:to_json)}
				end
				
				def routes(*routes)
					@routes = routes
				end
					
				def routes!
					unless @routes
						@routes = SINGLETON_ROUTES.dup
						@routes << :index unless @singleton
					end
					@routes.each { |route| @request.send(route) }
				end
				
				def perform(method, id = nil)
					begin
						args = method === :save ? JSON.parse(@request.body) : @request.GET
						args.merge!(@primary_key => id) if id
						args.merge!(@parent_key => @captures[0]) if @captures
						self.send(method).call(args)
					rescue StandardError => e
						raise if ENV['RACK_ENV'] == 'development'
						@request.response.status = method === :save ? 422 : 404
					end
				end

			end
			
			module RequestMethods
				
				def api(options={}, &block)
					path = options.delete(:path) || 'api'
					subdomain = options.delete(:subdomain)
					options.merge!(host: /\A#{Regexp.escape(subdomain)}\./) if subdomain
					on([path, true], options, &block)
				end

				def version(version, &block)
			  		on("v#{version}", &block)
				end

				def resource(path, options={})
					@resource = Resource.new(path, self, @resource, options)
					on(@resource.path, options) do
						@resource.captures = captures.dup unless captures.empty?
						yield @resource
					 	@resource.routes!
						response.status = 404
				  end
				 	@resource = @resource.parent
				end

			  def index(options={}, &block)
				  block ||= ->{ @resource.perform(:list) }
					get(['', true], options, &block)
			  end

			  def show(options={}, &block)
				  block ||= default_block(:one)
					get(path, options, &block)
			  end

			  def create(options={}, &block)
				 	block ||= ->{@resource.perform(:save)}
					post(["", true], options) do
						response.status = 201
						block.call(*captures) if block
					end
			  end

			  def update(options={}, &block)
					block ||= default_block(:save)
				  options.merge!(method: [:put, :patch])
					is(path, options, &block)
			  end

			  def destroy(options={}, &block)
					block ||= default_block(:delete)
					delete(path, options) do
						response.status = 204
						block.call(*captures) if block
					end
			  end

			  def edit(options={}, &block)
					block ||= default_block(:one)
					get(path("edit"), options, &block)
			  end

			  def new(options={}, &block)
				  block ||= ->{@resource.perform(:one, "new")}
					get("new", options, &block)
			  end
				
			  private
			  
			  def path(path=nil)
				  if @resource.singleton
						path = ["", true] unless path
					else
						path = [":d", path].compact.join("/")
					end
					path
				end
				
				def default_block(method)
					if @resource.singleton
						->(){@resource.perform(method)}
					else
						->(id){@resource.perform(method, id)}
					end
				end
			  
			  CONTENT_TYPE = 'Content-Type'.freeze

			  def block_result_body(result)
				  if result && @resource
				  		response[CONTENT_TYPE] = @resource.content_type
				  		@resource.serialize.call(result)
				  	else
					  	super
					end
			  end
			  
			end
		end

		register_plugin(:rest_api, RestApi)

	end
end